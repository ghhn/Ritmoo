import 'package:collection/collection.dart';
import 'package:html/parser.dart' as parser;

import '../../../youtube_explode_dart.dart';
import '../../extensions/helpers_extension.dart';
import '../../retry.dart';
import '../models/initial_data.dart';
import '../models/youtube_page.dart';
import '../youtube_http_client.dart';

class PlaylistPage extends YoutubePage<_InitialData> {
  final String playlistId;
  final String? _visitorData;

  late final List<_Video> videos = initialData.playlistVideos;
  late final String? title = initialData.title;
  late final String? description = initialData.description;
  late final String? author = initialData.author;
  late final int? viewCount = initialData.viewCount;
  late final int? videoCount = initialData.videoCount;

  PlaylistPage.id(this.playlistId, _InitialData initialData,
      [this._visitorData])
      : super.fromInitialData(initialData);

  PlaylistPage.parse(String raw, this.playlistId)
      : _visitorData = null,
        super(parser.parse(raw), (root) => _InitialData(root));

  Future<PlaylistPage?> nextPage(YoutubeHttpClient httpClient) async {
    final token = initialData.continuationToken;
    if (token == null || token.isEmpty) return null;

    final data = await httpClient.sendContinuation('browse', token, headers: {
      'x-youtube-client-name': '1',
      'x-goog-visitor-id': _visitorData ?? '',
    });

    final newInitialData = _InitialData(data);
    // Guard against infinite loops with a stuck token.
    if (newInitialData.continuationToken == token) return null;

    return PlaylistPage.id(playlistId, newInitialData, _visitorData);
  }

  static Future<PlaylistPage> get(YoutubeHttpClient httpClient, String id) {
    final url = 'https://www.youtube.com/playlist?list=$id&hl=en&persist_hl=1';
    return retry(httpClient, () async {
      final raw = await httpClient.getString(url);
      final page = PlaylistPage.parse(raw, id);
      if (page.initialData.exists && page.videos.isNotEmpty) return page;

      // Fallback: fetch via the browse API. Needed for Mixes and YT Music playlists
      // whose initial HTML page doesn't embed the video list.
      try {
        final rawBrowseId = page.initialData.browseId ?? id;
        final candidates = <String>{
          rawBrowseId,
          if (rawBrowseId.startsWith('VL')) rawBrowseId.substring(2),
          if (!rawBrowseId.startsWith('VL')) 'VL$rawBrowseId',
        };
        for (final bId in candidates) {
          try {
            final data = await httpClient.sendPost('browse', {
              'browseId': bId,
            }, headers: {
              'x-youtube-client-name': '1',
              'x-goog-visitor-id': page.initialData.visitorData ?? '',
            });
            final browsePage = PlaylistPage.id(
                id, _InitialData(data), page.initialData.visitorData);
            if (browsePage.videos.isNotEmpty) return browsePage;
          } catch (_) {
            // Browse candidate failed — try next.
          }
        }
      } catch (_) {
        // Browse failed — fall through and return what we have.
      }
      return page;
    });
  }
}

class _InitialData extends InitialData {
  _InitialData(super.root);

  String? get visitorData => root.getJson<String>(
      'responseContext/webResponseContextExtensionData/ytConfigData/visitorData');

  String? get browseId {
    final params =
        root.getJson<List<dynamic>>('responseContext/serviceTrackingParams');
    final gfeedback = params
        ?.firstWhereOrNull((e) => e['service'] == 'GFEEDBACK') as JsonMap?;
    final paramList = gfeedback?.getJson<List<dynamic>>('params');
    return (paramList?.firstWhereOrNull((e) => e['key'] == 'browse_id')
        as JsonMap?)?['value'] as String?;
  }

  bool get exists =>
      root.getJson<String>('alerts/0/alertRenderer/type') != 'ERROR';

  late final String? title =
      root.getJson<String>('metadata/playlistMetadataRenderer/title') ??
      root.getJson<String>(
          'header/musicDetailHeaderRenderer/title/runs/0/text');

