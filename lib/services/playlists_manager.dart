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

import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:ritmoo/database/albums.db.dart';
import 'package:ritmoo/database/playlists.db.dart';
import 'package:ritmoo/database/sample_songs.db.dart';
import 'package:ritmoo/extensions/l10n.dart';
import 'package:ritmoo/main.dart' show audioHandler, logger;
import 'package:ritmoo/services/data_manager.dart';
import 'package:ritmoo/services/playlist_download_service.dart';
import 'package:ritmoo/services/proxy_manager.dart';
import 'package:ritmoo/services/settings_manager.dart';
import 'package:ritmoo/services/youtube_timeout.dart';
import 'package:ritmoo/utilities/app_utils.dart';
import 'package:ritmoo/utilities/flutter_toast.dart';
import 'package:ritmoo/utilities/formatter.dart';
import 'package:ritmoo/utilities/playlist_utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

List<Map> playlists = [...playlistsDB, ...albumsDB];
final userPlaylists = ValueNotifier<List<String>>(
  List<String>.from(Hive.box('user').get('playlists', defaultValue: [])),
);
final userCustomPlaylists = ValueNotifier<List<Map>>(
  List<Map>.from(Hive.box('user').get('customPlaylists', defaultValue: [])),
);
List<Map> userLikedPlaylists = List<Map>.from(
  Hive.box('user').get('likedPlaylists', defaultValue: []),
);
final userPlaylistFolders = ValueNotifier<List<Map>>(
  List<Map>.from(Hive.box('user').get('playlistFolders', defaultValue: [])),
);
final pinnedPlaylistIds = ValueNotifier<List<String>>(
  List<String>.from(
    Hive.box('user').get('pinnedPlaylistIds', defaultValue: <String>[]),
  ),
);
final onlinePlaylists = ValueNotifier<List<Map>>([]);
void _updateOnlineCache(Map? p) {
  if (p != null && !onlinePlaylists.value.any((x) => x['ytid'] == p['ytid'])) {
    onlinePlaylists.value = [...onlinePlaylists.value, p];
  }
}

Map? _searchAppPlaylistsById(String id) {
  for (final p in userCustomPlaylists.value) {
    if (p['ytid']?.toString() == id) return p;
  }
  for (final f in userPlaylistFolders.value) {
    for (final p in (f['playlists'] as List? ?? [])) {
      if (p['ytid']?.toString() == id) return p as Map;
    }
  }
  for (final p in userLikedPlaylists) {
    if (p['ytid']?.toString() == id) return p;
  }
  for (final p in onlinePlaylists.value) {
    if (p['ytid']?.toString() == id) return p;
  }
  for (final p in offlinePlaylistService.offlinePlaylists.value) {
    if (p['ytid']?.toString() == id) return p as Map;
  }
  for (final p in playlists) {
    if (p['ytid']?.toString() == id) return p;
  }
  return null;
}

List<Map> resolvePinnedPlaylists(List<String> ids) {
  if (ids.isEmpty) return [];
  final result = <Map>[];
  for (final id in ids) {
    final match = _searchAppPlaylistsById(id);
    if (match != null) result.add(match);
  }
  return result;
}

const pinnedPlaylistsLimit = 5;

final currentLikedPlaylistsLength = ValueNotifier<int>(
  userLikedPlaylists.length,
);

Future<List<dynamic>> getUserPlaylists() async {
  final futures = userPlaylists.value.map((playlistID) async {
    try {
      final plist = await ytClient.playlists.get(playlistID);
      return {
        'ytid': plist.id.toString(),
        'title': plist.title,
        'image': null,
        'source': 'user-youtube',
        'list': [],
      };
    } catch (e, stackTrace) {
      logger.log(
        'Error occurred while fetching the playlist:',
        error: e,
        stackTrace: stackTrace,
      );
      return {
        'ytid': playlistID,
        'title': 'Failed playlist',
        'image': null,
        'source': 'user-youtube',
        'list': [],
      };
    }
  });

  final results = await Future.wait(futures);
  for (final result in results) {
    _updateOnlineCache(result);
  }
  return results.toList();
}

Future<String> addUserPlaylist(String input, BuildContext context) async {
  String? playlistId = input;

  if (input.startsWith('http://') || input.startsWith('https://')) {
    playlistId = extractYoutubePlaylistId(input);
  }

  if (playlistId == null || playlistId.isEmpty) {
    return '${context.l10n!.invalidYouTubePlaylist}!';
  }

  final nonNullPlaylistId = playlistId; // Promote to non-null type

  try {
    if (playlistExistsAnywhere(nonNullPlaylistId)) {
      return '${context.l10n!.playlistAlreadyExists}!';
    }

    final playlist = await ytClient.playlists.get(nonNullPlaylistId);
    if (playlist.title.isEmpty) {
      return '${context.l10n!.invalidYouTubePlaylist}!';
    }

    userPlaylists.value = [...userPlaylists.value, nonNullPlaylistId];
    unawaited(addOrUpdateData('user', 'playlists', userPlaylists.value));
    return '${context.l10n!.addedSuccess}!';
  } catch (e, stackTrace) {
    logger.log('Error adding user playlist', error: e, stackTrace: stackTrace);
    return '${context.l10n!.error}: $e';
  }
}

(String message, String playlistId) createCustomPlaylist(
  String playlistName,
  String? image,
  BuildContext context,
) {
  final newPlaylistId = PlaylistUtils.generateCustomPlaylistId();
  final creationTime = DateTime.now().millisecondsSinceEpoch;
  final customPlaylist = {
    'ytid': newPlaylistId,
    'title': playlistName,
    'source': 'user-created',
    if (image != null) 'image': image,
    'list': [],
    'createdAt': creationTime,
  };
  userCustomPlaylists.value = [...userCustomPlaylists.value, customPlaylist];
  unawaited(
    addOrUpdateData('user', 'customPlaylists', userCustomPlaylists.value),
  );
  return ('${context.l10n!.addedSuccess}!', newPlaylistId);
}

String addSongInCustomPlaylist(
  BuildContext context,
  String playlistId,
  Map song, {
  int? indexToInsert,
}) {
  final found = _findCustomPlaylist(playlistId);
  final customPlaylist = found?.playlist;
  final isFromFolder = found?.isFromFolder ?? false;

  if (customPlaylist != null) {
    final List<dynamic> playlistSongs = customPlaylist['list'];
    if (playlistSongs.any(
      (playlistElement) => playlistElement['ytid'] == song['ytid'],
    )) {
      return context.l10n!.songAlreadyInPlaylist;
    }
    if (indexToInsert != null) {
      final safeIndex = indexToInsert.clamp(0, playlistSongs.length);
      playlistSongs.insert(safeIndex, song);
    } else {
      playlistSongs.add(song);
    }
    if (isFromFolder) {
      unawaited(
        addOrUpdateData('user', 'playlistFolders', userPlaylistFolders.value),
      );
    } else {
      unawaited(
        addOrUpdateData('user', 'customPlaylists', userCustomPlaylists.value),
      );
    }

    return context.l10n!.songAdded;
  } else {
    logger.log('Custom playlist not found for ytid: $playlistId');
    return context.l10n!.error;
  }
}

