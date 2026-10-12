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

import 'package:flutter/material.dart';
import 'package:ritmoo/extensions/l10n.dart';
import 'package:ritmoo/services/playlist_download_service.dart';
import 'package:ritmoo/utilities/flutter_toast.dart';
import 'package:ritmoo/widgets/confirmation_dialog.dart';

void showRemoveOfflinePlaylistDialog(BuildContext context, String playlistId) {
  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return ConfirmationDialog(
        confirmationMessage: context.l10n!.removeOfflinePlaylistConfirm,
        submitMessage: context.l10n!.remove,
        isDangerous: true,
        onCancel: () => Navigator.pop(context),
        onSubmit: () {
          offlinePlaylistService.removeOfflinePlaylist(playlistId);
          Navigator.pop(context);
          showToast(context, context.l10n!.playlistRemovedFromOffline);
        },
      );
    },
  );
}
