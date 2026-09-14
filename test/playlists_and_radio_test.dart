import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ritmoo/database/playlists.db.dart';
import 'package:ritmoo/database/albums.db.dart';
import 'package:ritmoo/services/playlists_manager.dart';
import 'package:ritmoo/services/settings_manager.dart';

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

  test('Verify getAlbumArtists extracts artists from albumsDB', () {
    final artists = getAlbumArtists();
    expect(artists.isNotEmpty, true);
    expect(artists.length, greaterThan(10));
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
}
