import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

import '../../app/providers.dart';
import '../../design/ledger_scaffold.dart';
import '../../design/office_button.dart';
import '../../design/permit_pad.dart';
import '../../design/tokens.dart';
import '../../platform/office_api.g.dart';

/// FR-13 — at least four seconds, not skippable.
const Duration gatePause = Duration(seconds: 4);

/// The screen that has to beat a reflex.
///
/// It is on the critical path of a habit, so it does three things in order and nothing
/// else: it takes four seconds away, it shows the user their own words back, and only
/// then offers a way through. Leaving is the larger, default action; asking for a permit
/// is available but not encouraged.
class GateScreen extends ConsumerStatefulWidget {
  const GateScreen({super.key, this.onLeave, this.blockedApp});

  /// On Android this pops the Activity back to the launcher. Injected so the screen
  /// stays testable without a platform channel.
  final VoidCallback? onLeave;

  /// The app that was just turned away, if the platform could name it.
  ///
  /// Android hands us package names, so unlike the iOS design (C-3, opaque tokens) the
  /// Gate can be specific about what it stopped. A generic block screen is easy to
  /// argue with; one that names the thing you reached for is not.
  final InstalledApp? blockedApp;

  @override
  ConsumerState<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends ConsumerState<GateScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;
  Timer? _pauseTimer;

  bool _pauseComplete = false;
  bool _requesting = false;
  final TextEditingController _reason = TextEditingController();
  PermitRefused? _refusal;

  /// Set once a permit is issued, which turns the stub into a stamped receipt.
  String? _issuedSerial;
  DateTime? _issuedUntil;

  @override
  void initState() {
    super.initState();

    // FR-7 — the attempt is recorded whether or not it turns into a permit. This is the
    // number the product is judged on, so it is logged before the user can act.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(officeProvider.notifier).recordAttempt();
    });

    _breath = AnimationController(vsync: this, duration: gatePause);
    _breath.forward();

    // A wall-clock timer rather than the animation's completion, so that disabling
    // animations for accessibility cannot also disable the pause.
    _pauseTimer = Timer(gatePause, () {
      if (mounted) setState(() => _pauseComplete = true);
    });
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _breath.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    final decision =
        await ref.read(officeProvider.notifier).requestPermit(_reason.text);
    if (!mounted) return;

    // Paint the outcome first, then fire the haptic. Awaiting the platform channel
    // before calling setState would hold the refusal off the screen for as long as the
    // channel takes to answer — on a refusal the user is already in a bad moment, and
    // making them wait to be told no is the wrong place to be slow.
    setState(() {
      switch (decision) {
        case PermitGranted(:final permit):
          _refusal = null;
          // Serial numbered per day, so it reads as a record rather than a UUID.
          final issuedToday = ref
              .read(officeProvider)
              .valueOrNull
              ?.events
              .where((e) => e.kind == EventKind.permitIssued)
              .length ??
              1;
          _issuedSerial = '№ ${issuedToday.toString().padLeft(4, '0')}';
          _issuedUntil = permit.nominalEnd;
        case PermitRefused():
          _refusal = decision;
      }
      _requesting = false;
    });

    unawaited(switch (decision) {
      PermitGranted() => HapticFeedback.heavyImpact(),
      PermitRefused() => HapticFeedback.vibrate(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider).valueOrNull;
    final quota = ref.watch(quotaStateProvider);
    final reasonLength = _reason.text.trim().length;
    final reasonOk = reasonLength >= minimumReasonLength;

    return LedgerScaffold(
      eyebrow: 'Permit office',
      title: 'This app is closed',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.blockedApp case final InstalledApp app) ...[
            _BlockedAppRow(app: app),
            const SizedBox(height: Space.lg),
          ],
          _BreathingBeat(controller: _breath, complete: _pauseComplete),
          const SizedBox(height: Space.xl),

          // FR-24 — their own reason, in their own words, shown back at the moment it
          // is least welcome and most useful.
          if (office?.declaration case final String declaration
              when declaration.trim().isNotEmpty) ...[
            Text('YOU WROTE', style: TextStyles.eyebrow),
            const SizedBox(height: Space.sm),
            Text(declaration, style: TextStyles.bodyStrong),
            const SizedBox(height: Space.xl),
          ],

          if (_pauseComplete) ...[
            Text('STATE YOUR REASON', style: TextStyles.eyebrow),
            const SizedBox(height: Space.sm),
            OfficeField(
              controller: _reason,
              hint: reasonOk
                  ? '$reasonLength characters'
                  : '$reasonLength of $minimumReasonLength characters minimum',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.xl),

            // The pad replaces what used to be a plain "Request a permit" button.
            // Spending something finite should feel like spending it (brief §5).
            if (quota != null)
              PermitPad(
                remaining: quota.remaining,
                perDay: quota.permitsPerDay,
                enabled: reasonOk && !_requesting,
                serial: _issuedSerial,
                validUntil: _issuedUntil,
                onTear: _request,
                disabledReason: quota.exhausted
                    ? 'Pad empty. Next issue ${_clockTime(quota.resetsAt)}.'
                    : reasonOk
                        ? null
                        : 'State a reason of at least $minimumReasonLength '
                            'characters first.',
              ),
          ],

          if (_refusal case final PermitRefused refusal) ...[
            const SizedBox(height: Space.lg),
            _RefusalNotice(refusal: refusal),
          ],
        ],
      ),
      footer: OfficeButton(
        label: _issuedSerial == null ? 'Leave' : 'Done',
        weight: ButtonWeight.primary,
        onPressed: _pauseComplete ? widget.onLeave : null,
        semanticHint: _pauseComplete
            ? 'Closes this and returns to the home screen'
            : 'Available once the pause finishes',
      ),
    );
  }
}

