import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

import '../../app/providers.dart';
import '../../design/ledger_scaffold.dart';
import '../../design/office_button.dart';
import '../../design/tokens.dart';
import '../../platform/office_api.g.dart';
import '../blocklist/blocklist_screen.dart';
import '../guardian/guardian_screen.dart';

/// Screen 9 — Office Rules.
///
/// The asymmetry is the point and the screen has to make it obvious: anything that
/// tightens lands as you tap it, anything that loosens is *requested* and waits a day.
/// So loosening controls say "Request", show the countdown, and offer a cancel — never a
/// switch that silently does nothing for 24 hours.
class OfficeRulesScreen extends ConsumerStatefulWidget {
  const OfficeRulesScreen({super.key});

  @override
  ConsumerState<OfficeRulesScreen> createState() => _OfficeRulesScreenState();
}

class _OfficeRulesScreenState extends ConsumerState<OfficeRulesScreen>
    with WidgetsBindingObserver {
  Timer? _tick;
  NativeState? _native;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Drives the cooldown countdown, and re-reads permissions so returning from the
    // Settings app updates the rows without the user having to do anything.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _refreshNative();
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNative();
      ref.read(officeProvider.notifier).reconcile();
    }
  }

  Future<void> _refreshNative() async {
    try {
      final state = await ref.read(hostApiProvider).state();
      if (mounted) setState(() => _native = state);
    } catch (_) {
      // No platform on the other end (widget tests, desktop debug). The permissions
      // block simply does not render.
    }
  }

  Future<void> _request(OfficeRules to, String description) async {
    final outcome = await ref
        .read(officeProvider.notifier)
        .requestRulesChange(to, description: description);
    if (!mounted) return;

    setState(() {
      _notice = switch (outcome) {
        ChangeApplied() => 'Applied.',
        ChangeQueued(:final pending) =>
          'Request logged. Applies ${_stamp(pending.appliesAt)}.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider).valueOrNull;
    if (office == null) {
      return const LedgerScaffold(
        title: 'Office rules',
        body: Text('Opening…', style: TextStyles.bodyText),
      );
    }

    final rules = office.rules;
    final native = _native;
    final canEnforce = native?.permissions.accessibility ?? false;

    return LedgerScaffold(
      eyebrow: 'Permit office',
      title: 'Office rules',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (office.pendingChange case final PendingChange pending) ...[
            _PendingNotice(
              pending: pending,
              now: ref.read(clockProvider).wall(),
              onCancel: () =>
                  ref.read(officeProvider.notifier).cancelPendingChange(),
            ),
            const SizedBox(height: Space.xl),
          ],

          if (_notice case final String notice) ...[
            Text(notice, style: TextStyles.mono.copyWith(color: Palette.seal)),
            const SizedBox(height: Space.lg),
          ],

          Text('ENFORCEMENT', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          const Hairline(),

          _Switch(
            label: 'Block Instagram',
            description: rules.enforcementEnabled
                ? 'Opening Instagram shows the gate.'
                : 'Nothing is blocked. Instagram opens normally.',
            value: rules.enforcementEnabled,
            // Switching on is a tightening and lands immediately. Switching off is the
            // largest loosening there is and queues like any other — the label changes to
            // say so rather than leaving the user to discover it.
            actionLabel: rules.enforcementEnabled
                ? 'Request blocking off'
                : 'Start blocking',
            enabled: canEnforce || rules.enforcementEnabled,
            onPressed: () => _request(
              rules.copyWith(enforcementEnabled: !rules.enforcementEnabled),
              rules.enforcementEnabled ? 'blocking off' : 'blocking on',
            ),
          ),

          if (!canEnforce && native != null) ...[
            const SizedBox(height: Space.sm),
            _Warning(
              text: 'Blocking cannot start until the accessibility service is '
                  'switched on. Without it nothing detects Instagram opening.',
            ),
          ],

          const SizedBox(height: Space.xl),
          Text('PERMISSIONS', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          const Hairline(),

          if (native == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              child: Text('Not available.', style: TextStyles.caption),
            )
          else ...[
            _PermissionRow(
              label: 'Accessibility service',
              granted: native.permissions.accessibility,
              detail: 'Detects when Instagram opens. Reads no screen content.',
              onGrant: () =>
                  ref.read(hostApiProvider).openAccessibilitySettings(),
            ),
            _PermissionRow(
              label: 'Notification access',
              granted: native.permissions.notificationAccess,
              detail: 'Only for the VIP list. Nothing is suppressed.',
              onGrant: () =>
                  ref.read(hostApiProvider).openNotificationAccessSettings(),
            ),
            _WatchdogRow(
              heartbeatEpochMs: native.lastWatcherHeartbeatEpochMs,
              now: ref.read(clockProvider).wall(),
              enforcing: rules.enforcementEnabled,
            ),
          ],

          const SizedBox(height: Space.xl),
          Text('BLOCKED APPS', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          const Hairline(),
          LedgerRow(
            label: 'Apps on the list',
            value: '${rules.blockedAppCount}',
            valueColor:
                rules.blockedAppCount == 0 ? Palette.stamp : Palette.ink,
          ),
          if (rules.blockedAppCount == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(
                'Nothing is on the list, so nothing will be gated even with '
                'blocking switched on.',
                style: TextStyles.caption,
              ),
            ),
          const SizedBox(height: Space.sm),
          OfficeButton(
            label: 'Edit the list',
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                pageBuilder: (context, _, _) => const BlocklistScreen(),
              ),
            ),
          ),

          const SizedBox(height: Space.xl),
          Text('PERMITS', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          const Hairline(),

          _Stepper(
            label: 'Permits per day',
            value: '${rules.quota.permitsPerDay}',
            // Fewer is stricter, so it applies now. More is a request.
            onDown: rules.quota.permitsPerDay > 0
                ? () => _request(
                      rules.copyWith(
                        quota: rules.quota.copyWith(
                          permitsPerDay: rules.quota.permitsPerDay - 1,
                        ),
                      ),
                      'quota to ${rules.quota.permitsPerDay - 1}',
                    )
                : null,
            onUp: () => _request(
              rules.copyWith(
                quota: rules.quota.copyWith(
                  permitsPerDay: rules.quota.permitsPerDay + 1,
                ),
              ),
              'quota to ${rules.quota.permitsPerDay + 1}',
            ),
          ),

          LedgerRow(
            label: 'Permit length',
            value: '${rules.grantDuration.inMinutes} min',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              'Fifteen minutes is the shortest interval the platform schedules '
              'reliably. Shorter permits are not offered.',
              style: TextStyles.caption,
            ),
          ),
          LedgerRow(
            label: 'Day resets at',
            value: rules.quota.boundary.toString(),
          ),

          const SizedBox(height: Space.xl),
          Text('STRICTNESS', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          const Hairline(),

          _Switch(
            label: 'Strict mode',
            description: rules.strictMode
                ? 'Loosening any rule waits 24 hours. Tightening applies now.'
                : 'Changes apply immediately, in both directions.',
            value: rules.strictMode,
            actionLabel: rules.strictMode
                ? 'Request strict mode off'
                : 'Turn strict mode on',
            onPressed: () => _request(
              rules.copyWith(strictMode: !rules.strictMode),
              rules.strictMode ? 'strict mode off' : 'strict mode on',
            ),
          ),

          const SizedBox(height: Space.xl),
          Text('GUARDIAN', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          const Hairline(),
          LedgerRow(
            label: 'Paired',
            value: office.guardian?.name ?? 'nobody',
            valueColor: office.guardianPaired ? Palette.seal : Palette.ink,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              office.guardianPaired
                  ? 'Loosening waits out its cooldown and needs their code.'
                  : 'Without one, the cooldown is the only thing between you '
                      'and a looser rule.',
              style: TextStyles.caption,
            ),
          ),
          OfficeButton(
            label: office.guardianPaired ? 'Guardian' : 'Pair a guardian',
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                pageBuilder: (context, _, _) => const GuardianScreen(),
              ),
            ),
          ),

          const SizedBox(height: Space.xl),
          const Hairline(),
          const SizedBox(height: Space.md),
          // FR-28 — stated plainly, in Settings, exactly as the SRS requires.
          Text('THE CEILING', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          Text(
            'Uninstalling this app removes every block. Nothing here prevents '
            'that, and no setting in this screen changes it.\n\n'
            'This phone may also switch the block off on its own: OxygenOS '
            'kills background services to save battery, and is known to undo '
            'the exemption days after you grant it. Lock the app in Recents.',
            style: TextStyles.bodyText,
          ),
          const SizedBox(height: Space.xxl),
        ],
      ),
    );
  }

  static String _stamp(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')} '
      'on ${at.day}/${at.month}';
}

/// FR-25 and FR-26 in one block: what is coming, when, and the way out.
class _PendingNotice extends StatelessWidget {
  const _PendingNotice({
    required this.pending,
    required this.now,
    required this.onCancel,
  });

  final PendingChange pending;
  final DateTime now;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final left = pending.remaining(now);
    final hours = left.inHours.toString().padLeft(2, '0');
    final minutes = (left.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (left.inSeconds % 60).toString().padLeft(2, '0');

    return Semantics(
      container: true,
      label: 'Pending change: ${pending.description}. '
          '${left.inHours} hours remaining.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          border: Border.all(color: Palette.seal, width: Stroke.heavy),
          borderRadius: Stroke.corner,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('CHANGE QUEUED',
                style: TextStyles.eyebrow.copyWith(color: Palette.seal)),
            const SizedBox(height: Space.sm),
            Text(pending.description, style: TextStyles.bodyStrong),
            const SizedBox(height: Space.sm),
            Text(
              '$hours:$minutes:$seconds',
              style: TextStyles.numeral.copyWith(
                fontSize: 32,
                color: Palette.seal,
              ),
            ),
            Text('until it applies', style: TextStyles.caption),
            const SizedBox(height: Space.md),
            OfficeButton(
              label: 'Cancel this change',
              onPressed: onCancel,
              semanticHint: 'Withdraws the request. Nothing changes.',
            ),
          ],
        ),
      ),
    );
  }
}

