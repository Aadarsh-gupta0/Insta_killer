import 'package:pigeon/pigeon.dart';

// Regenerate with:
//   dart run pigeon --input pigeons/office_api.dart
//
// Never edit the generated files. Both sides of this contract are compiled against it,
// so a hand-edit on one side is a runtime crash on the other.

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/office_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/aadarsh/insta_killer/OfficeApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.aadarsh.insta_killer'),
    dartPackageName: 'insta_killer',
  ),
)
/// Why the Flutter engine was started.
///
/// The enforcement service and the launcher icon open the same Activity, and the app
/// must not show the Front Desk when the user was reaching for Instagram.
enum LaunchReason {
  /// The user tapped our icon.
  icon,

  /// `ForegroundWatcher` saw Instagram come to the front. Show the Gate, nothing else.
  gate,
}

/// Grants Android makes us ask for by hand, each of which the user can revoke.
class Permissions {
  late bool accessibility;
  late bool notificationAccess;
}

/// A launchable app on this device, for the Blocklist screen.
///
/// Note what iOS could never provide here: a name. `FamilyActivityPicker` returns opaque
/// tokens by design (C-3), so the iOS build can only ever say "3 apps blocked". Android
/// gives us the label and the icon, which is why the Blocklist and the Gate can both name
/// the app they are talking about.
class InstalledApp {
  late String packageName;
  late String label;

  /// PNG bytes, pre-scaled by the platform. Null when the icon could not be rendered —
  /// the row still works, it just shows initials.
  Uint8List? icon;
}

/// The little that native owns.
///
/// Deliberately small. Every rule lives in `packages/domain` and every decision is made
/// in Dart; the services only need to know whether to act and whether a permit is
/// currently running. If you find yourself wanting to add a rule here, put it in the
/// domain package and have Dart write the answer down instead.
class NativeState {
  late bool blockingEnabled;

  /// Epoch millis. 0 means no permit is running.
  late int grantEndsAtEpochMs;

  late LaunchReason launchReason;
  late Permissions permissions;

  /// The app that triggered this launch, resolved to a label and icon by the platform.
  ///
  /// Null when the app was opened from its own icon. Resolving it here rather than
  /// making Dart search the installed-apps list keeps the Gate's first frame off the
  /// critical path of a few hundred package lookups.
  InstalledApp? blockedApp;

  /// Epoch millis of the last time `ForegroundWatcher` was alive. 0 means never.
  ///
  /// This is the watchdog from D-010: OxygenOS kills background services and reverts
  /// battery exemptions on its own, and a blocker that dies quietly is worse than none.
  late int lastWatcherHeartbeatEpochMs;
}

@HostApi()
abstract class OfficeHostApi {
  NativeState state();

  /// Every launchable app, minus our own. Sorted by label.
  ///
  /// Slow enough to be worth calling once when the Blocklist opens rather than on every
  /// build — a few hundred packages, each with an icon to rasterise.
  List<InstalledApp> installedApps();

  /// Re-scopes the accessibility service to exactly these packages.
  ///
  /// The manifest declares a static list, but the whole point is that the user chooses,
  /// so the service narrows itself at runtime. Passing an empty list means the watcher
  /// observes nothing at all, which is the correct reading of "no apps blocked".
  void setWatchedPackages(List<String> packageNames);

  void setBlockingEnabled(bool enabled);

  /// Suspends blocking until [endsAtEpochMs] and schedules the T-2min and T-0
  /// notifications (FR-19). The watcher reads the same timestamp, so a permit is
  /// honoured even if every alarm is dropped.
  void beginGrant(int endsAtEpochMs);

  /// FR-21 — surrender. Cancels the alarms and resumes blocking immediately.
  void endGrant();

  /// Dart owns the schema; native owns the file. Values are JSON written by the
  /// repository, opaque to Kotlin — which is what keeps the rules in one language.
  String? read(String key);

  void write(String key, String value);

  void openAccessibilitySettings();

  void openNotificationAccessSettings();

  /// Leaves the Gate to the launcher rather than back to Instagram underneath.
  void leaveToHome();
}

@FlutterApi()
abstract class OfficeFlutterApi {
  /// Instagram was opened while the engine was already warm. Same meaning as
  /// [LaunchReason.gate], but for a process that did not have to start.
  void onGateRequested();

  /// An alarm fired and blocking resumed. The UI should stop counting down.
  void onGrantExpired();
}
