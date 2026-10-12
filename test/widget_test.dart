import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmoo/widgets/playlist_page/shuffle_play_button.dart';

void main() {
  testWidgets('ShufflePlayButton renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShufflePlayButton(songs: []),
        ),
      ),
    );

    expect(find.byIcon(FluentIcons.arrow_shuffle_24_regular), findsOneWidget);
  });
}