/// Four seconds, made visible.
///
/// Not decoration — a countdown you can watch is easier to sit through than a dead
/// screen, and sitting through it is the entire intervention.
/// Names the app that was turned away. Icon small, label in the office's hand.
class _BlockedAppRow extends StatelessWidget {
  const _BlockedAppRow({required this.app});

  final InstalledApp app;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${app.label} was blocked',
      excludeSemantics: true,
      child: Row(
        children: [
          if (app.icon case final icon?) ...[
            Image.memory(icon, width: 28, height: 28,
                filterQuality: FilterQuality.medium),
            const SizedBox(width: Space.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TURNED AWAY', style: TextStyles.eyebrow),
                Text(app.label, style: TextStyles.bodyStrong),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreathingBeat extends StatelessWidget {
  const _BreathingBeat({required this.controller, required this.complete});

  final AnimationController controller;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduceMotion(context);

    return Semantics(
      liveRegion: true,
      label: complete ? 'Pause complete' : 'Please wait four seconds',
      excludeSemantics: true,
      child: SizedBox(
        height: 120,
        child: Center(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final remaining =
                  (gatePause.inMilliseconds * (1 - controller.value)) / 1000;

              if (reduced) {
                // §3.7: reduced motion kills the animation, never the information.
                return Text(
                  complete ? 'READY' : remaining.clamp(0, 4).toStringAsFixed(1),
                  style: TextStyles.numeral.copyWith(color: Palette.seal),
                );
              }

              // A ring that closes. No easing — a mechanical sweep, not a friendly one.
              return CustomPaint(
                size: const Size(112, 112),
                painter: _BeatPainter(progress: controller.value),
                child: SizedBox(
                  width: 112,
                  height: 112,
                  child: Center(
                    child: Text(
                      complete
                          ? 'READY'
                          : remaining.clamp(0, 4).toStringAsFixed(1),
                      style: TextStyles.mono.copyWith(
                        fontSize: complete ? 16 : 24,
                        color: Palette.seal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BeatPainter extends CustomPainter {
  const _BeatPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = Stroke.hairline
      ..color = Palette.rule;
    final swept = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = Stroke.heavy
      ..color = Palette.seal;

    canvas.drawCircle(rect.center, size.width / 2 - 1, track);
    canvas.drawArc(
      rect.deflate(1),
      -1.5707963, // twelve o'clock
      6.2831853 * progress,
      false,
      swept,
    );
  }

  @override
  bool shouldRepaint(_BeatPainter old) => old.progress != progress;
}

/// NFR-4 — every refusal states the reason and the next possible time.
class _RefusalNotice extends StatelessWidget {
  const _RefusalNotice({required this.refusal});

  final PermitRefused refusal;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          border: Border.all(color: Palette.stamp, width: Stroke.heavy),
          borderRadius: Stroke.corner,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _headline(refusal.reason),
              style: TextStyles.eyebrow.copyWith(color: Palette.stamp),
            ),
            const SizedBox(height: Space.sm),
            Text(refusal.detail ?? '', style: TextStyles.bodyText),
            if (refusal.availableAt case final DateTime at) ...[
              const SizedBox(height: Space.sm),
              Text(
                'Next issue ${_clockTime(at)}.',
                style: TextStyles.mono,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _headline(RefusalReason reason) => switch (reason) {
        RefusalReason.quotaExhausted => 'Pad empty',
        RefusalReason.scheduledWindow => 'Closed hours',
        RefusalReason.reasonTooShort => 'Incomplete form',
        RefusalReason.permitAlreadyActive => 'Permit already issued',
        RefusalReason.clockTampered => 'Clock discrepancy',
      };

}

String _clockTime(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';