  late final String? description =
      root.getJson<String>('metadata/playlistMetadataRenderer/description') ??
      root.getJson<String>(
          'header/musicDetailHeaderRenderer/description/runs/0/text');

  late final String? author = (root
          .getJson<List<dynamic>>('sidebar/playlistSidebarRenderer/items')
          ?.elementAtSafe(1) as JsonMap?)
      ?.getJson<List<dynamic>>(
        'playlistSidebarSecondaryInfoRenderer/videoOwner/videoOwnerRenderer/title/runs',
      )
      ?.cast<Map<dynamic, dynamic>>()
      .parseRuns() ??
      root.getJson<String>(
          'header/musicDetailHeaderRenderer/subtitle/runs/0/text');

  late final int? viewCount = ((root
              .getJson<List<dynamic>>('sidebar/playlistSidebarRenderer/items')
              ?.firstOrNull as JsonMap?)
          ?.getJson<List<dynamic>>('playlistSidebarPrimaryInfoRenderer/stats')
          ?.elementAtSafe(1) as JsonMap?)
      ?.getJson<String>('simpleText')
      .parseInt();

  late final int? videoCount = () {
    final stats = (root
                .getJson<List<dynamic>>('sidebar/playlistSidebarRenderer/items')
                ?.firstWhereOrNull(
                    (e) => e['playlistSidebarPrimaryInfoRenderer'] != null)
            as JsonMap?)
        ?.getJson<List<dynamic>>('playlistSidebarPrimaryInfoRenderer/stats');
    if (stats == null) return null;

    for (final stat in stats.cast<JsonMap>()) {
      final text = stat.getJson<String>('runs/0/text');
      final suffix = stat.getJson<String>('runs/1/text');
      if (text != null && suffix != null && suffix.contains('video')) {
        return text.parseInt();
      }
    }
    // Fallback: use the first stat if none was labelled "video".
    final first = stats.firstOrNull;
    return first is Map
        ? (first as JsonMap).getJson<String>('runs/0/text').parseInt()
        : null;
  }();

  String? get continuationToken {
    final items = _videoItems;
    if (items == null) return null;

    final endpoint = items
        .firstWhereOrNull((e) => e['continuationItemRenderer'] != null)
        ?.getJson<JsonMap>('continuationItemRenderer/continuationEndpoint');
    if (endpoint == null) return null;

    // Direct token.
    final token = endpoint.getJson<String>('continuationCommand/token');
    if (token != null) return token;

    // Some responses nest the token inside a commandExecutorCommand.
    return endpoint
        .getJson<List<dynamic>>('commandExecutorCommand/commands')
        ?.cast<JsonMap>()
        .map((c) => c.getJson<String>('continuationCommand/token'))
        .nonNulls
        .firstOrNull;
  }

