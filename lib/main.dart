import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'data/office_repository.dart';
import 'design/tokens.dart';
import 'features/gate/gate_screen.dart';
import 'features/home/front_desk_screen.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        // TODO(platform): swap for the Pigeon-backed repository once the Android
        // channel lands. Everything above this line is already written against the
        // interface, so it is a one-line change.
        repositoryProvider.overrideWithValue(InMemoryOfficeRepository()),
      ],
      child: const InstaKillerApp(),
    ),
  );
}

/// Which screen the app opens on depends on how it was launched.
///
/// Android's `ForegroundWatcher` starts us because Instagram was opened, in which case
/// the Gate is the only thing that should appear. Tapping the icon opens the Front Desk.
enum Entry { frontDesk, gate }

class InstaKillerApp extends StatelessWidget {
  const InstaKillerApp({super.key, this.entry = Entry.frontDesk});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Insta_killer',
      color: Palette.ledger,
      // No MaterialApp: it would drag in Material's theme, ripples and page
      // transitions, all of which argue against the design. See design/tokens.dart.
      builder: (context, _) => DefaultTextStyle(
        style: TextStyles.bodyText,
        child: switch (entry) {
          Entry.gate => const GateScreen(),
          Entry.frontDesk => const FrontDeskScreen(),
        },
      ),
    );
  }
}
