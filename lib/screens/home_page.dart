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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ritmoo/constants/app_constants.dart';
import 'package:ritmoo/extensions/l10n.dart';
import 'package:ritmoo/main.dart';
import 'package:ritmoo/services/common_services.dart';
import 'package:ritmoo/services/playlists_manager.dart';
import 'package:ritmoo/services/settings_manager.dart';
import 'package:ritmoo/utilities/app_utils.dart';
import 'package:ritmoo/utilities/async_loader.dart';
import 'package:ritmoo/widgets/announcement_box.dart';
import 'package:ritmoo/widgets/playlist_cube.dart';
import 'package:ritmoo/widgets/section_header.dart';
import 'package:ritmoo/widgets/song_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final playlistHeight = MediaQuery.sizeOf(context).height * 0.25 / 1.1;
    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/logo_r.png',
          height: 38,
          fit: BoxFit.contain,
        ),
      ),
      body: SingleChildScrollView(
        padding: commonSingleChildScrollViewPadding,
        child: Column(
          children: [
            ValueListenableBuilder<String?>(
              valueListenable: announcementURL,
              builder: (_, _url, __) {
                if (_url == null) return const SizedBox.shrink();
                final isSponsorshipAnnouncement = isSponsorshipAnnouncementUrl(
                  _url,
                );
                final _message = isSponsorshipAnnouncement
                    ? context.l10n!.sponsorProject
                    : context.l10n!.newAnnouncement;
                final _icon = isSponsorshipAnnouncement
                    ? FluentIcons.heart_24_filled
                    : FluentIcons.megaphone_24_filled;

                return AnnouncementBox(
                  message: _message,
                  url: _url,
                  icon: _icon,
                  onDismiss: () async {
                    announcementURL.value = null;
                  },
                );
              },
            ),
            _buildSuggestedPlaylists(playlistHeight),
            _buildSuggestedPlaylists(playlistHeight, showOnlyLiked: true),
            _buildSampleSongsSection(),
            _buildMostPlayedSection(),
            _buildRecommendedSongsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedPlaylists(
    double playlistHeight, {
    bool showOnlyLiked = false,
  }) {
    final sectionTitle = showOnlyLiked
        ? context.l10n!.backToFavorites
        : context.l10n!.suggestedPlaylists;
    return AsyncLoader<List<dynamic>>(
      future: getPlaylists(
        playlistsNum: recommendedCubesNumber,
        onlyLiked: showOnlyLiked,
      ),

      builder: (context, playlists) {
        if (playlists.isEmpty) {
          return const SizedBox.shrink();
        }
        final itemsNumber = playlists.length.clamp(0, recommendedCubesNumber);
        final isLargeScreen = MediaQuery.of(context).size.width > 480;

        return Column(
          children: [
            SectionHeader(
              title: sectionTitle,
              icon: showOnlyLiked
                  ? FluentIcons.heart_24_filled
                  : FluentIcons.list_24_filled,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: playlistHeight),
              child: isLargeScreen
                  ? _buildHorizontalList(playlists, itemsNumber, playlistHeight)
                  : _buildCarouselView(playlists, itemsNumber, playlistHeight),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSampleSongsSection() {
    final sampleSongs = getSampleSongs(limit: 6);
    if (sampleSongs.isEmpty) return const SizedBox.shrink();

    final sectionTitle = context.l10n!.sampleSongs;
    final samplePlaylist = {'title': sectionTitle, 'list': sampleSongs};

    return Column(
      children: [
        SectionHeader(
          title: sectionTitle,
          icon: FluentIcons.music_note_2_24_filled,
          actionButton: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.l10n?.startMixRadio ?? 'Start Mix Radio',
                onPressed: () => startMixRadio(
                  context,
                  seedPlaylist: samplePlaylist,
                ),
                icon: Icon(
                  FluentIcons.radio_button_24_filled,
                  color: Theme.of(context).colorScheme.primary,
                  size: 26,
                ),
              ),
              IconButton(
                onPressed: () async {
                  await audioHandler.playPlaylistSong(
                    playlist: samplePlaylist,
                    songIndex: 0,
                  );
                },
                icon: Icon(
                  FluentIcons.play_circle_24_filled,
                  color: Theme.of(context).colorScheme.primary,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: sampleSongs.length,
          padding: commonListViewBottomPadding,
          itemBuilder: (context, index) {
            final borderRadius = getItemBorderRadius(
              index,
              sampleSongs.length,
            );
            return RepaintBoundary(
              key: listItemKey('home_sample', index, sampleSongs[index]),
              child: SongBar(
                sampleSongs[index],
                true,
                borderRadius: borderRadius,
                showMusicDuration: true,
                onPlay: () async {
                  await audioHandler.playPlaylistSong(
                    playlist: samplePlaylist,
                    songIndex: index,
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHorizontalList(
    List<dynamic> playlists,
    int itemCount,
    double height,
  ) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GestureDetector(
            onTap: () => context.push(
              '/home/playlist/${playlist['ytid']}',
              extra: playlist,
            ),
            child: PlaylistCube(playlist, size: height),
          ),
        );
      },
    );
  }

  Widget _buildCarouselView(
    List<dynamic> playlists,
    int itemCount,
    double height,
  ) {
    return CarouselView.weighted(
      flexWeights: const <int>[3, 2, 1],
      itemSnapping: true,
      onTap: (index) => context.push(
        '/home/playlist/${playlists[index]['ytid']}',
        extra: playlists[index],
      ),
      children: List.generate(itemCount, (index) {
        return PlaylistCube(playlists[index], size: height * 2);
      }),
    );
  }

  Widget _buildRecommendedSongsSection() {
    return ValueListenableBuilder<bool>(
      valueListenable: externalRecommendations,
      builder: (_, recommendations, __) {
        return AsyncLoader<List<dynamic>>(
          future: getRecommendedSongs(),

          builder: (context, data) {
            if (data.isEmpty) return const SizedBox.shrink();
            return _buildRecommendedForYouSection(context, data);
          },
        );
      },
    );
  }

  Widget _buildMostPlayedSection() {
    final sectionTitle = context.l10n!.mostPlayed;

    return ValueListenableBuilder<int>(
      valueListenable: currentRecentlyPlayedLength,
      builder: (_, __, ___) {
        return ValueListenableBuilder<int>(
          valueListenable: recentlyPlayedVersion,
          builder: (_, __, ___) {
            final mostPlayedSongs = getMostPlayed(limit: 5);
            if (mostPlayedSongs.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              children: [
                SectionHeader(
                  title: sectionTitle,
                  icon: FluentIcons.music_note_2_24_filled,
                  actionButton: IconButton(
                    onPressed: () async {
                      await audioHandler.playPlaylistSong(
                        playlist: {
                          'title': sectionTitle,
                          'list': mostPlayedSongs,
                        },
                        songIndex: 0,
                      );
                    },
                    icon: Icon(
                      FluentIcons.play_circle_24_filled,
                      color: Theme.of(context).colorScheme.primary,
                      size: 30,
                    ),
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: mostPlayedSongs.length,
                  padding: commonListViewBottomPadding,
                  itemBuilder: (context, index) {
                    final borderRadius = getItemBorderRadius(
                      index,
                      mostPlayedSongs.length,
                    );
                    final song = mostPlayedSongs[index];

                    return RepaintBoundary(
                      key: listItemKey('home_most_played', index, song),
                      child: SongBar(
                        song,
                        true,
                        borderRadius: borderRadius,
                        showPlayTime: true,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRecommendedForYouSection(
    BuildContext context,
    List<dynamic> data,
  ) {
    final recommendedTitle = context.l10n!.recommendedForYou;

    return Column(
      children: [
        SectionHeader(
          title: recommendedTitle,
          icon: FluentIcons.sparkle_24_filled,
          actionButton: IconButton(
            onPressed: () async {
              await audioHandler.playPlaylistSong(
                playlist: {'title': recommendedTitle, 'list': data},
                songIndex: 0,
              );
            },
            icon: Icon(
              FluentIcons.play_circle_24_filled,
              color: Theme.of(context).colorScheme.primary,
              size: 30,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: data.length,
          padding: commonListViewBottomPadding,
          itemBuilder: (context, index) {
            final borderRadius = getItemBorderRadius(index, data.length);
            return RepaintBoundary(
              key: listItemKey('home_recommended', index, data[index]),
              child: SongBar(data[index], true, borderRadius: borderRadius),
            );
          },
        ),
      ],
    );
  }
}