  /// The flat list of items (videos + continuation marker) for the current page.
  /// Handles continuation responses, two-column, single-column, and YT Music album structures.
  List<JsonMap>? get _videoItems {
    // Continuation responses arrive under onResponseReceivedActions/Commands.
    final actions = root.getJson<List<dynamic>>('onResponseReceivedActions') ??
        root.getJson<List<dynamic>>('onResponseReceivedCommands');
    if (actions != null) {
      for (final action in actions.cast<JsonMap>()) {
        final items = action.getJson<List<dynamic>>(
                'appendContinuationItemsAction/continuationItems') ??
            action.getJson<List<dynamic>>(
                'reloadContinuationItemsCommand/continuationItems');
        if (items != null) return items.cast<JsonMap>();
      }
    }

    // Direct musicPlaylistShelfRenderer or musicShelfRenderer under contents
    final directPlaylistShelf = root.getJson<List<dynamic>>('contents/musicPlaylistShelfRenderer/contents') ??
        root.getJson<List<dynamic>>('contents/musicShelfRenderer/contents') ??
        root.getJson<List<dynamic>>('contents/playlistVideoListRenderer/contents');
    if (directPlaylistShelf != null) return directPlaylistShelf.cast<JsonMap>();

    // secondaryContents (commonly used in two-column YouTube Music album layout)
    final secondarySections = root.getJson<List<dynamic>>(
        'contents/twoColumnBrowseResultsRenderer/secondaryContents/sectionListRenderer/contents');
    if (secondarySections != null) {
      for (final section in secondarySections.cast<JsonMap>()) {
        final contents = section.getJson<List<dynamic>>('musicPlaylistShelfRenderer/contents') ??
            section.getJson<List<dynamic>>('musicShelfRenderer/contents') ??
            section.getJson<List<dynamic>>('playlistVideoListRenderer/contents');
        if (contents != null) return contents.cast<JsonMap>();

        final itemContents = section.getJson<List<dynamic>>('itemSectionRenderer/contents');
        if (itemContents != null) {
          for (final item in itemContents.cast<JsonMap>()) {
            final subContents = item.getJson<List<dynamic>>('musicPlaylistShelfRenderer/contents') ??
                item.getJson<List<dynamic>>('musicShelfRenderer/contents') ??
                item.getJson<List<dynamic>>('playlistVideoListRenderer/contents');
            if (subContents != null) return subContents.cast<JsonMap>();
          }
        }
      }
    }

    // Initial page: tabs → sectionList → itemSection → playlistVideoListRenderer/musicPlaylistShelfRenderer.
    final tabs = root.getJson<List<dynamic>>('contents/twoColumnBrowseResultsRenderer/tabs') ??
        root.getJson<List<dynamic>>('contents/singleColumnBrowseResultsRenderer/tabs');
    if (tabs != null) {
      for (final tab in tabs.cast<JsonMap>()) {
        // Direct shelf under tabRenderer
        final directTabShelf = tab.getJson<List<dynamic>>(
                'tabRenderer/content/musicPlaylistShelfRenderer/contents') ??
            tab.getJson<List<dynamic>>(
                'tabRenderer/content/musicShelfRenderer/contents') ??
            tab.getJson<List<dynamic>>(
                'tabRenderer/content/playlistVideoListRenderer/contents');
        if (directTabShelf != null) return directTabShelf.cast<JsonMap>();

        final sections = tab.getJson<List<dynamic>>(
            'tabRenderer/content/sectionListRenderer/contents');
        if (sections == null) continue;

        for (final section in sections.cast<JsonMap>()) {
          final directContents =
              section.getJson<List<dynamic>>('musicPlaylistShelfRenderer/contents') ??
              section.getJson<List<dynamic>>('playlistVideoListRenderer/contents') ??
              section.getJson<List<dynamic>>('musicShelfRenderer/contents');
          if (directContents != null) return directContents.cast<JsonMap>();

          final itemContents =
              section.getJson<List<dynamic>>('itemSectionRenderer/contents');
          if (itemContents == null) continue;

          for (final item in itemContents.cast<JsonMap>()) {
            final contents =
                item.getJson<List<dynamic>>('musicPlaylistShelfRenderer/contents') ??
                item.getJson<List<dynamic>>('playlistVideoListRenderer/contents') ??
                item.getJson<List<dynamic>>('musicShelfRenderer/contents');
            if (contents != null) return contents.cast<JsonMap>();
          }
        }
      }
    }

    // Direct sectionListRenderer (fallback for browse API responses)
    final directSections = root.getJson<List<dynamic>>('contents/sectionListRenderer/contents');
    if (directSections != null) {
      for (final section in directSections.cast<JsonMap>()) {
        final directContents = section.getJson<List<dynamic>>('musicPlaylistShelfRenderer/contents') ??
            section.getJson<List<dynamic>>('playlistVideoListRenderer/contents') ??
            section.getJson<List<dynamic>>('musicShelfRenderer/contents');
        if (directContents != null) return directContents.cast<JsonMap>();

        final itemContents = section.getJson<List<dynamic>>('itemSectionRenderer/contents');
        if (itemContents != null) {
          for (final item in itemContents.cast<JsonMap>()) {
            final contents =
                item.getJson<List<dynamic>>('musicPlaylistShelfRenderer/contents') ??
                item.getJson<List<dynamic>>('playlistVideoListRenderer/contents') ??
                item.getJson<List<dynamic>>('musicShelfRenderer/contents');
            if (contents != null) return contents.cast<JsonMap>();
          }
        }
      }
    }

    return null;
  }

