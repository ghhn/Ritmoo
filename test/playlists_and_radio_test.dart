import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ritmoo/database/albums.db.dart';
import 'package:ritmoo/database/playlists.db.dart';
import 'package:ritmoo/services/playlists_manager.dart';
import 'package:ritmoo/services/settings_manager.dart';
import 'package:ritmoo/utilities/formatter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ritmoo_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('user');
    final settingsBox = await Hive.openBox('settings');
    await settingsBox.put('offlineMode', true);
    offlineMode.value = true;
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Verify playlistsDB contains 4 to 5 songs per playlist', () {
    expect(playlistsDB.isNotEmpty, true);
    for (final playlist in playlistsDB) {
      final list = playlist['list'] as List;
      expect(list.length, inInclusiveRange(4, 5),
          reason: 'Playlist "${playlist['title']}" should have 4 or 5 songs');
      for (final song in list) {
        expect(song['ytid'], isNotNull);
        expect(song['title'], isNotNull);
        expect(song['artist'], isNotNull);
        expect(song['image'], isNotNull);
      }
    }
  });

  test('Verify getAlbumArtists extracts artists from albumsDB without album titles', () {
    final artists = getAlbumArtists();
    expect(artists.isNotEmpty, true);
    expect(artists.length, greaterThan(10));
    // Album titles like "Short N' Sweet" should not be in the artists list
    expect(artists.contains("Short N' Sweet"), false);
    expect(artists.contains("Hit Me Hard And Soft"), false);
    // Real artists should be present
    expect(artists.contains("Sabrina Carpenter"), true);
    expect(artists.contains("Billie Eilish"), true);
  });

  test('Verify getInfiniteRelatedSongsFromAlbums provides fallback songs when offline', () async {
    final seedSong = playlistsDB.first['list'][0] as Map;
    final related = await getInfiniteRelatedSongsFromAlbums(
      seedSong: seedSong,
      limit: 5,
    );
    expect(related.isNotEmpty, true);
    expect(related.length, lessThanOrEqualTo(5));
  });

  test('Verify getInfiniteRelatedSongsFromAlbums respects excludedYtIds', () async {
    final seedSong = playlistsDB.first['list'][0] as Map;
    final firstBatch = await getInfiniteRelatedSongsFromAlbums(
      seedSong: seedSong,
      limit: 3,
    );
    final excluded = firstBatch.map((s) => s['ytid'].toString()).toSet();
    final secondBatch = await getInfiniteRelatedSongsFromAlbums(
      seedSong: seedSong,
      limit: 3,
      excludedYtIds: excluded,
    );
    for (final song in secondBatch) {
      expect(excluded.contains(song['ytid'].toString()), false,
          reason: 'Second batch should not contain songs from excluded set');
    }
  });

  test('Verify returnSongLayout extracts artist from author when title lacks dash', () {
    final video = Video(
      VideoId('abcdefghijk'),
      'Espresso',
      'Sabrina Carpenter - Topic',
      ChannelId('UC1234567890123456789012'),
      DateTime.now(),
      'now',
      DateTime.now(),
      'description',
      const Duration(minutes: 3),
      ThumbnailSet('abcdefghijk'),
      [],
      Engagement(0, 0, 0),
      false,
    );

    final result = returnSongLayout(0, video);
    expect(result['title'], 'Espresso');
    expect(result['artist'], 'Sabrina Carpenter');
  });

  test('Verify returnSongLayout splits title when dash is present', () {
    final video = Video(
      VideoId('abcdefghijk'),
      'Arctic Monkeys - 505',
      'ArcticMonkeysVEVO',
      ChannelId('UC1234567890123456789012'),
      DateTime.now(),
      'now',
      DateTime.now(),
      'description',
      const Duration(minutes: 3),
      ThumbnailSet('abcdefghijk'),
      [],
      Engagement(0, 0, 0),
      false,
    );

    final result = returnSongLayout(0, video);
    expect(result['title'], '505');
    expect(result['artist'], 'Arctic Monkeys');
  });
}
