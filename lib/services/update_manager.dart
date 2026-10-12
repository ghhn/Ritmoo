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

import 'dart:io';

import 'package:flutter/material.dart';

const String checkUrl =
    'https://raw.githubusercontent.com/ghhn/Ritmoo/update/check.json';
const String releasesUrl =
    'https://api.github.com/repos/ghhn/Ritmoo/releases/latest';
const String downloadUrlKey = 'url';
const String downloadUrlArm64Key = 'arm64url';
const String downloadFilename = 'Ritmoo.apk';

Future<void> checkAppUpdates() async {
  // External update prompts and APK downloads are disabled for Google Play production builds.
  // Updates are handled automatically by the app store.
  return;
}

void showUpdateCheckDialog(BuildContext context) {
  // Disabled: Ritmoo updates are handled via official distribution channels (Google Play Store).
  return;
}

bool isLatestVersionHigher(String appVersion, String latestVersion) {
  return false;
}

Future<String> getCPUArchitecture() async {
  try {
    if (!Platform.isAndroid) {
      final info = await Process.run('uname', ['-m']);
      final cpu = info.stdout.toString().replaceAll('\n', '').trim();
      if (cpu.isNotEmpty) return cpu;
    }
  } catch (_) {}
  return 'aarch64';
}

Future<String> getDownloadUrl(Map<String, dynamic> map) async {
  try {
    final cpuArchitecture = await getCPUArchitecture();
    final arm64Url = map[downloadUrlArm64Key]?.toString();
    final defaultUrl = map[downloadUrlKey]?.toString();

    if (cpuArchitecture.contains('aarch64') || cpuArchitecture.contains('arm64')) {
      if (arm64Url != null && arm64Url.isNotEmpty) return arm64Url;
    }
    return defaultUrl ?? arm64Url ?? releasesUrl;
  } catch (_) {
    return releasesUrl;
  }
}

/// Announcement checks are disabled.
Future<void> fetchAnnouncementOnly() async {
  return;
}