List<Map> getUserCustomPlaylists() {
  return [
    ...userCustomPlaylists.value
        .where((p) => p['source'] == 'user-created')
        .cast<Map>(),
    for (final folder in userPlaylistFolders.value)
      ...(folder['playlists'] as List<dynamic>? ?? [])
          .where((p) => p['source'] == 'user-created')
          .cast<Map>(),
  ];
}

String addSongsInCustomPlaylist(
  BuildContext context,
  String playlistId,
  List<dynamic> songs,
) {
  final found = _findCustomPlaylist(playlistId);
  final customPlaylist = found?.playlist;
  final isFromFolder = found?.isFromFolder ?? false;

  if (customPlaylist != null) {
    final List<dynamic> playlistSongs = customPlaylist['list'];

    final newSongs = <dynamic>[];
    for (final song in songs) {
      final alreadyExists = playlistSongs.any(
        (playlistElement) => playlistElement['ytid'] == song['ytid'],
      );
      if (!alreadyExists) {
        playlistSongs.add(song);
        newSongs.add(song);
      }
    }

    if (newSongs.isNotEmpty) {
      if (isFromFolder) {
        unawaited(
          addOrUpdateData('user', 'playlistFolders', userPlaylistFolders.value),
        );
      } else {
        unawaited(
          addOrUpdateData('user', 'customPlaylists', userCustomPlaylists.value),
        );
      }
      return context.l10n!.addedSuccess;
    } else {
      return context.l10n!.songAlreadyInPlaylist;
    }
  } else {
    logger.log('Custom playlist not found for ytid: $playlistId');
    return context.l10n!.error;
  }
}

