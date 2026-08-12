import 'package:flutter/widgets.dart';

/// The Permit Office.
///
/// The visual argument: Instagram is infinite, glossy, warm and free; this is finite,
/// papery, cold and bureaucratic. Every value here is derived from that, and the
/// prohibitions matter as much as the values — no shadows, no gradients, radius 2 at
/// most, hairlines everywhere.
///
/// Defined once. Nothing downstream should invent a colour or a spacing.
abstract final class Palette {
  const Palette._();

  /// Pale greenbar paper. The app background, and the assumed background for every
  /// contrast ratio quoted below.
  static const Color ledger = Color(0xFFE4E9DC);

  /// Text, rules, stamp outline. 13.4:1 on ledger.
  static const Color ink = Color(0xFF16211C);

  /// Hairlines, the 8pt grid, form field underlines. 1.9:1 — a line colour, never a
  /// text colour.
  static const Color rule = Color(0xFFA9B6A0);

  /// Approved permits, the active countdown. 9.0:1 on ledger.
  static const Color seal = Color(0xFF1F3A6E);

  /// Denial, quota exhausted, the shield. Used nowhere else — the moment this appears
  /// somewhere decorative it stops meaning anything.
  ///
  /// **Darkened from the brief's `#C2331F`,** which measures 4.49:1 on ledger and fails
  /// the 4.5:1 floor the SRS sets in §3.7. This is 5.1:1.
  static const Color stamp = Color(0xFFB32E1B);

  /// Archived and spent stubs. **1.6:1 — a fill, never text.** If you need to write on
  /// carbon, write in [ink].
  static const Color carbon = Color(0xFFD8B4A8);
}

/// The 8pt grid. Spacing is chosen from this list, not typed as a number.
abstract final class Space {
  const Space._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Page gutter.
  static const double gutter = 20;
}

abstract final class Stroke {
  const Stroke._();

  /// One physical hairline. Not scaled — a rule that thickens with text size stops
  /// being a rule.
  static const double hairline = 1;
  static const double heavy = 2;

  /// The brief's ceiling. Anything rounder starts to look friendly.
  static const Radius radius = Radius.circular(2);
  static const BorderRadius corner = BorderRadius.all(radius);
}

/// Type.
///
/// Display is Archivo Narrow 700, uppercase, tight — form headers and section eyebrows.
/// Data is Space Mono, always, for anything the office issued: serials, timers, quotas,
/// timestamps. A countdown in a proportional face reads as friendly; it must read as
/// machine-issued. Body is IBM Plex Sans.
abstract final class TextStyles {
  const TextStyles._();

  static const String display = 'ArchivoNarrow';
  static const String data = 'SpaceMono';
  static const String body = 'IBMPlexSans';

  // Archivo Narrow and IBM Plex Sans are variable fonts, so weight is selected by axis
  // rather than by FontWeight — declaring w700 alone would render the default instance.
  static const List<FontVariation> _bold = [FontVariation('wght', 700)];
  static const List<FontVariation> _medium = [FontVariation('wght', 500)];
  static const List<FontVariation> _regular = [FontVariation('wght', 400)];

  /// Page titles. Uppercase at the call site, not here — an uppercase transform baked
  /// into a style is invisible to a screen reader's pronunciation.
  static const TextStyle title = TextStyle(
    fontFamily: display,
    fontVariations: _bold,
    fontSize: 28,
    height: 1.05,
    letterSpacing: 0.5,
    color: Palette.ink,
  );

  /// Section eyebrows. Small, wide, quiet.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: display,
    fontVariations: _bold,
    fontSize: 12,
    height: 1.2,
    letterSpacing: 1.6,
    color: Palette.ink,
  );

  /// The big one — the countdown, the clock of time not spent.
  static const TextStyle numeral = TextStyle(
    fontFamily: data,
    fontSize: 44,
    height: 1.0,
    letterSpacing: -1,
    color: Palette.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Serials, timestamps, quota counters.
  static const TextStyle mono = TextStyle(
    fontFamily: data,
    fontSize: 13,
    height: 1.3,
    letterSpacing: 0.2,
    color: Palette.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle bodyText = TextStyle(
    fontFamily: body,
    fontVariations: _regular,
    fontSize: 16,
    height: 1.45,
    color: Palette.ink,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: body,
    fontVariations: _medium,
    fontSize: 16,
    height: 1.45,
    color: Palette.ink,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: body,
    fontVariations: _regular,
    fontSize: 13,
    height: 1.4,
    color: Palette.ink,
  );

  /// Button faces.
  static const TextStyle action = TextStyle(
    fontFamily: display,
    fontVariations: _bold,
    fontSize: 15,
    letterSpacing: 1.2,
    color: Palette.ink,
  );
}

/// Motion.
///
/// There is exactly one elaborate moment in this product — tearing a stub off the pad —
/// and it earns its elaboration by being the moment you spend something finite.
/// Everywhere else, motion is either instant or a short fade. If you are reaching for a
/// curve that is not here, the answer is probably no animation at all.
abstract final class Motion {
  const Motion._();

  static const Duration instant = Duration.zero;
  static const Duration quick = Duration(milliseconds: 120);
  static const Duration settle = Duration(milliseconds: 260);

  /// The rip, the settle, the stamp landing.
  static const Duration tear = Duration(milliseconds: 420);
  static const Duration stampFall = Duration(milliseconds: 180);

  static const Curve paper = Curves.easeOutCubic;

  /// FR from §3.7: reduced motion kills the stamp animation but keeps the haptic. Check
  /// this before animating anything, not after.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
