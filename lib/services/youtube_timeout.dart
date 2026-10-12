import 'dart:async';

import 'package:ritmoo/main.dart' show logger;

/// Runs a YouTube API request with a hard timeout and graceful fallback.
/// This keeps slow or blocked network calls from hanging the player UI.
Future<T> youtubeRequest<T>({
  required String operation,
  required Future<T> Function() request,
  Duration timeout = const Duration(seconds: 12),
  T? fallback,
}) async {
  try {
    return await request().timeout(timeout, onTimeout: () async {
      if (fallback != null) {
        logger.log(
          'YouTube request timed out during $operation, using fallback value.',
        );
        return fallback;
      }

      throw TimeoutException(
        'Request timed out for $operation',
        timeout,
      );
    });
  } on TimeoutException catch (e, stackTrace) {
    logger.log(
      'YouTube request timed out during $operation',
      error: e,
      stackTrace: stackTrace,
    );

    if (fallback != null) {
      return fallback;
    }

    rethrow;
  } catch (e, stackTrace) {
    logger.log(
      'YouTube request failed during $operation',
      error: e,
      stackTrace: stackTrace,
    );

    if (fallback != null) {
      return fallback;
    }

    rethrow;
  }
}
