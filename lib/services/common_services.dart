/*
 *     Copyright (C) 2026 ghhn
 *
 *     Ritmoo is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Ritmoo is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Ritmoo, including how to contribute,
 *     please visit: https://github.com/ghhn/Ritmoo
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:ritmoo/constants/clients.dart';
import 'package:ritmoo/database/playlists.db.dart';
import 'package:ritmoo/database/sample_songs.db.dart';
import 'package:ritmoo/main.dart' show logger;
import 'package:ritmoo/services/data_manager.dart';
import 'package:ritmoo/services/io_service.dart';
import 'package:ritmoo/services/lyrics_manager.dart';
import 'package:ritmoo/services/playlists_manager.dart';
import 'package:ritmoo/services/proxy_manager.dart';
import 'package:ritmoo/services/settings_manager.dart';
import 'package:ritmoo/services/youtube_timeout.dart';
import 'package:ritmoo/utilities/app_utils.dart';
import 'package:ritmoo/utilities/formatter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

List globalSongs = [];

List userLikedSongsList = Hive.box('user').get('likedSongs', defaultValue: []);

List userRecentlyPlayed = Hive.box(
  'user',
).get('recentlyPlayedSongs', defaultValue: []);
List userOfflineSongs = Hive.box(
  'userNoBackup',
).get('offlineSongs', defaultValue: []);

dynamic nextRecommendedSong;

final currentLikedSongsLength = ValueNotifier<int>(userLikedSongsList.length);
final currentOfflineSongsLength = ValueNotifier<int>(userOfflineSongs.length);
final currentRecentlyPlayedLength = ValueNotifier<int>(
  userRecentlyPlayed.length,
);
final recentlyPlayedVersion = ValueNotifier<int>(0);

final lyrics = ValueNotifier<String?>(null);
String? lastFetchedLyrics;

// Timeouts and durations used across manifest fetching and cache validation.
const Duration _manifestTimeout = Duration(seconds: 12);
const Duration _perClientTimeout = Duration(seconds: 8);
const Duration _cacheValidationDuration = Duration(hours: 1);

// Ordered fallback clients to try when the primary list fails.
final _fallbackClients = [
  YoutubeApiClient.androidVr,
  YoutubeApiClient.tv,
  YoutubeApiClient.ios,
  YoutubeApiClient.mweb,
  YoutubeApiClient.androidMusic,
  YoutubeApiClient.androidSdkless,
];

/// Fetches a stream manifest for a song, honoring proxy settings.
/// Tries the configured client list first, then falls back to individual
/// clients one by one to maximize success rate.
Future<StreamManifest?> _fetchStreamManifest(String songId) async {
  if (useProxy.value) {
    return ProxyManager().getSongManifest(songId).timeout(_manifestTimeout);
  }

  // Fast direct attempt: bypasses scraping the web watch page
  try {
    final result = await ytClient.videos.streams
        .getManifest(songId, ytClients: customClients, requireWatchPage: false)
        .timeout(_manifestTimeout);
    // Validate that the manifest actually contains audio streams
    if (result.audioOnly.isNotEmpty) return result;
    logger.log('Fast direct attempt returned empty audio streams for $songId, continuing...');
  } catch (e) {
    logger.log('Fast direct client list failed for $songId, trying standard: $e');
  }

  // Standard attempt: with watch page if deciphering is needed
  try {
    final result = await ytClient.videos.streams
        .getManifest(songId, ytClients: customClients)
        .timeout(_manifestTimeout);
    // Validate that the manifest actually contains audio streams
    if (result.audioOnly.isNotEmpty) return result;
    logger.log('Primary attempt returned empty audio streams for $songId, trying fallbacks...');
  } catch (e) {
    logger.log('Primary client list failed for $songId, trying fallbacks: $e');
  }

  // Fallback: try each client individually
  for (final client in _fallbackClients) {
    try {
      final result = await ytClient.videos.streams
          .getManifest(songId, ytClients: [client], requireWatchPage: false)
          .timeout(_perClientTimeout);
      if (result.audioOnly.isNotEmpty) {
        logger.log('Fallback client succeeded for $songId');
        return result;
      }
    } catch (_) {
      try {
        final resultWithWatchPage = await ytClient.videos.streams
            .getManifest(songId, ytClients: [client])
            .timeout(_perClientTimeout);
        if (resultWithWatchPage.audioOnly.isNotEmpty) {
          logger.log('Fallback client with watch page succeeded for $songId');
          return resultWithWatchPage;
        }
      } catch (e) {
        logger.log('Fallback client failed for $songId: $e');
      }
    }
  }

  return null;
}

/// Returns a cached song URL if present and still valid.
Future<String?> _getCachedSongUrl(
  String cacheKey,
  Duration cacheDuration,
) async {
  final cachedUrl = await getData(
    'cache',
    cacheKey,
    cachingDuration: cacheDuration,
  );

  if (cachedUrl is! String || cachedUrl.isEmpty) {
    return null;
  }

  // Use Hive.box (not openBox) — the 'cache' box is already open since
  // initialisation() in main.dart. Calling openBox again can cause
  // race conditions and unnecessary async overhead.
  final cacheBox = Hive.box('cache');
  final cacheDate = cacheBox.get('${cacheKey}_date') as DateTime?;
  final now = DateTime.now();
  final isOld =
      cacheDate != null && now.difference(cacheDate) > _cacheValidationDuration;

  if (!isOld) {
    return cachedUrl;
  }

  if (await _validateCachedUrl(cachedUrl)) {
    return cachedUrl;
  }

  await deleteData('cache', cacheKey);
  await deleteData('cache', '${cacheKey}_date');
  return null;
}

/// Checks if a cached URL still responds successfully.
/// Note: YouTube CDN often returns 403 on HEAD requests even for valid stream URLs,
/// so we accept 403 as potentially valid and let the player handle actual playback errors.
Future<bool> _validateCachedUrl(String cachedUrl) async {
  try {
    final response = await http.head(Uri.parse(cachedUrl));
    // Accept 2xx AND 403 (YouTube CDN blocks HEAD but stream may still be playable)
    return response.statusCode >= 200 && response.statusCode < 300 ||
        response.statusCode == 403;
  } catch (_) {
    return false;
  }
}

Future<bool> _validateStreamUrl(String streamUrl) async {
  try {
    final response = await http.head(
      Uri.parse(streamUrl),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
        'Referer': 'https://www.youtube.com/',
      },
    ).timeout(const Duration(seconds: 6));

    return response.statusCode >= 200 && response.statusCode < 300 ||
        response.statusCode == 403;
  } catch (_) {
    return false;
  }
}

Future<List> fetchSongsList(String searchQuery) async {
  try {
    final searchResults = await youtubeRequest<List<Video>>(
      operation: 'search songs for "$searchQuery"',
      request: () => ytClient.search.search(searchQuery),
      fallback: <Video>[],
    );
    final songsList = searchResults
        .map((video) => returnSongLayout(0, video))
        .toList();

    return songsList;
  } catch (e, stackTrace) {
    logger.log('Error in fetchSongsList', error: e, stackTrace: stackTrace);
    return [];
  }
}

Future<List> getRecommendedSongs() async {
  try {
    if (externalRecommendations.value && userRecentlyPlayed.isNotEmpty) {
      return await _getRecommendationsFromRecentlyPlayed();
    } else {
      return await _getRecommendationsFromMixedSources();
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error in getRecommendedSongs',
      error: e,
      stackTrace: stackTrace,
    );
    return [];
  }
}

Future<List> _getRecommendationsFromRecentlyPlayed() async {
  final recent = (List.from(userRecentlyPlayed)..shuffle()).take(3).toList();

  final futures = recent.map((songData) async {
    try {
      final song = await ytClient.videos.get(songData['ytid']);
      final relatedSongs = await ytClient.videos.getRelatedVideos(song) ?? [];
      return relatedSongs.take(3).map((s) => returnSongLayout(0, s)).toList();
    } catch (e, stackTrace) {
      logger.log(
        'Error getting related videos for ${songData['ytid']}',
        error: e,
        stackTrace: stackTrace,
      );
      return <Map>[];
    }
  }).toList();

  final results = await Future.wait(futures);
  // Limit to 15 items max for performance
  final playlistSongs = results.expand((list) => list).take(15).toList()
    ..shuffle();
  return playlistSongs;
}

List latinSongs = [];

Future<List> _getRecommendationsFromMixedSources() async {
  final playlistSongs = [...userLikedSongsList, ...userRecentlyPlayed];

  if (globalSongs.isEmpty) {
    const playlistId = 'PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx'; // Global / English Trending
    globalSongs = await getSongsFromPlaylist(playlistId);
  }
  if (latinSongs.isEmpty) {
    const latinPlaylistId = 'PL3-sRm8WVJLPx2jV4s_y8qU9R0U3S-29d'; // Spanish / Latino Trending
    latinSongs = await getSongsFromPlaylist(latinPlaylistId);
  }

  playlistSongs
    ..addAll(globalSongs.take(8))
    ..addAll(latinSongs.take(8));

  if (userCustomPlaylists.value.isNotEmpty) {
    for (final userPlaylist in userCustomPlaylists.value) {
      final _list = List.from(userPlaylist['list'] as List)..shuffle();
      playlistSongs.addAll(_list.take(5));
    }
  }

  return _deduplicateAndShuffle(playlistSongs);
}

List<Map<String, dynamic>> getSampleSongs({int? limit}) {
  final list = List<Map<String, dynamic>>.from(sampleSongsDB);
  if (limit != null && limit > 0) {
    return list.take(limit).toList();
  }
  return list;
}

List _deduplicateAndShuffle(List playlistSongs) {
  final seenYtIds = <String>{};
  final uniqueSongs = <Map>[];

  final songsToProcess =
      (playlistSongs.isNotEmpty
            ? List.from(playlistSongs)
            : List.from(sampleSongsDB))
        ..shuffle();

  for (final song in songsToProcess) {
    if (song['ytid'] != null && seenYtIds.add(song['ytid'])) {
      uniqueSongs.add(song);
      // Early exit when we have enough songs
      if (uniqueSongs.length >= 15) break;
    }
  }

  if (uniqueSongs.isEmpty) {
    return List<Map<String, dynamic>>.from(sampleSongsDB);
  }

  return uniqueSongs;
}

Future<void> updateSongLikeStatus(dynamic songId, bool add) async {
  try {
    if (add) {
      if (!userLikedSongsList.any((song) => song['ytid'] == songId)) {
        final songDetails = await getSongDetails(
          userLikedSongsList.length,
          songId,
        );
        userLikedSongsList.add(songDetails);
      }
    } else {
      userLikedSongsList.removeWhere((song) => song['ytid'] == songId);
    }

    currentLikedSongsLength.value = userLikedSongsList.length;
    unawaited(addOrUpdateData('user', 'likedSongs', userLikedSongsList));
  } catch (e, stackTrace) {
    logger.log(
      'Error updating song like status',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

void moveLikedSong(int oldIndex, int newIndex) {
  if (oldIndex < newIndex) {
    newIndex -= 1;
  }
  final _song = userLikedSongsList.removeAt(oldIndex);
  userLikedSongsList.insert(newIndex, _song);
  currentLikedSongsLength.value = userLikedSongsList.length;
  unawaited(addOrUpdateData('user', 'likedSongs', userLikedSongsList));
}

Future<void> renameSongInLikedSongs(
  dynamic songId,
  String newTitle,
  String newArtist,
) async {
  try {
    final songIndex = userLikedSongsList.indexWhere(
      (song) => song['ytid'] == songId,
    );

    if (songIndex != -1) {
      userLikedSongsList[songIndex]['title'] = newTitle;
      userLikedSongsList[songIndex]['artist'] = newArtist;

      currentLikedSongsLength.value = userLikedSongsList.length;
      unawaited(addOrUpdateData('user', 'likedSongs', userLikedSongsList));
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error renaming song in liked songs',
      error: e,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

bool isSongAlreadyLiked(songIdToCheck) =>
    userLikedSongsList.any((song) => song['ytid'] == songIdToCheck);

bool isPlaylistAlreadyLiked(playlistIdToCheck) =>
    userLikedPlaylists.any((playlist) => playlist['ytid'] == playlistIdToCheck);

bool isSongAlreadyOffline(songIdToCheck) =>
    userOfflineSongs.any((song) => song['ytid'] == songIdToCheck);

bool isPlaylistFullyOffline(List songs) {
  if (songs.isEmpty) return false;
  final offlineIds = userOfflineSongs.map((s) => s['ytid']).toSet();
  return songs.every((s) => offlineIds.contains(s['ytid']));
}

Map<String, dynamic> getOfflineSongByYtid(String ytid) {
  try {
    final song = userOfflineSongs.firstWhere(
      (s) => s['ytid'] == ytid,
      orElse: () => <String, dynamic>{},
    );
    return Map<String, dynamic>.from(song);
  } catch (_) {
    return <String, dynamic>{};
  }
}

Future<List<String>> getSearchSuggestions(String query) async {
  // Built-in implementation with timeout guard.
  final suggestions = await youtubeRequest<List<String>>(
    operation: 'search suggestions for "$query"',
    request: () => ytClient.search.getQuerySuggestions(query),
    timeout: const Duration(seconds: 6),
    fallback: <String>[],
  );

  return suggestions;
}

Future<List<Map<String, int>>> getSkipSegments(String id) async {
  try {
    final res = await ProxyManager().getProxiedResponse(
      Uri(
        scheme: 'https',
        host: 'sponsor.ajay.app',
        path: '/api/skipSegments',
        queryParameters: {
          'videoID': id,
          'category': [
            'sponsor',
            'selfpromo',
            'interaction',
            'intro',
            'outro',
            'music_offtopic',
          ],
          'actionType': 'skip',
        },
      ),
    );
    if (res.statusCode == 200 && res.body != 'Not Found') {
      final data = jsonDecode(res.body);
      final segments = data.map((obj) {
        return Map.castFrom<String, dynamic, String, int>({
          'start': obj['segment'].first.toInt(),
          'end': obj['segment'].last.toInt(),
        });
      }).toList();
      return List.castFrom<dynamic, Map<String, int>>(segments);
    } else {
      return [];
    }
  } catch (e, stackTrace) {
    logger.log('Error in getSkipSegments', error: e, stackTrace: stackTrace);
    return [];
  }
}

Future<void> getSimilarSong(String songYtId) async {
  try {
    if (!offlineMode.value) {
      final song = await youtubeRequest<Video?>(
        operation: 'fetch similar song details for $songYtId',
        request: () => ytClient.videos.get(songYtId),
      );
      if (song == null) {
        throw const FormatException('No video metadata returned');
      }
        final relatedSongs = await youtubeRequest<List<Video>>(
          operation: 'fetch related songs for $songYtId',
          request: () async {
            final videos = await ytClient.videos.getRelatedVideos(song);
            return videos ?? const <Video>[];
          },
        );

      if (relatedSongs.isNotEmpty) {
        nextRecommendedSong = returnSongLayout(0, relatedSongs.first);
        return;
      }
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error while fetching next similar song from YouTube:',
      error: e,
      stackTrace: stackTrace,
    );
  }

  // Fallback to related songs from playlistsDB and sampleSongsDB
  try {
    final pool = <Map>[];
    for (final p in playlistsDB) {
      final pList = p['list'] as List? ?? [];
      for (final s in pList) {
        if (s is Map && s['ytid'] != songYtId) pool.add(s);
      }
    }
    pool.addAll(sampleSongsDB.where((s) => s['ytid'] != songYtId));
    if (pool.isNotEmpty) {
      pool.shuffle();
      nextRecommendedSong = pool.first;
    }
  } catch (e) {
    logger.log('Fallback similar song selection failed: $e');
  }
}

/// Fetches the best available audio stream for a song.
Future<AudioOnlyStreamInfo?> fetchBestAudioStream(String? songId) async {
  try {
    if (songId == null || songId.isEmpty) {
      logger.log('fetchBestAudioStream: songId is null or empty');
      return null;
    }

    final manifest = await _fetchStreamManifest(songId);
    final audioStream = manifest?.audioOnly;
    if (audioStream == null || audioStream.isEmpty) {
      logger.log('fetchBestAudioStream: no audio streams for $songId');
      return null;
    }
    return selectAudioOnlyStreamForQuality(audioStream.sortByBitrate());
  } on TimeoutException catch (_) {
    logger.log('fetchBestAudioStream request timed out for $songId');
    return null;
  } catch (e, stackTrace) {
    logger.log(
      'Error while fetching best audio stream',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// Resolves a playable stream URL for a song (cached when possible).
Future<String?> fetchSongStreamUrl(String songId, bool isLive) async {
  try {
    if (songId.isEmpty) {
      logger.log('fetchSongStreamUrl: songId is empty');
      return null;
    }
    if (isLive) {
      final streamInfo = await ytClient.videos.streamsClient
          .getHttpLiveStreamUrl(VideoId(songId));
      return streamInfo;
    }

    const _cacheDuration = Duration(hours: 3);
    final cacheKey = 'song_${songId}_${audioQualitySetting.value}_url';

    // Try to get from cache
    final cachedUrl = await _getCachedSongUrl(cacheKey, _cacheDuration);
    if (cachedUrl != null) {
      return cachedUrl;
    }

    // Get fresh URL
    final manifest = await _fetchStreamManifest(songId);
    final audioStreams = manifest?.audioOnly;
    if (audioStreams == null || audioStreams.isEmpty) {
      logger.log('fetchSongStreamUrl: no audio streams for $songId');
      return null;
    }

    final streamCandidates = List<AudioOnlyStreamInfo>.from(
      audioStreams.sortByBitrate(),
    )..sort((a, b) => b.bitrate.compareTo(a.bitrate));

    for (final stream in streamCandidates) {
      final url = stream.url.toString();
      if (url.isEmpty) continue;

      final urlIsValid = await _validateStreamUrl(url);
      if (urlIsValid) {
        unawaited(addOrUpdateData('cache', cacheKey, url));
        return url;
      }

      logger.log('Skipping non-playable stream candidate for $songId: $url');
    }

    final selectedStream = selectAudioOnlyStreamForQuality(
      audioStreams.sortByBitrate(),
    );
    final url = selectedStream.url.toString();

    unawaited(addOrUpdateData('cache', cacheKey, url));

    return url;
  } on TimeoutException catch (_) {
    logger.log('fetchSongStreamUrl request timed out for $songId');
    return null;
  } catch (e, stackTrace) {
    logger.log(
      'Error in fetchSongStreamUrl for $songId:',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}

Future<Map<String, dynamic>> getSongDetails(
  int songIndex,
  String songId,
) async {
  try {
    final song = await youtubeRequest<Video?>(
      operation: 'fetch song details for $songId',
      request: () => ytClient.videos.get(songId),
    );
    if (song == null) {
      return <String, dynamic>{};
    }
    return returnSongLayout(songIndex, song);
  } catch (e, stackTrace) {
    logger.log(
      'Error while getting song details',
      error: e,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

Future<String?> getSongLyrics(String? artist, String title) async {
  if (artist == null) return null;
  if (lastFetchedLyrics != '$artist - $title') {
    lyrics.value = null;
    var _lyrics = await LyricsManager().fetchLyrics(artist, title);
    if (_lyrics != null) {
      _lyrics = _lyrics.replaceAll(RegExp(r'\n{4}'), '\n\n');
      _lyrics = _lyrics.replaceAll(RegExp(r'\n{2}'), '\n');
      lyrics.value = _lyrics;
    } else {
      return null;
    }

    lastFetchedLyrics = '$artist - $title';
    return _lyrics;
  }

  return lyrics.value;
}

Future<bool> makeSongOffline(dynamic song) async {
  try {
    final String? ytid = song['ytid'];

    if (ytid == null || ytid.isEmpty) {
      logger.log('makeSongOffline: song["ytid"] is null or empty');
      return false;
    }

    if (isSongAlreadyOffline(ytid)) {
      return true;
    }

    final offlineSong = Map<String, dynamic>.from(song as Map);

    final audioPath = FilePaths.getAudioPath(ytid);
    final audioFile = File(audioPath);
    final artworkPath = FilePaths.getArtworkPath(ytid);

    await audioFile.parent.create(recursive: true);

    IOSink? fileStream;
    try {
      final audioManifest = await fetchBestAudioStream(ytid);
      if (audioManifest == null) {
        logger.log('makeSongOffline: audioManifest is null for $ytid');
        return false;
      }

      final stream = ytClient.videos.streamsClient.get(audioManifest);
      fileStream = audioFile.openWrite();
      await stream.pipe(fileStream);
      await fileStream.flush();
      await fileStream.close();
      fileStream = null;
    } catch (e, stackTrace) {
      logger.log(
        'Error downloading audio file',
        error: e,
        stackTrace: stackTrace,
      );
      try {
        await fileStream?.close();
      } catch (_) {}
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
      return false;
    }

    try {
      if (offlineSong['highResImage'] != null &&
          offlineSong['highResImage'].toString().isNotEmpty) {
        final _artworkFile = await _downloadAndSaveArtworkFile(
          offlineSong['highResImage'],
          artworkPath,
        );

        if (_artworkFile != null && await _artworkFile.exists()) {
          offlineSong['artworkPath'] = artworkPath;
        } else {
          logger.log(
            'Artwork download failed or file does not exist for $ytid',
          );
          offlineSong['artworkPath'] = null;
        }
      }
    } catch (e, stackTrace) {
      logger.log('Error downloading artwork', error: e, stackTrace: stackTrace);
      offlineSong['artworkPath'] = null;
    }

    offlineSong['audioPath'] = audioFile.path;
    offlineSong['dateAdded'] = DateTime.now().millisecondsSinceEpoch;

    try {
      final existingIndex = userOfflineSongs.indexWhere(
        (s) => s['ytid'] == ytid,
      );

      if (existingIndex != -1) {
        userOfflineSongs[existingIndex] = offlineSong;
      } else {
        userOfflineSongs.add(offlineSong);
      }

      unawaited(
        addOrUpdateData('userNoBackup', 'offlineSongs', userOfflineSongs),
      );
      currentOfflineSongsLength.value = userOfflineSongs.length;
    } catch (e, st) {
      logger.log(
        'Error updating global offline songs list',
        error: e,
        stackTrace: st,
      );
    }

    return true;
  } catch (e, stackTrace) {
    logger.log('Error making song offline', error: e, stackTrace: stackTrace);
    return false;
  }
}

Future<bool> removeSongFromOffline(dynamic songId) async {
  try {
    final audioPath = FilePaths.getAudioPath(songId);
    final audioFile = File(audioPath);
    final artworkPath = FilePaths.getArtworkPath(songId);
    final artworkFile = File(artworkPath);

    try {
      if (await audioFile.exists()) await audioFile.delete(recursive: true);
    } catch (e, stackTrace) {
      logger.log('Error deleting audio file', error: e, stackTrace: stackTrace);
    }

    try {
      if (await artworkFile.exists()) await artworkFile.delete(recursive: true);
    } catch (e, stackTrace) {
      logger.log(
        'Error deleting artwork file',
        error: e,
        stackTrace: stackTrace,
      );
    }

    try {
      userOfflineSongs.removeWhere((song) => song['ytid'] == songId);
      currentOfflineSongsLength.value = userOfflineSongs.length;
      unawaited(
        addOrUpdateData('userNoBackup', 'offlineSongs', userOfflineSongs),
      );
    } catch (e, st) {
      logger.log(
        'Error updating offline songs registry after removal',
        error: e,
        stackTrace: st,
      );
    }

    return true;
  } catch (e, stackTrace) {
    logger.log(
      'Error removing song from offline storage',
      error: e,
      stackTrace: stackTrace,
    );
    return false;
  }
}

Future<File?> _downloadAndSaveArtworkFile(String url, String filePath) async {
  try {
    final response = await ProxyManager().getProxiedResponse(Uri.parse(url));

    if (response.statusCode == 200) {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);

      // Validate that the file was actually written
      if (await file.exists() && await file.length() > 0) {
        return file;
      } else {
        logger.log('Artwork file was not written properly: $filePath');
        return null;
      }
    } else {
      logger.log(
        'Failed to download file. Status code: ${response.statusCode}',
      );
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error downloading and saving file',
      error: e,
      stackTrace: stackTrace,
    );
  }

  return null;
}

const recentlyPlayedSongsLimit = 250;

/// Updates the recently played list and listening count for [songId].
///
/// When [songFallback] is provided, its metadata is used to seed the history
/// entry if the song has never been played before. This avoids a network
/// request when registering offline songs whose metadata is already available
/// locally (e.g. from [userOfflineSongs]).
Future<void> updateRecentlyPlayed(dynamic songId, {Map? songFallback}) async {
  try {
    if (userRecentlyPlayed.isNotEmpty &&
        userRecentlyPlayed[0]['ytid'] == songId) {
      final existing = userRecentlyPlayed[0] as Map;
      existing['listeningCount'] = (existing['listeningCount'] ?? 0) + 1;
      existing['lastPlayed'] = DateTime.now();
      recentlyPlayedVersion.value++;
      unawaited(
        addOrUpdateData('user', 'recentlyPlayedSongs', userRecentlyPlayed),
      );
      return;
    }

    final existingIndex = userRecentlyPlayed.indexWhere(
      (song) => song['ytid'] == songId,
    );

    if (existingIndex == -1 &&
        userRecentlyPlayed.length >= recentlyPlayedSongsLimit) {
      userRecentlyPlayed.removeLast();
    }

    if (existingIndex != -1) {
      final song = userRecentlyPlayed.removeAt(existingIndex) as Map;
      song['listeningCount'] = (song['listeningCount'] ?? 0) + 1;
      song['lastPlayed'] = DateTime.now();
      userRecentlyPlayed.insert(0, song);
    } else {
      final newSongDetails = songFallback != null
          ? Map<String, dynamic>.from(songFallback)
          : await getSongDetails(0, songId);
      newSongDetails['listeningCount'] = 1;
      newSongDetails['lastPlayed'] = DateTime.now();
      userRecentlyPlayed.insert(0, newSongDetails);
    }

    currentRecentlyPlayedLength.value = userRecentlyPlayed.length;
    recentlyPlayedVersion.value++;
    unawaited(
      addOrUpdateData('user', 'recentlyPlayedSongs', userRecentlyPlayed),
    );
  } catch (e, stackTrace) {
    logger.log(
      'Error updating recently played',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

Future<void> removeFromRecentlyPlayed(dynamic songId) async {
  if (userRecentlyPlayed.any((song) => song['ytid'] == songId)) {
    userRecentlyPlayed.removeWhere((song) => song['ytid'] == songId);
    currentRecentlyPlayedLength.value = userRecentlyPlayed.length;
    recentlyPlayedVersion.value++;
    unawaited(
      addOrUpdateData('user', 'recentlyPlayedSongs', userRecentlyPlayed),
    );
  }
}

/// Returns the most-played songs, ordered by `listeningCount` desc and
/// `lastPlayed` desc as a tiebreaker. Does not mutate the persisted list.
List<Map> getMostPlayed({int limit = 20, bool deduplicate = true}) {
  final copy = List<Map>.from(userRecentlyPlayed);

  if (deduplicate) {
    final seen = <String>{};
    copy.removeWhere((m) {
      final id = m['ytid']?.toString();
      if (id == null) return true;
      if (seen.contains(id)) return true;
      seen.add(id);
      return false;
    });
  }

  copy.sort((a, b) {
    final ai = (a['listeningCount'] is int)
        ? a['listeningCount'] as int
        : int.tryParse(a['listeningCount']?.toString() ?? '') ?? 0;
    final bi = (b['listeningCount'] is int)
        ? b['listeningCount'] as int
        : int.tryParse(b['listeningCount']?.toString() ?? '') ?? 0;
    if (ai != bi) return bi.compareTo(ai);

    final ad = a['lastPlayed'] is DateTime
        ? a['lastPlayed'] as DateTime
        : DateTime.tryParse(a['lastPlayed']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
    final bd = b['lastPlayed'] is DateTime
        ? b['lastPlayed'] as DateTime
        : DateTime.tryParse(b['lastPlayed']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
    return bd.compareTo(ad);
  });

  return copy.take(limit).toList();
}
