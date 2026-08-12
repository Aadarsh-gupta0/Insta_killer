/// Time, treated as hostile.
///
/// A-4 in the SRS says device clock changes are adversarial, and FR-20 requires us to
/// resolve any disagreement in favour of the stricter interpretation. That is not
/// paranoia — moving the clock back is the single easiest way to extend a permit
/// forever, and it takes four taps in Settings.
library;

/// Both clocks the rules need.
///
/// [wall] is what the user sees and can change. [monotonic] counts up from an arbitrary
/// origin and cannot be set — on iOS this is `ProcessInfo.systemUptime`, on Android
/// `SystemClock.elapsedRealtime()`. Its weakness is that it resets on reboot.
abstract interface class Clock {
  DateTime wall();

  Duration monotonic();
}

/// The real one.
class SystemClock implements Clock {
  const SystemClock();

  static final Stopwatch _uptime = Stopwatch()..start();

  @override
  DateTime wall() => DateTime.now();

  @override
  Duration monotonic() => _uptime.elapsed;
}

/// A clock you can lie to, for tests.
class FakeClock implements Clock {
  FakeClock({required DateTime wall, Duration monotonic = Duration.zero})
      : _wall = wall,
        _monotonic = monotonic;

  DateTime _wall;
  Duration _monotonic;

  @override
  DateTime wall() => _wall;

  @override
  Duration monotonic() => _monotonic;

  /// Time passing honestly: both clocks advance together.
  void advance(Duration by) {
    _wall = _wall.add(by);
    _monotonic += by;
  }

  /// The attack: wall clock moves, monotonic does not.
  void setWallClock(DateTime to) => _wall = to;

  /// A reboot. Monotonic restarts from zero; wall time survives.
  void reboot({Duration downtime = const Duration(seconds: 30)}) {
    _wall = _wall.add(downtime);
    _monotonic = Duration.zero;
  }
}

/// A pair of readings taken at the same instant, stored alongside anything with a
/// deadline. Comparing a later pair against this one is what makes tampering visible.
class ClockStamp {
  const ClockStamp({required this.wall, required this.monotonic});

  final DateTime wall;
  final Duration monotonic;

  static ClockStamp now(Clock clock) =>
      ClockStamp(wall: clock.wall(), monotonic: clock.monotonic());

  Map<String, Object?> toJson() => {
        'wall': wall.toUtc().toIso8601String(),
        'monotonic': monotonic.inMilliseconds,
      };

  static ClockStamp fromJson(Map<String, Object?> json) => ClockStamp(
        wall: DateTime.parse(json['wall']! as String).toLocal(),
        monotonic: Duration(milliseconds: json['monotonic']! as int),
      );
}

enum TamperVerdict {
  /// Both clocks agree within tolerance.
  none,

  /// Wall clock moved backwards relative to monotonic — someone is buying time.
  rewound,

  /// Wall clock jumped forwards. Not an attack on a permit (it ends one sooner), but it
  /// can skip a quota reset, so callers still need to know.
  advanced,
}

class ElapsedResolution {
  const ElapsedResolution({required this.elapsed, required this.verdict});

  /// How much time to treat as having passed. Always the stricter of the two readings.
  final Duration elapsed;

  final TamperVerdict verdict;

  bool get tampered => verdict != TamperVerdict.none;
}

/// Resolves how much time has really passed since [since].
///
/// The rule is one line — take whichever clock says *more* time has elapsed — and it is
/// correct in every direction that matters:
///
///   * wall rewound  → wall elapsed is small, monotonic is not, monotonic wins, the
///     permit still ends on time
///   * wall advanced → wall elapsed is larger, wall wins, the permit ends early
///   * reboot        → monotonic resets to ~0, wall wins, permit ends on time
///
/// The one case it cannot catch alone is reboot *and* rewind together, where both
/// readings are small. [ClockGuard] closes that with a persisted high-water mark.
ElapsedResolution resolveElapsed({
  required ClockStamp since,
  required Clock clock,
  Duration tolerance = const Duration(seconds: 5),
}) {
  final wallElapsed = clock.wall().difference(since.wall);
  final monotonicElapsed = clock.monotonic() - since.monotonic;

  // A negative monotonic delta means the device rebooted; treat it as no information
  // rather than as negative time.
  final monotonic =
      monotonicElapsed.isNegative ? Duration.zero : monotonicElapsed;
  final wall = wallElapsed.isNegative ? Duration.zero : wallElapsed;

  final drift = wall - monotonic;
  final TamperVerdict verdict;
  if (drift < -tolerance) {
    verdict = TamperVerdict.rewound;
  } else if (drift > tolerance && monotonicElapsed >= Duration.zero) {
    verdict = TamperVerdict.advanced;
  } else {
    verdict = TamperVerdict.none;
  }

  return ElapsedResolution(
    elapsed: wall > monotonic ? wall : monotonic,
    verdict: verdict,
  );
}

/// Catches the reboot-plus-rewind case by remembering the furthest-forward wall time
/// ever observed. Wall time is monotonic in reality; if we ever see it go backwards,
/// something was changed by hand.
class ClockGuard {
  ClockGuard({DateTime? highWaterMark}) : _highWaterMark = highWaterMark;

  DateTime? _highWaterMark;

  DateTime? get highWaterMark => _highWaterMark;

  /// Feed every observation through this. Returns true when the clock has moved
  /// backwards by more than [tolerance], which callers must treat as an expiry.
  bool observe(DateTime wallNow,
      {Duration tolerance = const Duration(minutes: 1)}) {
    final mark = _highWaterMark;
    if (mark == null) {
      _highWaterMark = wallNow;
      return false;
    }
    if (wallNow.isBefore(mark.subtract(tolerance))) {
      // Deliberately not advancing the mark: the user must return to real time before
      // anything is trusted again.
      return true;
    }
    if (wallNow.isAfter(mark)) _highWaterMark = wallNow;
    return false;
  }
}
