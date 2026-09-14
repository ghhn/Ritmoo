import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Verify stream manifest extraction and album playlist', () async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streams.getManifest(
        'dQw4w9WgXcQ',
        ytClients: [YoutubeApiClient.androidSdkless, YoutubeApiClient.ios],
      );
      final audioStreams = manifest.audioOnly;
      
      print('Extracted audio streams count: ' + audioStreams.length.toString());
      expect(audioStreams.isNotEmpty, true);

      final song = audioStreams.withHighestBitrate();
      print('Highest bitrate audio URL obtained: ' + (song.url.toString().isNotEmpty).toString());
      expect(song.url.toString().isNotEmpty, true);
    } finally {
      yt.close();
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}
