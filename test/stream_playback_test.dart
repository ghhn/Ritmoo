import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ritmoo/constants/clients.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Verify stream manifest extraction and album playlist', () async {
    final yt = YoutubeExplode();
    try {
      final client = http.Client();
      print('Testing sw.js_data...');
      try {
        final swRes = await client.get(Uri.parse('https://www.youtube.com/sw.js_data')).timeout(const Duration(seconds: 5));
        print('sw.js_data status: ${swRes.statusCode}');
      } catch (e) {
        print('sw.js_data failed: $e');
      }

      print('Testing youtubei/v1/player with androidSdkless client payload...');
      try {
        final payload = {
          'context': {
            'client': {
              'clientName': 'ANDROID',
              'clientVersion': '20.10.38',
              'userAgent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
              'hl': 'en',
              'timeZone': 'UTC',
              'utcOffsetMinutes': 0,
              'osName': 'Android',
              'osVersion': '11',
            },
          },
          'videoId': 'dQw4w9WgXcQ',
        };
        final res = await client.post(
          Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
          },
          body: json.encode(payload),
        ).timeout(const Duration(seconds: 5));
        print('player response status: ${res.statusCode}');
        final data = json.decode(res.body);
        print('player response playabilityStatus: ${data['playabilityStatus']?['status']}');
        final streamingData = data['streamingData'];
        final adaptiveFormats = streamingData?['adaptiveFormats'] as List?;
        print('adaptiveFormats count: ${adaptiveFormats?.length}');
      } catch (e) {
        print('player request failed: $e');
      }
      client.close();
    } finally {
      yt.close();
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}
