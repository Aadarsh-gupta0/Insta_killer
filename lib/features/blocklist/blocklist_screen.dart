import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

import '../../app/providers.dart';
import '../../design/ledger_scaffold.dart';
import '../../design/office_button.dart';
import '../../design/tokens.dart';
import '../../platform/office_api.g.dart';

/// Screen 5 — the Blocklist.
///
/// Selection is local until you press Save, and the whole diff is submitted as one
/// change. Toggling row by row against the live rules would file a separate request per
/// tap, and under Strict Mode each removal starts its own 24-hour countdown — so
/// unblocking three apps would mean three overlapping cooldowns, only one of which the
/// screen could show.
class BlocklistScreen extends ConsumerStatefulWidget {
  const BlocklistScreen({super.key});

  @override
  ConsumerState<BlocklistScreen> createState() => _BlocklistScreenState();
}

class _BlocklistScreenState extends ConsumerState<BlocklistScreen> {
  List<InstalledApp>? _apps;
  String? _loadError;
  Set<String> _selected = {};
  bool _loadedSelection = false;
  final TextEditingController _filter = TextEditingController();
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // One call, on open. A few hundred packages each carrying a rasterised icon is not
      // something to re-fetch on every rebuild.
      final apps = await ref.read(hostApiProvider).installedApps();
      if (mounted) setState(() => _apps = apps);
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  Future<void> _save() async {
    final office = ref.read(officeProvider).valueOrNull;
    if (office == null) return;

    final added = _selected.difference(office.rules.blockedPackages).length;
    final removed = office.rules.blockedPackages.difference(_selected).length;
    if (added == 0 && removed == 0) {
      setState(() => _notice = 'Nothing changed.');
      return;
    }

    final outcome = await ref.read(officeProvider.notifier).requestRulesChange(
          office.rules.copyWith(blockedPackages: _selected),
          description: _describe(added, removed),
        );
    if (!mounted) return;

    setState(() {
      _notice = switch (outcome) {
        ChangeApplied() => 'Applied.',
        // A removal is a loosening, so the list on screen stays as it was until the
        // cooldown elapses. Saying so here stops it reading as a failed save.
        ChangeQueued() => 'Request logged. The list changes in 24 hours.',
      };
    });
  }

  static String _describe(int added, int removed) {
    final parts = [
      if (added > 0) 'blocked $added app${added == 1 ? '' : 's'}',
      if (removed > 0) 'unblocked $removed app${removed == 1 ? '' : 's'}',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider).valueOrNull;

    // Seed the local selection from the rules once they have loaded, and only once —
    // re-seeding on every build would wipe the user's edits underneath them.
    if (office != null && !_loadedSelection) {
      _selected = {...office.rules.blockedPackages};
      _loadedSelection = true;
    }

    final apps = _apps;
    final query = _filter.text.trim().toLowerCase();
    final visible = apps == null
        ? const <InstalledApp>[]
        : apps
            .where((a) => query.isEmpty || a.label.toLowerCase().contains(query))
            .toList();

    return LedgerScaffold(
      eyebrow: 'Permit office',
      title: 'Blocklist',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Every app you tick is gated the same way: opening it shows the '
            'gate, and getting past costs a permit.',
            style: TextStyles.bodyText,
          ),
          const SizedBox(height: Space.md),
          Text(
            'Removing an app loosens the rules, so it waits out the cooldown. '
            'Adding one applies at once.',
            style: TextStyles.caption,
          ),
          const SizedBox(height: Space.lg),

          if (_notice case final String notice) ...[
            Text(notice, style: TextStyles.mono.copyWith(color: Palette.seal)),
            const SizedBox(height: Space.md),
          ],

          LedgerRow(label: 'Selected', value: '${_selected.length}'),
          const SizedBox(height: Space.md),

          if (apps == null && _loadError == null)
            Text('Reading the app list…', style: TextStyles.caption)
          else if (_loadError != null)
            Text(
              'Could not read the app list. $_loadError',
              style: TextStyles.caption.copyWith(color: Palette.stamp),
            )
          else ...[
            OfficeField(
              controller: _filter,
              hint: '${visible.length} of ${apps!.length} shown',
              maxLines: 1,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.md),
            const Hairline(),
            for (final app in visible)
              _AppRow(
                app: app,
                selected: _selected.contains(app.packageName),
                onToggle: () => setState(() {
                  if (!_selected.remove(app.packageName)) {
                    _selected.add(app.packageName);
                  }
                }),
              ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.lg),
                child: Text('No app matches that.', style: TextStyles.caption),
              ),
          ],
          const SizedBox(height: Space.xxl),
        ],
      ),
      footer: OfficeButton(
        label: 'Save the list',
        weight: ButtonWeight.primary,
        onPressed: office == null ? null : _save,
      ),
    );
  }
}

/// A form row, not an app-store tile. The icon is small and the label is the point.
class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.selected,
    required this.onToggle,
  });

  final InstalledApp app;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: selected,
      label: app.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Palette.rule, width: Stroke.hairline),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Row(
            children: [
              // A tick box drawn as a stamped square, not a platform checkbox.
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: Palette.ink, width: Stroke.hairline),
                  borderRadius: Stroke.corner,
                  color: selected ? Palette.seal : null,
                ),
                child: selected
                    ? const Text(
                        '×',
                        style: TextStyle(
                          fontFamily: TextStyles.data,
                          fontSize: 15,
                          color: Palette.ledger,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: Space.md),
              if (app.icon case final icon?) ...[
                Image.memory(icon, width: 24, height: 24, filterQuality: FilterQuality.medium),
                const SizedBox(width: Space.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.label, style: TextStyles.bodyText),
                    Text(
                      app.packageName,
                      style: TextStyles.caption.copyWith(color: Palette.rule),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
