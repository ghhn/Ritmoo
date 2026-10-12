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
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Direct network manager for YouTube requests.
/// Proxy scraping has been disabled to eliminate network latency,
/// timeouts, and playback blocking.
class ProxyManager {
  factory ProxyManager() => _instance;
  ProxyManager._internal() {
    _defaultYt = YoutubeExplode();
  }

  static final ProxyManager _instance = ProxyManager._internal();

  late final YoutubeExplode _defaultYt;

  /// Returns the default direct YouTube client.
  YoutubeExplode getClientSync() => _defaultYt;

  /// Unused proxy client getter kept for API backwards-compatibility.
  Future<YoutubeExplode?> getYoutubeExplodeClient({
    int timeoutSeconds = 5,
    bool force = false,
  }) async {
    return null;
  }

  /// Song manifest fetcher - handled directly by common_services.
  Future<StreamManifest?> getSongManifest(
    String songId, {
    bool forceProxy = false,
  }) async {
    return null;
  }

  /// Performs a direct HTTP GET request with a clean timeout.
  Future<http.Response> getProxiedResponse(
    Uri uri, {
    Map<String, String>? headers,
    int timeoutSeconds = 10,
  }) async {
    try {
      return await http
          .get(uri, headers: headers)
          .timeout(
            Duration(seconds: timeoutSeconds),
            onTimeout: () => http.Response('Timeout', 408),
          );
    } catch (_) {
      return http.Response('Error', 500);
    }
  }

  void closeAll() {
    try {
      _defaultYt.close();
    } catch (_) {}
  }
}

final ytClient = ProxyManager().getClientSync();