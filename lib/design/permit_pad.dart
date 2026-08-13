import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'office_button.dart';
import 'tokens.dart';

/// The signature element (brief §5): a pad of perforated permit stubs.
///
/// Requesting time is *tearing a stub off*, not pressing a button. That is the one place
/// in this product with elaborate motion, and it earns it — the gesture is the moment
/// something finite gets spent, and it should feel like spending it. Everywhere else stays
/// hairlines and exact spacing.
///
/// The pad's edge shows how many stubs are left today. When it is empty the counter is
/// stamped in [Palette.stamp] and the gesture is dead — FR-17 wants the affordance
/// disabled, not merely refusing when used.
class PermitPad extends StatefulWidget {
  const PermitPad({
    super.key,
    required this.remaining,
    required this.perDay,
    required this.enabled,
    required this.onTear,
    this.disabledReason,
    this.serial,
    this.validUntil,
  });

  final int remaining;
  final int perDay;

  /// False disables the gesture *and* the button fallback: quota gone, pause not
  /// finished, reason too short.
  final bool enabled;

  final Future<void> Function() onTear;

  /// Shown under the pad when [enabled] is false, so the dead gesture is explained
  /// rather than just unresponsive.
  final String? disabledReason;

  /// Set once a permit has been issued — the stub becomes a stamped receipt.
  final String? serial;
  final DateTime? validUntil;

  bool get issued => serial != null;

  @override
  State<PermitPad> createState() => _PermitPadState();
}

class _PermitPadState extends State<PermitPad> with TickerProviderStateMixin {
  static const double _tearThreshold = 64;
  static const double _maxDrag = 96;

  late final AnimationController _stamp = AnimationController(
    vsync: this,
    duration: Motion.stampFall,
  );

  double _drag = 0;
  bool _tearing = false;

  /// The stamp lands off-square. Fixed per instance rather than random per frame so it
  /// does not jitter on rebuild — a stamp that moves is a stamp that is not stamped.
  late final double _stampAngle =
      (math.Random(widget.serial?.hashCode ?? 7).nextDouble() * 2 + 1) *
          math.pi /
          180;

  @override
  void didUpdateWidget(PermitPad old) {
    super.didUpdateWidget(old);
    if (!old.issued && widget.issued) {
      if (Motion.reduceMotion(context)) {
        _stamp.value = 1;
      } else {
        _stamp.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _stamp.dispose();
    super.dispose();
  }

  Future<void> _completeTear() async {
    if (_tearing) return;
    setState(() => _tearing = true);

    // §3.7 — reduced motion kills the animation but keeps the haptic. The thud is the
    // part that tells you something was spent.
    unawaited(HapticFeedback.heavyImpact());
    await widget.onTear();

    if (mounted) setState(() => _tearing = false);
  }

  void _settleBack() {
    setState(() => _drag = 0);
  }

  @override
  Widget build(BuildContext context) {
    final empty = widget.remaining <= 0;
    final live = widget.enabled && !empty && !widget.issued && !_tearing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PadEdge(remaining: widget.remaining, perDay: widget.perDay),
        const SizedBox(height: Space.sm),

        Semantics(
          container: true,
          button: true,
          enabled: live,
          label: widget.issued
              ? 'Permit issued, serial ${widget.serial}'
              : 'Tear off a permit stub',
          hint: live
              ? 'Drag down, or use the button below'
              : widget.disabledReason,
          excludeSemantics: true,
          child: RawGestureDetector(
            gestures: live
                ? {
                    _EagerVerticalDrag:
                        GestureRecognizerFactoryWithHandlers<_EagerVerticalDrag>(
                      () => _EagerVerticalDrag(debugOwner: this),
                      (r) {
                        r.onUpdate = (d) {
                          setState(() {
                            _drag = (_drag + d.delta.dy).clamp(0.0, _maxDrag);
                          });
                        };
                        r.onEnd = (_) {
                          if (_drag >= _tearThreshold) {
                            unawaited(_completeTear());
                          } else {
                            _settleBack();
                          }
                        };
                        r.onCancel = _settleBack;
                      },
                    ),
                  }
                : const {},
            child: _Stub(
              drag: _drag,
              empty: empty,
              issued: widget.issued,
              enabled: widget.enabled,
              serial: widget.serial,
              validUntil: widget.validUntil,
              stamp: _stamp,
              stampAngle: _stampAngle,
            ),
          ),
        ),

        if (widget.disabledReason case final String reason
            when !live && !widget.issued) ...[
          const SizedBox(height: Space.sm),
          Text(
            reason,
            style: TextStyles.caption
                .copyWith(color: empty ? Palette.stamp : Palette.ink),
          ),
        ],

        // §3.7 requires an equivalent button for every custom gesture. Not a fallback for
        // screen readers only — a drag is also awkward one-handed.
        if (!widget.issued) ...[
          const SizedBox(height: Space.md),
          OfficeButton(
            label: 'Tear off a stub',
            onPressed: live ? _completeTear : null,
          ),
        ],
      ],
    );
  }
}

