import 'package:flutter_test/flutter_test.dart';
import 'package:ritmoo/services/youtube_timeout.dart';

void main() {
  test('returns fallback when a YouTube request times out', () async {
    final result = await youtubeRequest<String>(
      operation: 'demo timeout',
      request: () async {
        await Future.delayed(const Duration(milliseconds: 250));
        return 'slow result';
      },
      timeout: const Duration(milliseconds: 50),
      fallback: 'fallback result',
    );

    expect(result, 'fallback result');
  });

  test('returns the result when the request completes in time', () async {
    final result = await youtubeRequest<String>(
      operation: 'demo success',
      request: () async => 'ok',
      timeout: const Duration(seconds: 1),
      fallback: 'fallback result',
    );

    expect(result, 'ok');
  });
}
