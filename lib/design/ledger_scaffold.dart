import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The page. Paper, a hairline under the header, and nothing else.
class LedgerScaffold extends StatelessWidget {
  const LedgerScaffold({
    super.key,
    required this.title,
    required this.body,
    this.eyebrow,
    this.footer,
  });

  final String title;
  final String? eyebrow;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.ledger,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Space.lg),
              if (eyebrow != null) ...[
                Text(eyebrow!.toUpperCase(), style: TextStyles.eyebrow),
                const SizedBox(height: Space.sm),
              ],
              Text(title.toUpperCase(), style: TextStyles.title),
              const SizedBox(height: Space.md),
              const Hairline(),
              // Everything scrolls. At the largest Dynamic Type setting even a short
              // screen overflows, and §3.7 asks for XXL without clipping.
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.lg),
                    child: body,
                  ),
                ),
              ),
              if (footer != null) ...[
                const Hairline(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.md),
                  child: footer,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.color = Palette.rule});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: Stroke.hairline, child: ColoredBox(color: color));
}

/// A labelled value in the office's house style: quiet label, mono value.
class LedgerRow extends StatelessWidget {
  const LedgerRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: value,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(label, style: TextStyles.caption)),
            const SizedBox(width: Space.md),
            Text(
              value,
              style: TextStyles.mono.copyWith(color: valueColor),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ),
    );
  }
}