/// The pad's printed edge: how many stubs remain.
class _PadEdge extends StatelessWidget {
  const _PadEdge({required this.remaining, required this.perDay});

  final int remaining;
  final int perDay;

  @override
  Widget build(BuildContext context) {
    final empty = remaining <= 0;

    return Row(
      children: [
        Text('PERMIT PAD', style: TextStyles.eyebrow),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.xs,
          ),
          decoration: empty
              ? BoxDecoration(
                  border: Border.all(color: Palette.stamp, width: Stroke.heavy),
                  borderRadius: Stroke.corner,
                )
              : null,
          child: Text(
            empty ? 'PAD EMPTY' : '$remaining of $perDay left',
            style: TextStyles.mono.copyWith(
              color: empty ? Palette.stamp : Palette.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _Stub extends StatelessWidget {
  const _Stub({
    required this.drag,
    required this.empty,
    required this.issued,
    required this.enabled,
    required this.serial,
    required this.validUntil,
    required this.stamp,
    required this.stampAngle,
  });

  final double drag;
  final bool empty;
  final bool issued;
  final bool enabled;
  final String? serial;
  final DateTime? validUntil;
  final Animation<double> stamp;
  final double stampAngle;

  @override
  Widget build(BuildContext context) {
    final ink = empty ? Palette.rule : Palette.ink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The perforation. It separates as you drag, which is the whole feedback: the
        // stub is coming away from the pad.
        CustomPaint(
          size: const Size(double.infinity, 10),
          painter: _PerforationPainter(
            separation: drag,
            color: empty ? Palette.rule : Palette.ink,
          ),
        ),
        AnimatedSlide(
          offset: Offset(0, drag / 160),
          duration: drag == 0 ? Motion.settle : Duration.zero,
          curve: Motion.paper,
          child: Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: issued ? Palette.ledger : null,
              border: Border.all(color: ink, width: Stroke.hairline),
              borderRadius: Stroke.corner,
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('PERMIT',
                            style: TextStyles.eyebrow.copyWith(color: ink)),
                        Text(
                          serial ?? '№ ————',
                          style: TextStyles.mono.copyWith(color: ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    Text(
                      '15 MINUTES',
                      style: TextStyles.title.copyWith(fontSize: 30, color: ink),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      validUntil == null
                          ? 'VALID UNTIL ——:——'
                          : 'VALID UNTIL ${_hhmm(validUntil!)}',
                      style: TextStyles.mono.copyWith(color: ink),
                    ),
                    const SizedBox(height: Space.md),
                    Text(
                      issued
                          ? 'Tear along the perforation. Filed.'
                          : empty
                              ? 'No stubs remain on this pad.'
                              : 'Drag down to tear off.',
                      style: TextStyles.caption.copyWith(color: ink),
                    ),
                  ],
                ),

                if (issued)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: stamp,
                      builder: (context, _) => Align(
                        alignment: Alignment.bottomRight,
                        child: Opacity(
                          opacity: stamp.value,
                          child: Transform.rotate(
                            angle: stampAngle,
                            // Lands from slightly above, and slightly oversized, so it
                            // reads as pressed down rather than faded in.
                            child: Transform.scale(
                              scale: 1 + (1 - stamp.value) * 0.4,
                              child: const _ApprovedStamp(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _hhmm(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

class _ApprovedStamp extends StatelessWidget {
  const _ApprovedStamp();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: Palette.seal, width: Stroke.heavy),
        borderRadius: Stroke.corner,
      ),
      child: Text(
        'ISSUED',
        style: TextStyles.eyebrow.copyWith(color: Palette.seal, fontSize: 14),
      ),
    );
  }
}

/// The dashed line, opening up as the stub is pulled away.
class _PerforationPainter extends CustomPainter {
  const _PerforationPainter({required this.separation, required this.color});

  final double separation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = Stroke.hairline
      ..strokeCap = StrokeCap.round;

    const dash = 6.0;
    const gap = 5.0;
    // The two halves of the perforation pull apart, up to a few pixels.
    final spread = (separation / 96 * 3).clamp(0.0, 3.0);
    final y = size.height / 2;

    for (var x = 0.0; x < size.width; x += dash + gap) {
      final end = math.min(x + dash, size.width);
      canvas.drawLine(Offset(x, y - spread), Offset(end, y - spread), paint);
      canvas.drawLine(Offset(x, y + spread), Offset(end, y + spread), paint);
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) =>
      old.separation != separation || old.color != color;
}

/// The stub must win vertical drags against the page's scroll view, or tearing just
/// scrolls the Gate.
class _EagerVerticalDrag extends VerticalDragGestureRecognizer {
  _EagerVerticalDrag({super.debugOwner});

  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}
