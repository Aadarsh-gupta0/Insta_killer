import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

import '../../app/providers.dart';
import '../../design/ledger_scaffold.dart';
import '../../design/office_button.dart';
import '../../design/tokens.dart';
import '../settings/office_rules_screen.dart';

/// State at a glance. One primary action, no encouragement.
class FrontDeskScreen extends ConsumerStatefulWidget {
  const FrontDeskScreen({super.key});

  @override
  ConsumerState<FrontDeskScreen> createState() => _FrontDeskScreenState();
}

class _FrontDeskScreenState extends ConsumerState<FrontDeskScreen>
    with WidgetsBindingObserver {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // One second is enough for a countdown displayed to the minute, and cheap.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // NFR-2 — reconcile toward more restriction whenever we come back.
    if (state == AppLifecycleState.resumed) {
      ref.read(officeProvider.notifier).reconcile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider).valueOrNull;
    final quota = ref.watch(quotaStateProvider);
    final streak = ref.watch(streakProvider);
    final insights = ref.watch(insightsProvider);
    final clock = ref.watch(clockProvider);

    if (office == null || quota == null) {
      return const LedgerScaffold(
        title: 'Front desk',
        body: Text('Opening…', style: TextStyles.bodyText),
      );
    }

    final permit = office.activePermit;
    final status = permit?.status(clock);
    final attemptsToday = office.events
        .where((e) =>
            e.kind == EventKind.attemptBlocked && quota.day.contains(e.at))
        .length;

    return LedgerScaffold(
      eyebrow: 'Permit office',
      title: 'Front desk',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null && status.active)
            _ActivePermit(remaining: status.remaining)
          else
            _TimeNotSpent(attempts: attemptsToday),

          const SizedBox(height: Space.xl),
          const Hairline(),
          const SizedBox(height: Space.sm),

          LedgerRow(
            label: 'Blocked attempts today',
            value: '$attemptsToday',
          ),
          LedgerRow(
            label: 'Permits remaining',
            value: '${quota.remaining} of ${quota.permitsPerDay}',
            valueColor: quota.exhausted ? Palette.stamp : Palette.ink,
          ),
          LedgerRow(
            label: 'Next issue',
            value: _clockTime(quota.resetsAt),
          ),
          if (insights != null)
            LedgerRow(
              label: 'Permits issued, all time',
              value: '${insights.totalPermits}',
            ),

          const SizedBox(height: Space.lg),
          Text('CLEAN DAYS', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          if (streak != null) _StreakStamps(streak: streak),

          const SizedBox(height: Space.xxl),
          if (!office.rules.enforcementEnabled)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Text(
                'Nothing is being blocked. Open Office rules to start.',
                style: TextStyles.caption.copyWith(color: Palette.stamp),
              ),
            ),
          // Deliberately quiet and at the bottom: §6 asks the Front Desk for one primary
          // action, and settings is never it.
          OfficeButton(
            label: 'Office rules',
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                pageBuilder: (context, _, _) => const OfficeRulesScreen(),
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
        ],
      ),
      footer: status != null && status.active
          ? OfficeButton(
              label: 'Return early',
              weight: ButtonWeight.primary,
              onPressed: () =>
                  ref.read(officeProvider.notifier).surrenderPermit(),
              semanticHint:
                  'Gives up the rest of this permit. The time is not refunded.',
            )
          : null,
    );
  }

  static String _clockTime(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

class _ActivePermit extends StatelessWidget {
  const _ActivePermit({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    final warning = remaining <= const Duration(minutes: 2);

    return Semantics(
      liveRegion: true,
      label: 'Permit active, ${remaining.inMinutes} minutes remaining',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PERMIT ISSUED', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$minutes:$seconds',
              style: TextStyles.numeral.copyWith(
                color: warning ? Palette.stamp : Palette.seal,
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Text('remaining', style: TextStyles.caption),
        ],
      ),
    );
  }
}

/// The headline number when nothing is running. Facts, not praise — §6 is explicit that
/// the Record does not congratulate, and the Front Desk holds the same line.
class _TimeNotSpent extends StatelessWidget {
  const _TimeNotSpent({required this.attempts});

  final int attempts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('NO PERMIT IN FORCE', style: TextStyles.eyebrow),
        const SizedBox(height: Space.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            attempts.toString().padLeft(2, '0'),
            style: TextStyles.numeral,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          attempts == 1 ? 'attempt turned away today' : 'attempts turned away today',
          style: TextStyles.caption,
        ),
      ],
    );
  }
}

/// A row of stamps, one per clean day, capped so the row stays a row.
class _StreakStamps extends StatelessWidget {
  const _StreakStamps({required this.streak});

  final StreakSummary streak;

  static const int _maxStamps = 14;

  @override
  Widget build(BuildContext context) {
    final shown = streak.current.clamp(0, _maxStamps);

    return Semantics(
      label: 'Current streak ${streak.current} clean days, '
          'longest ${streak.longest}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (var i = 0; i < shown; i++)
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    border: Border.all(color: Palette.seal, width: Stroke.hairline),
                    borderRadius: Stroke.corner,
                    color: Palette.seal,
                  ),
                ),
              if (streak.current > _maxStamps)
                Text('+${streak.current - _maxStamps}', style: TextStyles.mono),
              if (streak.current == 0)
                Text('None today', style: TextStyles.caption),
            ],
          ),
          const SizedBox(height: Space.sm),
          LedgerRow(label: 'Longest run', value: '${streak.longest} days'),
        ],
      ),
    );
  }
}
