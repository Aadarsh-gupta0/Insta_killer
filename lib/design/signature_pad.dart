import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// A stroke, as fractions of the pad's box.
///
/// Normalised so the same signature can be drawn back at any size — small on a record
/// row, full width on the declaration — without resampling.
typedef SignatureStroke = List<Offset>;

/// Wins the arena outright.
///
/// The pad lives inside the scaffold's scroll view, and a plain `GestureDetector` loses
/// every vertical drag to the `Scrollable` — you would try to sign and scroll the page
/// instead. Accepting on rejection means a pan that starts on the pad belongs to the pad.
class _EagerPanRecognizer extends PanGestureRecognizer {
  _EagerPanRecognizer({super.debugOwner});

  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}

/// FR-24 — the drawn half of the signed declaration.
///
/// Nobody is verifying this against anything. It is ceremony, and the ceremony is the
/// point: writing a reason and signing it is a different act from ticking a box, and the
/// Gate shows the result back at the moment it is least welcome.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.onChanged,
    this.height = 160,
  });

  final ValueChanged<List<SignatureStroke>> onChanged;
  final double height;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<SignatureStroke> _strokes = [];
  Size _size = Size.zero;

  bool get isEmpty => _strokes.isEmpty;

  void clear() {
    setState(_strokes.clear);
    widget.onChanged(const []);
  }

  Offset _normalise(Offset local) => Offset(
        (local.dx / (_size.width == 0 ? 1 : _size.width)).clamp(0.0, 1.0),
        (local.dy / (_size.height == 0 ? 1 : _size.height)).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Signature area',
      hint: 'Draw your signature with one finger',
      value: _strokes.isEmpty ? 'empty' : 'signed',
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = Size(constraints.maxWidth, widget.height);

          return RawGestureDetector(
            gestures: {
              _EagerPanRecognizer:
                  GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
                () => _EagerPanRecognizer(debugOwner: this),
                (recognizer) => recognizer
                  ..onStart = (details) {
                    setState(() => _strokes.add([_normalise(details.localPosition)]));
                  }
                  ..onUpdate = (details) {
                    setState(() => _strokes.last.add(_normalise(details.localPosition)));
                  }
                  ..onEnd = (_) => widget.onChanged(_strokes),
              ),
            },
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                border: Border.all(color: Palette.rule, width: Stroke.hairline),
                borderRadius: Stroke.corner,
              ),
              child: CustomPaint(
                painter: _SignaturePainter(strokes: _strokes, showRule: true),
                size: Size.infinite,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Draws a stored signature. Read-only.
class SignatureView extends StatelessWidget {
  const SignatureView({super.key, required this.strokes, this.height = 80});

  final List<SignatureStroke> strokes;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Your signature',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SignaturePainter(strokes: strokes, showRule: false),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes, required this.showRule});

  final List<SignatureStroke> strokes;
  final bool showRule;

  @override
  void paint(Canvas canvas, Size size) {
    if (showRule) {
      // The line you sign on, three-quarters down, like a form.
      final y = size.height * 0.75;
      canvas.drawLine(
        Offset(size.width * 0.08, y),
        Offset(size.width * 0.92, y),
        Paint()
          ..color = Palette.rule
          ..strokeWidth = Stroke.hairline,
      );
    }

    final ink = Paint()
      ..color = Palette.ink
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;

      // A single tap is a dot, not a zero-length path, which would draw nothing.
      if (stroke.length == 1) {
        final p = Offset(stroke.first.dx * size.width, stroke.first.dy * size.height);
        canvas.drawCircle(p, 1.5, ink..style = PaintingStyle.fill);
        ink.style = PaintingStyle.stroke;
        continue;
      }

      final path = Path()
        ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) =>
      old.strokes != strokes || old.strokes.length != strokes.length;
}

/// Serialisation for the repository. Kept beside the widget because the shape is the
/// widget's, not the domain's — a signature is not a rule.
List<Object?> encodeStrokes(List<SignatureStroke> strokes) => [
      for (final stroke in strokes)
        [
          for (final point in stroke) {'x': point.dx, 'y': point.dy},
        ],
    ];

List<SignatureStroke> decodeStrokes(List<Object?> json) => [
      for (final stroke in json)
        [
          for (final point in stroke! as List<Object?>)
            Offset(
              ((point! as Map)['x'] as num).toDouble(),
              ((point as Map)['y'] as num).toDouble(),
            ),
        ],
    ];
