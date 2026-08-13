import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'design/tokens.dart';
import 'features/gate/gate_screen.dart';
import 'features/home/front_desk_screen.dart';
import 'platform/office_api.g.dart';
import 'platform/pigeon_office_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final host = OfficeHostApi();

  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(PigeonOfficeRepository(host: host)),
      hostApiProvider.overrideWithValue(host),
    ],
  );

  // Ask the platform why we were started before showing anything. Opening the Front Desk
  // for a beat and then swapping to the Gate would hand the user a moment where the only
  // thing on screen is a way out — and the Gate is on the critical path of a reflex.
  try {
    final state = await host.state();
    container.read(entryProvider.notifier).state =
        state.launchReason == LaunchReason.gate ? Entry.gate : Entry.frontDesk;
    container.read(blockedAppProvider.notifier).state = state.blockedApp;
  } catch (_) {
    // No platform on the other end (a test harness, a desktop debug run). The Front Desk
    // is the safe default: it shows state and offers nothing that needs enforcement.
  }

  OfficeFlutterApi.setUp(_PlatformEvents(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const InstaKillerApp(),
    ),
  );
}

/// Calls arriving from Kotlin while the engine is already warm.
class _PlatformEvents implements OfficeFlutterApi {
  _PlatformEvents(this.container);

  final ProviderContainer container;

  /// Instagram was opened and our process was already alive, so there was no cold launch
  /// to read an intent from.
  @override
  void onGateRequested() {
    container.read(entryProvider.notifier).state = Entry.gate;
  }

  @override
  void onGrantExpired() {
    container.read(entryProvider.notifier).state = Entry.frontDesk;
    container.read(officeProvider.notifier).reconcile();
  }
}

class InstaKillerApp extends ConsumerWidget {
  const InstaKillerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(entryProvider);

    return WidgetsApp(
      title: 'Insta_killer',
      color: Palette.ledger,
      // No MaterialApp: it brings Material's theme, ripples and page transitions, all of
      // which argue against the design. See design/tokens.dart.
      //
      // Keyed by entry so that switching to the Gate rebuilds the Navigator from
      // scratch. Without the key, being sent to the Gate while Office Rules is pushed
      // would leave Office Rules sitting on top of it — a settings screen covering the
      // one screen that exists to interrupt you.
      key: ValueKey(entry),
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
        // A cross-fade, not a slide. The office does not swoosh.
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: Motion.quick,
        reverseTransitionDuration: Motion.quick,
      ),
      home: switch (entry) {
        Entry.gate => GateScreen(
            onLeave: () => ref.read(hostApiProvider).leaveToHome(),
            blockedApp: ref.watch(blockedAppProvider),
          ),
        Entry.frontDesk => const FrontDeskScreen(),
      },
      builder: (context, child) => DefaultTextStyle(
        style: TextStyles.bodyText,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