  List<_Video> get playlistVideos {
    final items = _videoItems;
    if (items == null) return const [];

    return items
        .map((item) =>
            item['playlistVideoRenderer'] as JsonMap? ??
            item['richItemRenderer']?['content']?['playlistVideoRenderer']
                as JsonMap? ??
            item['musicResponsiveListItemRenderer'] as JsonMap? ??
            item)
        .nonNulls
        .map(_Video.new)
        .where((v) => v.id.isNotEmpty)
        .toList();
  }
}

class _Video {
  final JsonMap root;
  _Video(this.root);

  String get id {
    final direct = root.getJson<String>('videoId') ??
        root.getJson<String>('playlistItemData/videoId') ??
        root.getJson<String>('navigationEndpoint/watchEndpoint/videoId') ??
        root.getJson<String>('onTap/watchEndpoint/videoId') ??
        root.getJson<String>('doubleTapCommand/watchEndpoint/videoId') ??
        root.getJson<String>(
            'overlay/musicItemThumbnailOverlayRenderer/content/musicPlayButtonRenderer/playNavigationEndpoint/watchEndpoint/videoId') ??
        root.getJson<String>(
            'thumbnailOverlay/musicItemThumbnailOverlayRenderer/content/musicPlayButtonRenderer/playNavigationEndpoint/watchEndpoint/videoId');
    if (direct != null && direct.isNotEmpty) return direct;

    // Try flex columns (musicResponsiveListItemRenderer)
    final flexCols = root.getJson<List<dynamic>>('flexColumns');
    if (flexCols != null) {
      for (final col in flexCols) {
        if (col is Map) {
          final runs = (col as JsonMap).getJson<List<dynamic>>(
              'musicResponsiveListItemFlexColumnRenderer/text/runs');
          if (runs != null) {
            for (final run in runs) {
              if (run is Map) {
                final vid = (run as JsonMap).getJson<String>(
                    'navigationEndpoint/watchEndpoint/videoId');
                if (vid != null && vid.isNotEmpty) return vid;
              }
            }
          }
        }
      }
    }

    // Try menu items
    final menuItems = root.getJson<List<dynamic>>('menu/menuRenderer/items');
    if (menuItems != null) {
      for (final item in menuItems) {
        if (item is Map) {
          final vid = (item as JsonMap).getJson<String>(
              'menuNavigationItemRenderer/navigationEndpoint/watchEndpoint/videoId');
          if (vid != null && vid.isNotEmpty) return vid;
        }
      }
    }

    return '';
  }

  String get author {
    final standardAuthor = root
            .getJson<List<dynamic>>('ownerText/runs')
            ?.cast<Map<dynamic, dynamic>>()
            .parseRuns() ??
        root
            .getJson<List<dynamic>>('shortBylineText/runs')
            ?.cast<Map<dynamic, dynamic>>()
            .parseRuns() ??
        root
            .getJson<List<dynamic>>('longBylineText/runs')
            ?.cast<Map<dynamic, dynamic>>()
            .parseRuns() ??
        root
            .getJson<List<dynamic>>('bylineText/runs')
            ?.cast<Map<dynamic, dynamic>>()
            .parseRuns();
    if (standardAuthor != null && standardAuthor.isNotEmpty) {
      return standardAuthor;
    }

    // Fallback: musicResponsiveListItemRenderer flexColumns[1]
    final flexCols = root.getJson<List<dynamic>>('flexColumns');
    if (flexCols != null && flexCols.length > 1) {
      final secondCol = flexCols[1] as JsonMap?;
      final runs = secondCol?.getJson<List<dynamic>>(
          'musicResponsiveListItemFlexColumnRenderer/text/runs');
      if (runs != null) {
        final parsed = runs.cast<Map<dynamic, dynamic>>().parseRuns();
        if (parsed.isNotEmpty) return parsed;
      }
    }

    return '';
  }

