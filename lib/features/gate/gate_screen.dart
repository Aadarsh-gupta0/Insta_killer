import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

import '../../app/providers.dart';
import '../../design/ledger_scaffold.dart';
import '../../design/office_button.dart';
import '../../design/tokens.dart';

/// FR-13 — at least four seconds, not skippable.
const Duration gatePause = Duration(seconds: 4);

/// The screen that has to beat a reflex.
///
/// It is on the critical path of a habit, so it does three things in order and nothing
/// else: it takes four seconds away, it shows the user their own words back, and only
/// then offers a way through. Leaving is the larger, default action; asking for a permit
/// is available but not encouraged.
class GateScreen extends ConsumerStatefulWidget {
  const GateScreen({super.key, this.onLeave});

  /// On Android this pops the Activity back to the launcher. Injected so the screen
  /// stays testable without a platform channel.
  final VoidCallback? onLeave;

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
    setState(() => _requesting = true);
    final decision =
        await ref.read(officeProvider.notifier).requestPermit(_reason.text);
    if (!mounted) return;

    // Paint the outcome first, then fire the haptic. Awaiting the platform channel
    // before calling setState would hold the refusal off the screen for as long as the
    // channel takes to answer — on a refusal the user is already in a bad moment, and
    // making them wait to be told no is the wrong place to be slow.
    setState(() {
      _refusal = switch (decision) {
        PermitGranted() => null,
        PermitRefused() => decision,
      };
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

          if (quota != null)
            LedgerRow(
              label: 'Permits remaining today',
              value: '${quota.remaining} of ${quota.permitsPerDay}',
              valueColor: quota.exhausted ? Palette.stamp : Palette.ink,
            ),

          if (_pauseComplete) ...[
            const SizedBox(height: Space.lg),
            Text('STATE YOUR REASON', style: TextStyles.eyebrow),
            const SizedBox(height: Space.sm),
            OfficeField(
              controller: _reason,
              hint: reasonOk
                  ? '$reasonLength characters'
                  : '$reasonLength of $minimumReasonLength characters minimum',
              onChanged: (_) => setState(() {}),
            ),
          ],

          if (_refusal case final PermitRefused refusal) ...[
            const SizedBox(height: Space.lg),
            _RefusalNotice(refusal: refusal),
          ],
        ],
      ),
      footer: Column(
        children: [
          OfficeButton(
            label: 'Leave',
            weight: ButtonWeight.primary,
            onPressed: _pauseComplete ? widget.onLeave : null,
            semanticHint: _pauseComplete
                ? 'Closes this and returns to the home screen'
                : 'Available once the pause finishes',
          ),
          const SizedBox(height: Space.sm),
          OfficeButton(
            label: 'Request a permit',
            onPressed: (_pauseComplete && reasonOk && !_requesting)
                ? _request
                : null,
            semanticHint: reasonOk
                ? 'Spends one of today\'s permits'
                : 'Type at least $minimumReasonLength characters first',
          ),
        ],
      ),
    );
  }
}

/// Four seconds, made visible.
///
/// Not decoration — a countdown you can watch is easier to sit through than a dead
/// screen, and sitting through it is the entire intervention.
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

  static String _clockTime(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
