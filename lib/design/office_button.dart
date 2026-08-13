import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ledger_scaffold.dart' show Hairline;
import 'tokens.dart';

enum ButtonWeight {
  /// The one we want you to press. Filled, larger.
  primary,

  /// Available, not encouraged.
  secondary,
}

/// A rectangle with a hairline. No elevation, no ripple, no rounded pill.
///
/// Built on [GestureDetector] rather than a Material button because Material's defaults —
/// ink splashes, 8px radii, elevation — are precisely the friendly-app vocabulary the
/// design is arguing against, and overriding all of them costs more than not using them.
class OfficeButton extends StatefulWidget {
  const OfficeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.weight = ButtonWeight.secondary,
    this.destructive = false,
    this.semanticHint,
  });

  final String label;

  /// Null disables the button. FR-17 requires the affordance to be *disabled* on quota
  /// exhaustion, not merely to refuse when pressed.
  final VoidCallback? onPressed;

  final ButtonWeight weight;
  final bool destructive;
  final String? semanticHint;

  bool get enabled => onPressed != null;

  @override
  State<OfficeButton> createState() => _OfficeButtonState();
}

class _OfficeButtonState extends State<OfficeButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.weight == ButtonWeight.primary;
    final accent = widget.destructive ? Palette.stamp : Palette.ink;

    final Color background;
    final Color foreground;
    if (!widget.enabled) {
      background = Palette.ledger;
      foreground = Palette.rule;
    } else if (primary) {
      background = _down ? Palette.seal : accent;
      foreground = Palette.ledger;
    } else {
      background = _down ? Palette.rule : Palette.ledger;
      foreground = accent;
    }

    return Semantics(
      // container: true is what makes this a node of its own. Without it the annotation
      // merges into the nearest ancestor, and a screen reader reads the whole page as one
      // utterance with no button to focus — the control is effectively invisible.
      container: true,
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      hint: widget.semanticHint,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel:
            widget.enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: Container(
          // 48 is the accessibility floor for a touch target; primary sits above it
          // because it is the action we want taken under stress.
          constraints: BoxConstraints(minHeight: primary ? 60 : 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(
              color: widget.enabled ? accent : Palette.rule,
              width: primary ? Stroke.heavy : Stroke.hairline,
            ),
            borderRadius: Stroke.corner,
          ),
          child: Text(
            widget.label.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyles.action.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

/// A field with a rule under it, in the office's hand.
///
/// Stateful only to own its [FocusNode]. Building one inline would hand `EditableText` a
/// fresh node on every keystroke — the field would lose focus as you typed, and every
/// discarded node would leak.
class OfficeField extends StatefulWidget {
  const OfficeField({
    super.key,
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.maxLines = 3,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  State<OfficeField> createState() => _OfficeFieldState();
}

class _OfficeFieldState extends State<OfficeField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditableText(
          controller: widget.controller,
          focusNode: _focus,
          autofocus: widget.autofocus,
          style: TextStyles.bodyText,
          cursorColor: Palette.seal,
          backgroundCursorColor: Palette.rule,
          maxLines: widget.maxLines,
          minLines: 1,
          onChanged: widget.onChanged,
          selectionColor: Palette.rule,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: Space.sm),
        const Hairline(),
        const SizedBox(height: Space.xs),
        Text(widget.hint, style: TextStyles.caption.copyWith(color: Palette.ink)),
      ],
    );
  }
}

/// Drag gestures on the permit pad must not fight the page's scroll. Vertical drags on
/// the stub win; everything else falls through.
class StubDragRecognizer extends VerticalDragGestureRecognizer {
  StubDragRecognizer({super.debugOwner});

  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}