/// D-010 — the app reports its own death rather than showing an unearned clean streak.
class _WatchdogRow extends StatelessWidget {
  const _WatchdogRow({
    required this.heartbeatEpochMs,
    required this.now,
    required this.enforcing,
  });

  final int heartbeatEpochMs;
  final DateTime now;
  final bool enforcing;

  @override
  Widget build(BuildContext context) {
    if (!enforcing) {
      return const LedgerRow(label: 'Watcher last seen', value: 'idle');
    }
    if (heartbeatEpochMs == 0) {
      return const LedgerRow(
        label: 'Watcher last seen',
        value: 'never',
        valueColor: Palette.stamp,
      );
    }

    final seen = DateTime.fromMillisecondsSinceEpoch(heartbeatEpochMs);
    final age = now.difference(seen);
    final value = age.inMinutes < 1
        ? 'just now'
        : age.inHours < 1
            ? '${age.inMinutes} min ago'
            : age.inDays < 1
                ? '${age.inHours} h ago'
                : '${age.inDays} d ago';

    return LedgerRow(label: 'Watcher last seen', value: value);
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.granted,
    required this.detail,
    required this.onGrant,
  });

  final String label;
  final bool granted;
  final String detail;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerRow(
            label: label,
            value: granted ? 'granted' : 'not granted',
            valueColor: granted ? Palette.ink : Palette.stamp,
          ),
          Text(detail, style: TextStyles.caption),
          if (!granted) ...[
            const SizedBox(height: Space.sm),
            OfficeButton(label: 'Open settings', onPressed: onGrant),
          ],
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.description,
    required this.value,
    required this.actionLabel,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final String description;
  final bool value;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerRow(
            label: label,
            value: value ? 'on' : 'off',
            valueColor: value ? Palette.seal : Palette.ink,
          ),
          Text(description, style: TextStyles.caption),
          const SizedBox(height: Space.sm),
          OfficeButton(
            label: actionLabel,
            weight: value ? ButtonWeight.secondary : ButtonWeight.primary,
            onPressed: enabled ? onPressed : null,
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onDown,
    required this.onUp,
  });

  final String label;
  final String value;
  final VoidCallback? onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerRow(label: label, value: value),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: OfficeButton(
                  label: 'Fewer',
                  onPressed: onDown,
                  semanticHint: 'Stricter. Applies immediately.',
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: OfficeButton(
                  label: 'Request more',
                  onPressed: onUp,
                  semanticHint: 'Looser. Waits 24 hours under strict mode.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        border: Border.all(color: Palette.stamp, width: Stroke.hairline),
        borderRadius: Stroke.corner,
      ),
      child: Text(text, style: TextStyles.caption),
    );
  }
}