bool removeSongFromPlaylist(
  Map playlist,
  Map songToRemove, {
  int? removeOneAtIndex,
}) {
  try {
    if (playlist['list'] == null) return false;

    final playlistSongs = List<dynamic>.from(playlist['list']);
    if (removeOneAtIndex != null) {
      if (removeOneAtIndex < 0 || removeOneAtIndex >= playlistSongs.length) {
        return false;
      }
      playlistSongs.removeAt(removeOneAtIndex);
    } else {
      final initialLength = playlistSongs.length;
      playlistSongs.removeWhere((song) => song['ytid'] == songToRemove['ytid']);
      if (playlistSongs.length == initialLength) return false;
    }

    playlist['list'] = playlistSongs;

    try {
      if (playlist['source'] == 'user-created') {
        final playlistId = playlist['ytid']?.toString();
        final isInFolder =
            playlistId != null &&
            userPlaylistFolders.value.any((folder) {
              final folderPlaylists =
                  folder['playlists'] as List<dynamic>? ?? [];
              return folderPlaylists.any(
                (p) => p['ytid']?.toString() == playlistId,
              );
            });

        if (isInFolder) {
          unawaited(
            addOrUpdateData(
              'user',
              'playlistFolders',
              userPlaylistFolders.value,
            ),
          );
        } else {
          unawaited(
            addOrUpdateData(
              'user',
              'customPlaylists',
              userCustomPlaylists.value,
            ),
          );
        }
      } else {
        unawaited(addOrUpdateData('user', 'playlists', userPlaylists.value));
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error saving playlist changes',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }

    return true;
  } catch (e, stackTrace) {
    logger.log(
      'Error while removing song from playlist: ',
      error: e,
      stackTrace: stackTrace,
    );
    return false;
  }
}

void removeUserPlaylist(String playlistId) {
  final normalizedId = playlistId.trim();
  if (normalizedId.isEmpty) return;

  final updatedPlaylists = List<String>.from(userPlaylists.value)
    ..removeWhere((id) => id == normalizedId);
  userPlaylists.value = updatedPlaylists;

  final foldersChanged = _removePlaylistFromFolders(normalizedId);
  final likedChanged = _removePlaylistFromLikedPlaylists(normalizedId);
  _unpinPlaylist(normalizedId);

  unawaited(addOrUpdateData('user', 'playlists', userPlaylists.value));
  if (foldersChanged) {
    unawaited(
      addOrUpdateData('user', 'playlistFolders', userPlaylistFolders.value),
    );
  }
  if (likedChanged) {
    unawaited(addOrUpdateData('user', 'likedPlaylists', userLikedPlaylists));
  }
}

void removeUserPlaylistEntry(Map playlist) {
  final playlistId = playlist['ytid']?.toString().trim() ?? '';
  if (playlistId.isEmpty) return;

  final source = playlist['source']?.toString();
  if (PlaylistUtils.isCustomPlaylist(playlist)) {
    removeUserCustomPlaylist(playlistId);
    return;
  }

  if (source == 'user-youtube') {
    removeUserPlaylist(playlistId);
    return;
  }

  final existsInCustom = userCustomPlaylists.value.any(
    (p) => p['ytid']?.toString() == playlistId,
  );

  if (existsInCustom) {
    removeUserCustomPlaylist(playlistId);
  } else {
    removeUserPlaylist(playlistId);
  }
}

void removeUserCustomPlaylist(dynamic playlist) {
  try {
    final playlistId = (playlist is Map ? playlist['ytid'] : playlist)
        ?.toString()
        .trim();
    if (playlistId == null || playlistId.isEmpty) return;

    final updatedPlaylists = List<Map>.from(userCustomPlaylists.value)
      ..removeWhere((p) => p['ytid']?.toString() == playlistId);
    userCustomPlaylists.value = updatedPlaylists;

    final foldersChanged = _removePlaylistFromFolders(playlistId);
    final likedChanged = _removePlaylistFromLikedPlaylists(playlistId);
    _unpinPlaylist(playlistId);

    unawaited(
      addOrUpdateData('user', 'customPlaylists', userCustomPlaylists.value),
    );
    if (foldersChanged) {
      unawaited(
        addOrUpdateData('user', 'playlistFolders', userPlaylistFolders.value),
      );
    }
    if (likedChanged) {
      unawaited(addOrUpdateData('user', 'likedPlaylists', userLikedPlaylists));
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error removing custom playlist',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

bool _removePlaylistFromFolders(String playlistId) {
  var changed = false;
  final updatedFolders = List<Map>.from(userPlaylistFolders.value);

  for (final folder in updatedFolders) {
    final folderPlaylists = List<Map>.from(folder['playlists'] ?? []);
    final previousLength = folderPlaylists.length;
    folderPlaylists.removeWhere(
      (playlist) => playlist['ytid']?.toString() == playlistId,
    );

    if (folderPlaylists.length != previousLength) {
      folder['playlists'] = folderPlaylists;
      changed = true;
    }
  }

  if (changed) {
    userPlaylistFolders.value = updatedFolders;
  }

  return changed;
}

bool _removePlaylistFromLikedPlaylists(String playlistId) {
  final previousLength = userLikedPlaylists.length;
  userLikedPlaylists.removeWhere((playlist) => playlist['ytid'] == playlistId);
  return userLikedPlaylists.length != previousLength;
}

String createPlaylistFolder(String folderName, [BuildContext? context]) {
  if (folderName.trim().isEmpty) {
    return context?.l10n?.enterFolderName ?? 'Please enter a folder name';
  }

  final exists = userPlaylistFolders.value.any(
    (folder) =>
        folder['name'].toString().toLowerCase() ==
        folderName.trim().toLowerCase(),
  );

  if (exists) {
    return context?.l10n?.folderAlreadyExists ?? 'Folder already exists';
  }

  final newFolder = {
    'id': DateTime.now().millisecondsSinceEpoch.toString(),
    'name': folderName.trim(),
    'playlists': <Map>[],
    'createdAt': DateTime.now().millisecondsSinceEpoch,
  };

  userPlaylistFolders.value = [...userPlaylistFolders.value, newFolder];
  unawaited(
    addOrUpdateData('user', 'playlistFolders', userPlaylistFolders.value),
  );
  return context?.l10n?.addedSuccess ?? 'Added successfully';
}

String renamePlaylistFolder(
  String folderId,
  String newName, [
  BuildContext? context,
]) {
  if (newName.trim().isEmpty) {
    return context?.l10n?.enterFolderName ?? 'Please enter a folder name';
  }

  final updatedFolders = List<Map>.from(userPlaylistFolders.value);
  final folderIndex = updatedFolders.indexWhere((f) => f['id'] == folderId);

  if (folderIndex == -1) {
    return context?.l10n?.error ?? 'Error';
  }

  final exists = updatedFolders.any(
    (folder) =>
        folder['id'] != folderId &&
        folder['name'].toString().toLowerCase() == newName.trim().toLowerCase(),
  );

  if (exists) {
    return context?.l10n?.folderAlreadyExists ?? 'Folder already exists';
  }

  updatedFolders[folderIndex]['name'] = newName.trim();
  userPlaylistFolders.value = updatedFolders;

  unawaited(
    addOrUpdateData('user', 'playlistFolders', userPlaylistFolders.value),
  );
  return context?.l10n?.folderUpdated ?? 'Folder updated successfully';
}

String movePlaylistToFolder(
  Map playlist,
  String? folderId,
  BuildContext context,
) {
  try {
    final updatedFolders = List<Map>.from(userPlaylistFolders.value);
    final updatedCustomPlaylists = List<Map>.from(userCustomPlaylists.value);
    final updatedYoutubePlaylists = List<String>.from(userPlaylists.value);

    for (final folder in updatedFolders) {
      final folderPlaylists = List<Map>.from(
        folder['playlists'] ?? [],
      )..removeWhere((p) => p['ytid'] != null && p['ytid'] == playlist['ytid']);
      folder['playlists'] = folderPlaylists;
    }

    if (folderId != null) {
      final targetFolder = updatedFolders.firstWhere(
        (folder) => folder['id'] == folderId,
        orElse: () => {},
      );

      if (targetFolder.isNotEmpty) {
        final folderPlaylists = List<Map>.from(targetFolder['playlists'] ?? [])
          ..add(playlist);
        targetFolder['playlists'] = folderPlaylists;

        if (playlist['source'] == 'user-created') {
          updatedCustomPlaylists.removeWhere(
            (p) => p['ytid'] == playlist['ytid'],
          );
        } else if (playlist['source'] == 'user-youtube') {
          updatedYoutubePlaylists.removeWhere((p) => p == playlist['ytid']);
        }
      } else {
        logger.log(
          'Target folder with id $folderId not found for moving playlist',
        );
        return context.l10n!.error;
      }
    } else {
      if (playlist['source'] == 'user-created') {
        if (!updatedCustomPlaylists.any((p) => p['ytid'] == playlist['ytid'])) {
          updatedCustomPlaylists.add(playlist);
        }
      } else if (playlist['source'] == 'user-youtube') {
        if (!updatedYoutubePlaylists.contains(playlist['ytid'])) {
          updatedYoutubePlaylists.add(playlist['ytid']);
        }
      }
    }

    userPlaylistFolders.value = updatedFolders;
    userCustomPlaylists.value = updatedCustomPlaylists;
    userPlaylists.value = updatedYoutubePlaylists;

    unawaited(
      addOrUpdateData('user', 'playlistFolders', userPlaylistFolders.value),
    );
    unawaited(
      addOrUpdateData('user', 'customPlaylists', userCustomPlaylists.value),
    );
    unawaited(addOrUpdateData('user', 'playlists', userPlaylists.value));

    return '${context.l10n!.addedSuccess}!';
  } catch (e, stackTrace) {
    logger.log(
      'Error moving playlist to folder',
      error: e,
      stackTrace: stackTrace,
    );
    return context.l10n!.error;
  }
}

String deletePlaylistFolder(String folderId, [BuildContext? context]) {
  try {
    final updatedFolders = List<Map>.from(userPlaylistFolders.value);
    final folderToDelete = updatedFolders.firstWhere(
      (folder) => folder['id'] == folderId,
      orElse: () => {},
    );

    if (folderToDelete.isNotEmpty) {
      final folderPlaylists = List<Map>.from(folderToDelete['playlists'] ?? []);
      final updatedCustomPlaylists = List<Map>.from(userCustomPlaylists.value);
      final updatedYoutubePlaylists = List<String>.from(userPlaylists.value);

      for (final playlist in folderPlaylists) {
        if (playlist['source'] == 'user-created') {
          if (playlist['ytid'] != null &&
              !updatedCustomPlaylists.any(
                (p) => p['ytid'] == playlist['ytid'],
              )) {
            updatedCustomPlaylists.add(playlist);
          }
        } else if (playlist['source'] == 'user-youtube') {
          if (playlist['ytid'] != null &&
              !updatedYoutubePlaylists.contains(playlist['ytid'])) {
            updatedYoutubePlaylists.add(playlist['ytid']);
          }
        }
      }

      updatedFolders.removeWhere((folder) => folder['id'] == folderId);

      userPlaylistFolders.value = updatedFolders;
      userCustomPlaylists.value = updatedCustomPlaylists;
      userPlaylists.value = updatedYoutubePlaylists;

      unawaited(
        addOrUpdateData('user', 'playlistFolders', userPlaylistFolders.value),
      );
      unawaited(
        addOrUpdateData('user', 'customPlaylists', userCustomPlaylists.value),
      );
      unawaited(addOrUpdateData('user', 'playlists', userPlaylists.value));

      return context?.l10n?.folderDeleted ?? 'Folder deleted successfully';
    }
    return context?.l10n?.error ?? 'Error';
  } catch (e, stackTrace) {
    logger.log(
      'Error deleting playlist folder',
      error: e,
      stackTrace: stackTrace,
    );
    return context?.l10n?.error ?? 'Error';
  }
}

List<Map> getPlaylistsInFolder(String folderId) {
  try {
    final folder = userPlaylistFolders.value.firstWhere(
      (folder) => folder['id'] == folderId,
      orElse: () => {},
    );
    return List<Map>.from(folder['playlists'] ?? []);
  } catch (e, stackTrace) {
    logger.log(
      'Error getting playlists in folder',
      error: e,
      stackTrace: stackTrace,
    );
    return [];
  }
}

List<Map> getPlaylistsNotInFolders() {
  final playlistsInFolders = <String>{};
  for (final folder in userPlaylistFolders.value) {
    final folderPlaylists = folder['playlists'] as List<dynamic>? ?? [];
    for (final playlist in folderPlaylists) {
      if (playlist['ytid'] != null) {
        playlistsInFolders.add(playlist['ytid']);
      }
    }
  }

  return userCustomPlaylists.value
      .where((playlist) {
        final playlistId = playlist['ytid'];
        return playlistId == null || !playlistsInFolders.contains(playlistId);
      })
      .toList()
      .cast<Map>();
}

Future<List> getPlaylists({
  String? query,
  int? playlistsNum,
  bool onlyLiked = false,
  String type = 'all',
}) async {
  if (onlyLiked) {
    if (playlistsNum != null) {
      return userLikedPlaylists.take(playlistsNum).toList();
    }
    return userLikedPlaylists;
  }

  if (playlists.isEmpty || (playlistsNum == null && query == null)) {
    logger.log('No playlists available');
    return [];
  }

  if (query != null && playlistsNum == null) {
    final lowercaseQuery = query.toLowerCase();
    final filteredPlaylists = playlists.where((playlist) {
      final title = playlist['title'].toLowerCase();
      final matchesQuery = title.contains(lowercaseQuery);
      final matchesType =
          type == 'all' ||
          (type == 'album' && playlist['isAlbum'] == true) ||
          (type == 'playlist' && playlist['isAlbum'] != true);
      return matchesQuery && matchesType;
    }).toList();

    final searchTerm = type == 'album' ? '$query album' : query;

    Iterable<dynamic> searchResultsIterable = const <dynamic>[];
    try {
      searchResultsIterable = await youtubeRequest<Iterable<dynamic>>(
        operation: 'search playlists for "$searchTerm"',
        request: () => ytClient.search.searchContent(
          searchTerm,
          filter: TypeFilters.playlist,
        ),
        fallback: const <dynamic>[],
      );
    } catch (e, st) {
      logger.log(
        'Error while searching online songs:',
        error: e,
        stackTrace: st,
      );
      if (searchResultsIterable.isEmpty) {
        final proxyYt = await ProxyManager().getYoutubeExplodeClient(force: true);
        if (proxyYt != null) {
          try {
            searchResultsIterable = await youtubeRequest<Iterable<dynamic>>(
              operation: 'proxy search playlists for "$searchTerm"',
              request: () => proxyYt.search.searchContent(
                searchTerm,
                filter: TypeFilters.playlist,
              ),
              fallback: const <dynamic>[],
            );
          } catch (e2, st2) {
            logger.log('Proxy search failed:', error: e2, stackTrace: st2);
            searchResultsIterable = <dynamic>[];
          } finally {
            try {
              proxyYt.close();
            } catch (_) {}
          }
        } else {
          searchResultsIterable = <dynamic>[];
        }
      } else {
        searchResultsIterable = <dynamic>[];
      }
    }

    final existingYtIds = onlinePlaylists.value
        .map((p) => p['ytid'] as String)
        .toSet();

    final newPlaylists = searchResultsIterable
        .whereType<SearchPlaylist>()
        .map((playlist) {
          final playlistMap = {
            'ytid': playlist.id.toString(),
            'title': playlist.title,
            'source': 'youtube',
            'isAlbum': type == 'album',
            'list': [],
          };
          if (!existingYtIds.contains(playlistMap['ytid'])) {
            existingYtIds.add(playlistMap['ytid'].toString());
            return playlistMap;
          }
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
    onlinePlaylists.value = [...onlinePlaylists.value, ...newPlaylists];
    return filteredPlaylists.isNotEmpty
        ? filteredPlaylists
        : onlinePlaylists.value
              .where((p) => p['title'].toLowerCase().contains(lowercaseQuery))
              .toList();
  }

  if (playlistsNum != null && query == null) {
    final suggestedPlaylists = List<Map>.from(playlists)..shuffle();
    return suggestedPlaylists.take(playlistsNum).toList();
  }

  if (type != 'all') {
    return playlists.where((playlist) {
      return type == 'album'
          ? playlist['isAlbum'] == true
          : playlist['isAlbum'] != true;
    }).toList();
  }

  return playlists;
}

Future<List<dynamic>> getUserPlaylistsNotInFolders() async {
  final playlistsInFolders = <String>{};
  for (final folder in userPlaylistFolders.value) {
    final folderPlaylists = folder['playlists'] as List<dynamic>? ?? [];
    for (final playlist in folderPlaylists) {
      if (playlist['ytid'] != null && playlist['source'] == 'user-youtube') {
        playlistsInFolders.add(playlist['ytid']);
      }
    }
  }

  final allUserPlaylists = await getUserPlaylists();
  return allUserPlaylists.where((playlist) {
    return !playlistsInFolders.contains(playlist['ytid']);
  }).toList();
}

bool playlistExistsAnywhere(String playlistId) {
  final normalizedId = playlistId.trim();
  if (normalizedId.isEmpty) return false;

  if (userPlaylists.value.any((id) => id == normalizedId)) {
    return true;
  }

  if (userCustomPlaylists.value.any(
    (p) => p['ytid']?.toString() == normalizedId,
  )) {
    return true;
  }

  for (final folder in userPlaylistFolders.value) {
    final folderPlaylists = folder['playlists'] as List<dynamic>? ?? [];
    if (folderPlaylists.any((p) => p['ytid']?.toString() == normalizedId)) {
      return true;
    }
  }

  return false;
}

int findPlaylistIndexByYtId(String ytid) {
  for (var i = 0; i < playlists.length; i++) {
    if (playlists[i]['ytid'] == ytid) {
      return i;
    }
  }
  return -1;
}

Future<Map?> getPlaylistInfoForWidget(
  dynamic id, {
  bool isArtist = false,
}) async {
  if (id == null) return null;
  final normalizedId = id.toString().trim();
  if (normalizedId.isEmpty || normalizedId == 'null') return null;
  if (isArtist) return _fetchArtistPlaylist(normalizedId);
  if (normalizedId.startsWith('customId-')) {
    return _findCustomPlaylist(normalizedId)?.playlist;
  }

  final offlinePlaylist = _findOfflinePlaylist(normalizedId);
  if (offlinePlaylist != null) return offlinePlaylist;

  return _fetchYouTubePlaylist(normalizedId);
}

Future<Map> _fetchArtistPlaylist(String artistName) async {
  try {
    final searchResults = await youtubeRequest<List<Video>>(
      operation: 'fetch artist playlist for "$artistName"',
      request: () => ytClient.search.search(artistName),
      fallback: <Video>[],
    );
    return {
      'title': artistName,
      'list': searchResults.map((v) => returnSongLayout(0, v)).toList(),
    };
  } catch (e, stackTrace) {
    logger.log(
      'Error fetching artist songs for $artistName',
      error: e,
      stackTrace: stackTrace,
    );
    return {'title': artistName, 'list': []};
  }
}

({Map playlist, bool isFromFolder})? _findCustomPlaylist(String playlistId) {
  for (final playlist in userCustomPlaylists.value) {
    if (playlist['ytid'] == playlistId) {
      return (playlist: playlist, isFromFolder: false);
    }
  }
  for (final folder in userPlaylistFolders.value) {
    final folderPlaylists = folder['playlists'] as List<dynamic>? ?? [];
    for (final playlist in folderPlaylists) {
      if (playlist['ytid'] == playlistId) {
        return (playlist: playlist as Map, isFromFolder: true);
      }
    }
  }
  return null;
}

Map? _findOfflinePlaylist(String id) {
  return _findPlaylistById(offlinePlaylistService.offlinePlaylists.value, id);
}

Map? _findPlaylistById(Iterable<dynamic> playlists, String id) {
  for (final playlist in playlists) {
    if (playlist is Map && playlist['ytid']?.toString() == id) {
      return playlist;
    }
  }

  return null;
}

Future<Map?> _fetchYouTubePlaylist(String id) async {
  // 1. Local DB / in-memory caches (no network).
  var playlist = _findPlaylistById(playlists, id);

  // 2. User-added YouTube playlists.
  if (playlist == null) {
    final userPlaylists = await getUserPlaylists();
    playlist = _findPlaylistById(userPlaylists, id);
  }

  // 3. Previously fetched online playlists.
  playlist ??= _findPlaylistById(onlinePlaylists.value, id);

  // 4. Fetch from YouTube as a last resort.
  if (playlist == null) {
    try {
      final ytPlaylist = await youtubeRequest<Playlist?>(
        operation: 'fetch playlist info for $id',
        request: () => ytClient.playlists.get(id),
      );
      if (ytPlaylist == null) {
        return null;
      }
      playlist = {
        'ytid': ytPlaylist.id.toString(),
        'title': ytPlaylist.title,
        'image': null,
        'source': 'user-youtube',
        'list': [],
      };
      _updateOnlineCache(playlist);
    } catch (e, stackTrace) {
      logger.log(
        'Failed to fetch playlist info for id $id',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  // 5. Populate the song list if it is absent or empty.
  final list = playlist['list'];
  if (list == null || (list is List && list.isEmpty)) {
    playlist['list'] = await _loadSongsForPlaylist(playlist);
  }

  return playlist;
}

Future<List> _loadSongsForPlaylist(Map playlist) async {
  try {
    final playlistImage = playlist['isAlbum'] == true
        ? playlist['image'] as String?
        : null;
    var songs = await getSongsFromPlaylist(
      playlist['ytid'],
      playlistImage: playlistImage,
    );

    // Fallback: If playlist ID returned 0 songs, search YouTube for the album tracks
    if (songs.isEmpty && playlist['title'] != null) {
      final title = playlist['title'].toString().trim();
      if (title.isNotEmpty) {
        logger.log(
          'Playlist/Album "$title" returned 0 songs by ID (${playlist['ytid']}), running fallback search...',
        );
        songs = await searchFallbackForAlbum(
          title,
          playlistImage: playlistImage,
          excludeId: playlist['ytid']?.toString(),
        );
        if (songs.isNotEmpty) {
          final rawId = playlist['ytid']?.toString() ?? '';
          final normalizedId =
              (rawId.startsWith('OLAK5uy_') && !rawId.startsWith('VL'))
                  ? 'VL$rawId'
                  : rawId;
          unawaited(
            addOrUpdateData('cache', 'playlistSongs$normalizedId', songs),
          );
        }
      }
    }

    if (!playlists.contains(playlist)) {
      playlists.add(playlist);
    }
    return songs;
  } catch (e, stackTrace) {
    logger.log(
      'Error fetching songs for playlist ${playlist['ytid']}',
      error: e,
      stackTrace: stackTrace,
    );
    return [];
  }
}

Future<List> searchFallbackForAlbum(
  String title, {
  String? playlistImage,
  String? excludeId,
}) async {
  final cleanExcludeId = excludeId != null
      ? (excludeId.startsWith('VL') ? excludeId.substring(2) : excludeId)
      : null;

  // 1. Try finding an alternative playlist on YouTube for this album
  try {
    final searchContent = await ytClient.search
        .searchContent('$title album', filter: TypeFilters.playlist)
        .timeout(const Duration(seconds: 15));

    for (final item in searchContent.take(2)) {
      if (item is SearchPlaylist) {
        final candidateId = item.id.value;
        final cleanCandidateId = candidateId.startsWith('VL')
            ? candidateId.substring(2)
            : candidateId;
        if (cleanCandidateId != cleanExcludeId &&
            cleanCandidateId.isNotEmpty) {
          final candidateSongs = await getSongsFromPlaylist(
            candidateId,
            playlistImage: playlistImage,
          );
          if (candidateSongs.isNotEmpty) {
            logger.log(
              'Fallback playlist $candidateId succeeded with ${candidateSongs.length} songs for "$title"',
            );
            return candidateSongs;
          }
        }
      }
    }
  } catch (e) {
    logger.log('Playlist search fallback failed for "$title": $e');
  }

  // 2. Try searching YouTube for songs directly matching the album title
  try {
    final searchResults = await ytClient.search
        .search(title)
        .timeout(const Duration(seconds: 15));
    if (searchResults.isNotEmpty) {
      var idx = 0;
      final songs = searchResults
          .take(30)
          .map((video) => returnSongLayout(idx++, video, playlistImage: playlistImage))
          .toList();
      logger.log(
        'Direct search fallback succeeded with ${songs.length} songs for "$title"',
      );
      return songs;
    }
  } catch (e) {
    logger.log('Song direct search fallback failed for "$title": $e');
  }

  return [];
}

Future<List> getSongsFromPlaylist(
  dynamic playlistId, {
  String? playlistImage,
}) async {
  final rawId = playlistId.toString();
  final String normalizedId;
  if (rawId.startsWith('OLAK5uy_') && !rawId.startsWith('VL')) {
    normalizedId = 'VL$rawId';
  } else {
    normalizedId = rawId;
  }

  final cacheKey = 'playlistSongs$normalizedId';
  final cached = await getData('cache', cacheKey);
  final cachedList = (cached is List && cached.isNotEmpty) ? cached : null;

  final songList = [];
  var networkFailed = false;

  // First attempt: use the primary ytClient with normalized ID
  try {
    await for (final song in ytClient.playlists
        .getVideos(normalizedId)
        .timeout(const Duration(seconds: 10))) {
      songList.add(
        returnSongLayout(songList.length, song, playlistImage: playlistImage),
      );
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error getting playlist videos for $normalizedId (attempt 1): $e',
      error: e,
      stackTrace: stackTrace,
    );
    networkFailed = true;
  }

  // Fast return: if first attempt failed or was empty, and we have valid cached data, return it immediately!
  if ((networkFailed || songList.isEmpty) && cachedList != null) {
    logger.log('Fast return: using cached song list for $playlistId (${cachedList.length} songs)');
    return cachedList;
  }

  // Second attempt: try a fresh YoutubeExplode instance with different headers
  if (networkFailed || songList.isEmpty) {
    YoutubeExplode? freshYt;
    try {
      freshYt = YoutubeExplode();
      await for (final song in freshYt.playlists
          .getVideos(normalizedId)
          .timeout(const Duration(seconds: 8))) {
        songList.add(
          returnSongLayout(songList.length, song, playlistImage: playlistImage),
        );
      }
      if (songList.isNotEmpty) networkFailed = false;
    } catch (e2) {
      logger.log('getSongsFromPlaylist fallback instance failed: $e2');
    } finally {
      try {
        freshYt?.close();
      } catch (_) {}
    }
  }

  // Fallback attempt: if normalizedId returned nothing, try rawId without VL prefix
  if ((networkFailed || songList.isEmpty) && rawId != normalizedId) {
    try {
      await for (final song in ytClient.playlists
          .getVideos(rawId)
          .timeout(const Duration(seconds: 8))) {
        songList.add(
          returnSongLayout(songList.length, song, playlistImage: playlistImage),
        );
      }
      if (songList.isNotEmpty) networkFailed = false;
    } catch (eRaw) {
      logger.log('getSongsFromPlaylist rawId ($rawId) failed: $eRaw');
    }
  }

  // Third attempt: try proxy fallback if enabled
  if (networkFailed || songList.isEmpty) {
    final proxyYt = await ProxyManager().getYoutubeExplodeClient(force: true);
    if (proxyYt != null) {
      try {
        await for (final song in proxyYt.playlists
            .getVideos(normalizedId)
            .timeout(const Duration(seconds: 8))) {
          songList.add(
            returnSongLayout(
              songList.length,
              song,
              playlistImage: playlistImage,
            ),
          );
        }
        if (songList.isNotEmpty) networkFailed = false;
      } catch (e3) {
        logger.log('Proxy getVideos failed for $normalizedId: $e3');
      } finally {
        try {
          proxyYt.close();
        } catch (_) {}
      }
    }
  }

  if (songList.isNotEmpty) {
    // Fresh data from network — update cache
    unawaited(addOrUpdateData('cache', cacheKey, songList));
    return songList;
  }

  // All network attempts failed — fall back to cache to avoid empty screen
  if (cachedList != null) {
    logger.log('All network attempts failed for $playlistId, using cached song list');
    return cachedList;
  }

  return songList;
}


Future<void> startArtistRadio(
  BuildContext context,
  String artistName, {
  Map? seedSong,
}) async {
  final cleanArtist = artistName.trim();
  if (cleanArtist.isEmpty || cleanArtist.toLowerCase() == 'unknown') {
    showToast(context, context.l10n?.error ?? 'Error');
    return;
  }

  showToast(
    context,
    context.l10n?.startingArtistRadio ?? 'Starting artist radio...',
    duration: const Duration(seconds: 1),
  );

  try {
    final radioList = <dynamic>[];
    if (seedSong != null) {
      radioList.add(seedSong);
    }

    if (!offlineMode.value) {
      var searchResults = <Video>[];
      try {
        final results = await ytClient.search.search('$cleanArtist songs');
        searchResults = results.toList();
      } catch (e, st) {
        logger.log(
          'Error searching artist songs for radio',
          error: e,
          stackTrace: st,
        );
        if (searchResults.isEmpty) {
          final proxyYt = await ProxyManager().getYoutubeExplodeClient(force: true);
          if (proxyYt != null) {
            try {
              final results = await proxyYt.search.search('$cleanArtist songs');
              searchResults = results.toList();
            } catch (e2) {
              logger.log('Proxy search failed for artist radio: $e2');
            } finally {
              try {
                proxyYt.close();
              } catch (_) {}
            }
          }
        }
      }

      final seedYtId = seedSong?['ytid'];
      for (final video in searchResults) {
        if (video.id.toString() != seedYtId) {
          radioList.add(returnSongLayout(radioList.length, video));
        }
      }
    }

    if (radioList.isEmpty) {
      final userBox = Hive.box('user');
      final liked = List<Map>.from(userBox.get('likedSongs', defaultValue: []));
      // Key must match what common_services.dart stores: 'recentlyPlayedSongs'
      final recent = List<Map>.from(
        userBox.get('recentlyPlayedSongs', defaultValue: []),
      );
      final localMatches = [
        ...liked,
        ...recent,
      ].where((s) {
        final songArtist = s['artist']?.toString().toLowerCase() ?? '';
        return songArtist.contains(cleanArtist.toLowerCase());
      }).toList();
      radioList.addAll(localMatches);
    }

    // If still have few songs, replenish with album and related artists
    if (radioList.length < 8) {
      final excluded = radioList
          .where((s) => s is Map && s['ytid'] != null && s['ytid'].toString().isNotEmpty)
          .map((s) => s['ytid'].toString())
          .toSet();
      final more = await getInfiniteRelatedSongsFromAlbums(
        seedArtist: cleanArtist,
        seedSong: seedSong,
        limit: 12 - radioList.length,
        excludedYtIds: excluded,
      );
      radioList.addAll(more);
    }

    if (radioList.isNotEmpty) {
      final radioTitle = context.mounted
          ? '${context.l10n?.artistRadio ?? "Artist Radio"} • $cleanArtist'
          : 'Radio • $cleanArtist';
      await audioHandler.playPlaylistSong(
        playlist: {
          'title': radioTitle,
          'list': radioList,
          'isRadio': true,
          'seedArtist': cleanArtist,
          'seedSong': seedSong,
        },
        songIndex: 0,
      );
    } else {
      if (context.mounted) {
        showToast(context, context.l10n?.error ?? 'No songs found');
      }
    }
  } catch (e, st) {
    logger.log('Error starting artist radio', error: e, stackTrace: st);
    if (context.mounted) {
      showToast(context, context.l10n?.error ?? 'Error');
    }
  }
}

/// Extracts artist names from the created albums database.
List<String> getAlbumArtists() {
  final artists = <String>{};
  for (final album in albumsDB) {
    if (album is Map) {
      final title = album['title']?.toString() ?? '';
      if (title.contains(' - ')) {
        final parts = title.split(' - ');
        if (parts.length >= 2) {
          final artist = parts.sublist(1).join(' - ').trim();
          if (artist.isNotEmpty) {
            artists.add(artist);
          }
        }
      }
    }
  }
  return artists.where((a) => a.isNotEmpty && a.length > 2).toList();
}

/// Dynamically generates an indefinite list of related songs using the created albums database (albumsDB),
/// YouTube search, sample songs, and user preferences.
Future<List<Map>> getInfiniteRelatedSongsFromAlbums({
  Map? seedSong,
  Map? seedPlaylist,
  String? seedArtist,
  int limit = 10,
  Set<String>? excludedYtIds,
}) async {
  final resultSongs = <Map>[];
  final seenYtIds = <String>{...?excludedYtIds};
  if (seedSong?['ytid'] != null) seenYtIds.add(seedSong!['ytid'].toString());

  // 1. Identify seed artist / keywords
  var targetArtist = seedArtist?.trim() ?? '';
  if (targetArtist.isEmpty && seedSong != null) {
    targetArtist = seedSong['artist']?.toString().trim() ?? '';
  }
  if (targetArtist.isEmpty && seedPlaylist != null) {
    final playlistSongs = seedPlaylist['list'] as List? ?? [];
    if (playlistSongs.isNotEmpty && playlistSongs[0] is Map) {
      targetArtist = playlistSongs[0]['artist']?.toString().trim() ?? '';
    }
    if (targetArtist.isEmpty) {
      final title = seedPlaylist['title']?.toString() ?? '';
      if (title.contains(' - ')) {
        targetArtist = title.split(' - ').last.trim();
      }
    }
  }

  // 2. Search related artists from albumsDB
  final allAlbumArtists = getAlbumArtists();
  final relatedArtists = <String>[];
  if (targetArtist.isNotEmpty && targetArtist.toLowerCase() != 'unknown') {
    relatedArtists.add(targetArtist);
    for (final a in allAlbumArtists) {
      if (a.toLowerCase() != targetArtist.toLowerCase()) {
        relatedArtists.add(a);
      }
    }
  } else {
    relatedArtists.addAll(List<String>.from(allAlbumArtists)..shuffle());
  }

  // 3. Online fetch: query top songs from related album artists
  if (!offlineMode.value && relatedArtists.isNotEmpty) {
    final artistsToQuery = <String>[];
    if (targetArtist.isNotEmpty && targetArtist.toLowerCase() != 'unknown') {
      artistsToQuery.add(targetArtist);
    }
    final otherArtists = (List<String>.from(relatedArtists)
          ..removeWhere((a) => a.toLowerCase() == targetArtist.toLowerCase())
          ..shuffle())
        .take(3);
    artistsToQuery.addAll(otherArtists);

    for (final artist in artistsToQuery) {
      if (resultSongs.length >= limit) break;
      var searchSuccess = false;
      try {
        final searchResults = await ytClient.search.search('$artist songs');
        for (final video in searchResults) {
          final ytid = video.id.toString();
          if (seenYtIds.add(ytid)) {
            resultSongs.add(returnSongLayout(resultSongs.length, video));
            if (resultSongs.length >= limit) break;
          }
        }
        if (resultSongs.isNotEmpty) searchSuccess = true;
      } catch (e) {
        logger.log('Error fetching infinite album-related songs for $artist: $e');
      }

      if (!searchSuccess && resultSongs.length < limit) {
        final proxyYt = await ProxyManager().getYoutubeExplodeClient(force: true);
        if (proxyYt != null) {
          try {
            final searchResults = await proxyYt.search.search('$artist songs');
            for (final video in searchResults) {
              final ytid = video.id.toString();
              if (seenYtIds.add(ytid)) {
                resultSongs.add(returnSongLayout(resultSongs.length, video));
                if (resultSongs.length >= limit) break;
              }
            }
          } catch (pe) {
            logger.log('Proxy search failed for $artist: $pe');
          } finally {
            try {
              proxyYt.close();
            } catch (_) {}
          }
        }
      }
    }
  }

  // 4. Fallback / local pool from playlistsDB, sampleSongsDB, userLikedSongs
  if (resultSongs.length < limit) {
    final pool = <Map>[];
    for (final p in playlistsDB) {
      final pList = p['list'] as List? ?? [];
      for (final s in pList) {
        // Only include songs with a valid non-empty ytid
        if (s is Map && s['ytid'] != null && s['ytid'].toString().isNotEmpty) {
          pool.add(s);
        }
      }
    }
    // Filter sampleSongsDB for valid ytids as well
    pool.addAll(
      sampleSongsDB.where(
        (s) => s['ytid'] != null && s['ytid'].toString().isNotEmpty,
      ),
    );
    final userBox = Hive.box('user');
    final liked = List<Map>.from(userBox.get('likedSongs', defaultValue: []));
    pool.addAll(liked.where(
      (s) => s['ytid'] != null && s['ytid'].toString().isNotEmpty,
    ));

    // Prioritize songs that match targetArtist if possible
    if (targetArtist.isNotEmpty && targetArtist.toLowerCase() != 'unknown') {
      final targetLower = targetArtist.toLowerCase();
      final matchingSongs = pool
          .where((s) =>
              (s['artist']?.toString().toLowerCase() ?? '').contains(targetLower))
          .toList()
        ..shuffle();
      for (final song in matchingSongs) {
        final ytid = song['ytid']?.toString();
        if (ytid != null && ytid.isNotEmpty && seenYtIds.add(ytid)) {
          resultSongs.add(Map<String, dynamic>.from(song));
          if (resultSongs.length >= limit) break;
        }
      }
    }

    if (resultSongs.length < limit) {
      pool.shuffle();
      for (final song in pool) {
        final ytid = song['ytid']?.toString();
        if (ytid != null && ytid.isNotEmpty && seenYtIds.add(ytid)) {
          resultSongs.add(Map<String, dynamic>.from(song));
          if (resultSongs.length >= limit) break;
        }
      }
    }
  }

  return resultSongs;
}

/// Starts an endless Mix Radio based on a seed playlist, song, or artist.
Future<void> startMixRadio(
  BuildContext context, {
  Map? seedPlaylist,
  Map? seedSong,
  String? seedArtist,
  String? seedTitle,
}) async {
  showToast(
    context,
    context.l10n?.startingMixRadio ?? 'Starting Mix Radio...',
    duration: const Duration(seconds: 1),
  );

  try {
    final initialList = <dynamic>[];
    var displayTitle = seedTitle ?? '';

    if (seedSong != null) {
      initialList.add(seedSong);
      displayTitle = seedSong['title']?.toString() ?? displayTitle;
      seedArtist ??= seedSong['artist']?.toString();
    } else if (seedPlaylist != null) {
      displayTitle = seedPlaylist['title']?.toString() ?? displayTitle;
      final pList = seedPlaylist['list'] as List? ?? [];
      for (final s in pList.take(5)) {
        if (s is Map) initialList.add(s);
      }
    }

    if (displayTitle.isEmpty) {
      displayTitle = seedArtist ?? 'Mix';
    }

    // Generate indefinite related songs based on the created albums
    // Build excludedYtIds safely - filter out any null ytids to avoid
    // adding the literal string "null" to the exclusion set.
    final excludedIds = initialList
        .where((s) => s['ytid'] != null && s['ytid'].toString().isNotEmpty)
        .map((s) => s['ytid'].toString())
        .toSet();
    final moreSongs = await getInfiniteRelatedSongsFromAlbums(
      seedSong: seedSong,
      seedPlaylist: seedPlaylist,
      seedArtist: seedArtist,
      limit: 12,
      excludedYtIds: excludedIds,
    );
    initialList.addAll(moreSongs);

    if (initialList.isEmpty) {
      initialList.addAll(sampleSongsDB.take(6));
    }

    final radioTitle = context.mounted
        ? '${context.l10n?.mixRadio ?? "Mix Radio"} • $displayTitle'
        : 'Mix Radio • $displayTitle';

    await audioHandler.playPlaylistSong(
      playlist: {
        'title': radioTitle,
        'list': initialList,
        'isRadio': true,
        'seedSong': seedSong,
        'seedPlaylist': seedPlaylist,
        'seedArtist': seedArtist,
      },
      songIndex: 0,
    );
  } catch (e, st) {
    logger.log('Error starting mix radio', error: e, stackTrace: st);
    if (context.mounted) {
      showToast(context, context.l10n?.error ?? 'Error');
    }
  }
}

Future updatePlaylistList(BuildContext context, String playlistId) async {
  final index = findPlaylistIndexByYtId(playlistId);
  if (index != -1) {
    final target = playlists[index];
    final rawId = playlistId;
    final normalizedId =
        (rawId.startsWith('OLAK5uy_') && !rawId.startsWith('VL'))
            ? 'VL$rawId'
            : rawId;

    // Invalidate any stale cache for this playlist
    unawaited(deleteData('cache', 'playlistSongs$normalizedId'));
    unawaited(deleteData('cache', 'playlistSongs$rawId'));

    final songList = await _loadSongsForPlaylist(target);
    if (songList.isNotEmpty) {
      playlists[index]['list'] = songList;
      unawaited(
        addOrUpdateData('cache', 'playlistSongs$normalizedId', songList),
      );
    }
    if (context.mounted) {
      showToast(context, context.l10n!.playlistUpdated);
    }
    return playlists[index];
  }
  logger.log('Playlist with id $playlistId not found for update');
  return null;
}

Future<void> renameSongInPlaylist(
  dynamic playlistId,
  dynamic songId,
  String newTitle,
  String newArtist,
) async {
  try {
    final playlist = userCustomPlaylists.value.firstWhere(
      (p) => p['ytid'] == playlistId,
      orElse: () => <String, dynamic>{},
    );

    if (playlist.isNotEmpty && playlist['list'] != null) {
      final songIndex = (playlist['list'] as List).indexWhere(
        (song) => song['ytid'] == songId,
      );

      if (songIndex != -1) {
        final updatedSongs = List<dynamic>.from(playlist['list'] as List);
        updatedSongs[songIndex] =
            Map<String, dynamic>.from(updatedSongs[songIndex] as Map)
              ..['title'] = newTitle
              ..['artist'] = newArtist;

        final updatedPlaylist = Map<String, dynamic>.from(playlist)
          ..['list'] = updatedSongs;

        // Update the playlist in storage
        final updatedPlaylists = userCustomPlaylists.value
            .map((p) => p['ytid'] == playlistId ? updatedPlaylist : p)
            .toList();
        userCustomPlaylists.value = updatedPlaylists;

        // Save to database
        unawaited(addOrUpdateData('user', 'customPlaylists', updatedPlaylists));
      }
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error renaming song in playlist',
      error: e,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

Future<void> updatePlaylistLikeStatus(String playlistId, bool add) async {
  try {
    if (add) {
      if (!userLikedPlaylists.any(
        (playlist) => playlist['ytid'] == playlistId,
      )) {
        final playlist = playlists.firstWhere(
          (playlist) => playlist['ytid'] == playlistId,
          orElse: () => <String, dynamic>{},
        );

        if (playlist.isNotEmpty) {
          userLikedPlaylists.add(playlist);
        } else {
          final playlistInfo = await getPlaylistInfoForWidget(playlistId);
          if (playlistInfo != null) {
            userLikedPlaylists.add(playlistInfo);
          }
        }
      }
    } else {
      userLikedPlaylists.removeWhere(
        (playlist) => playlist['ytid'] == playlistId,
      );
    }

    currentLikedPlaylistsLength.value = userLikedPlaylists.length;
    unawaited(addOrUpdateData('user', 'likedPlaylists', userLikedPlaylists));
  } catch (e, stackTrace) {
    logger.log(
      'Error updating playlist like status: ',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

bool isPlaylistPinned(String playlistId) =>
    pinnedPlaylistIds.value.contains(playlistId);

bool togglePinnedPlaylist(String playlistId, BuildContext context) {
  final current = List<String>.from(pinnedPlaylistIds.value);
  if (current.contains(playlistId)) {
    current.remove(playlistId);
    pinnedPlaylistIds.value = current;
    unawaited(addOrUpdateData('user', 'pinnedPlaylistIds', current));
    return false;
  }
  if (current.length >= pinnedPlaylistsLimit) {
    return false;
  }
  current.add(playlistId);
  pinnedPlaylistIds.value = current;
  unawaited(addOrUpdateData('user', 'pinnedPlaylistIds', current));
  return true;
}

void _unpinPlaylist(String playlistId) {
  if (!pinnedPlaylistIds.value.contains(playlistId)) return;
  final updated = List<String>.from(pinnedPlaylistIds.value)
    ..remove(playlistId);
  pinnedPlaylistIds.value = updated;
  unawaited(addOrUpdateData('user', 'pinnedPlaylistIds', updated));
}

/// Updates the offline playlist metadata (title, image, source) when a custom
/// playlist is renamed or modified. This ensures the offline playlist section
/// in the library displays the updated information.
Future<void> syncOfflinePlaylistMetadata(Map updatedPlaylist) async {
  final playlistId = updatedPlaylist['ytid']?.toString();
  if (playlistId == null ||
      !offlinePlaylistService.isPlaylistDownloaded(playlistId)) {
    return;
  }

  final offlinePlaylists = List<dynamic>.from(
    offlinePlaylistService.offlinePlaylists.value,
  );
  final offlineIndex = offlinePlaylists.indexWhere(
    (p) => p['ytid']?.toString() == playlistId,
  );

  if (offlineIndex == -1) return;

  // Update the offline playlist with the new metadata
  offlinePlaylists[offlineIndex] = {
    ...offlinePlaylists[offlineIndex],
    'title': updatedPlaylist['title'],
    'image': updatedPlaylist['image'],
    'source': updatedPlaylist['source'],
  };

  // Create a new list to trigger ValueNotifier listeners
  offlinePlaylistService.offlinePlaylists.value = List<dynamic>.from(
    offlinePlaylists,
  );
  unawaited(
    addOrUpdateData('userNoBackup', 'offlinePlaylists', offlinePlaylists),
  );
}