  String get channelId {
    final standard = root.getJson<String>(
            'ownerText/runs/0/navigationEndpoint/browseEndpoint/browseId') ??
        root.getJson<String>(
            'shortBylineText/runs/0/navigationEndpoint/browseEndpoint/browseId') ??
        root.getJson<String>(
            'longBylineText/runs/0/navigationEndpoint/browseEndpoint/browseId') ??
        root.getJson<String>(
            'bylineText/runs/0/navigationEndpoint/browseEndpoint/browseId') ??
        root.getJson<String>(
            'shortBylineText/runs/0/navigationEndpoint/showDialogCommand/panelLoadingStrategy/inlineContent/dialogViewModel/customContent/listViewModel/listItems/0/listItemViewModel/rendererContext/commandContext/onTap/innertubeCommand/browseEndpoint/browseId');
    if (standard != null && standard.isNotEmpty) return standard;

    final flexCols = root.getJson<List<dynamic>>('flexColumns');
    if (flexCols != null && flexCols.length > 1) {
      final secondCol = flexCols[1] as JsonMap?;
      final runs = secondCol?.getJson<List<dynamic>>(
          'musicResponsiveListItemFlexColumnRenderer/text/runs');
      if (runs != null && runs.isNotEmpty) {
        final bId = (runs.first as JsonMap?)?.getJson<String>(
            'navigationEndpoint/browseEndpoint/browseId');
        if (bId != null && bId.isNotEmpty) return bId;
      }
    }
    return '';
  }

  String get title {
    final runsTitle = root
        .getJson<List<dynamic>>('title/runs')
        ?.cast<Map<dynamic, dynamic>>()
        .parseRuns();
    if (runsTitle != null && runsTitle.isNotEmpty) return runsTitle;

    final simpleTitle = root.getJson<String>('title/simpleText');
    if (simpleTitle != null && simpleTitle.isNotEmpty) return simpleTitle;

    // Fallback: musicResponsiveListItemRenderer flexColumns[0]
    final flexCols = root.getJson<List<dynamic>>('flexColumns');
    if (flexCols != null && flexCols.isNotEmpty) {
      final firstCol = flexCols.first as JsonMap?;
      final runs = firstCol?.getJson<List<dynamic>>(
          'musicResponsiveListItemFlexColumnRenderer/text/runs');
      if (runs != null) {
        final parsed = runs.cast<Map<dynamic, dynamic>>().parseRuns();
        if (parsed.isNotEmpty) return parsed;
      }
    }

    return '';
  }

  String get description =>
      root
          .getJson<List<dynamic>>('descriptionSnippet')
          ?.cast<Map<dynamic, dynamic>>()
          .parseRuns() ??
      '';

  Duration? get duration {
    final simple = root.getJson<String>('lengthText/simpleText')?.toDuration();
    if (simple != null) return simple;

    final secStr = root.getJson<String>('lengthSeconds');
    if (secStr != null) {
      final sec = int.tryParse(secStr);
      if (sec != null) return Duration(seconds: sec);
    }

    // Fallback: musicResponsiveListItemRenderer fixedColumns
    final fixedCols = root.getJson<List<dynamic>>('fixedColumns');
    if (fixedCols != null && fixedCols.isNotEmpty) {
      final firstFixed = fixedCols.first as JsonMap?;
      final fixedText = firstFixed?.getJson<String>(
              'musicResponsiveListItemFixedColumnRenderer/text/simpleText') ??
          firstFixed
              ?.getJson<List<dynamic>>(
                  'musicResponsiveListItemFixedColumnRenderer/text/runs')
              ?.cast<Map<dynamic, dynamic>>()
              .parseRuns();
      if (fixedText != null && fixedText.isNotEmpty) {
        return fixedText.toDuration();
      }
    }

    return null;
  }

  int get viewCount =>
      root.getJson<String>('viewCountText/simpleText').parseInt() ??
      _videoInfo?.split('•').elementAtSafe(0)?.stripNonDigits().parseInt() ??
      0;

  String? get uploadDateRaw => _videoInfo?.split('•').elementAtSafe(1);

  String? get _videoInfo => root
      .getJson<List<dynamic>>('videoInfo/runs')
      ?.cast<Map<dynamic, dynamic>>()
      .parseRuns();
}
