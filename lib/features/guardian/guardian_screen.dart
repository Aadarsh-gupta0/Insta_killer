import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

import '../../app/providers.dart';
import '../../data/guardian_codes.dart';
import '../../design/ledger_scaffold.dart';
import '../../design/office_button.dart';
import '../../design/tokens.dart';

/// FR-27 — the Guardian, both halves of it.
///
/// One screen serves two people. On your phone it pairs a Guardian and carries the
/// challenge you have to get answered. On theirs, the last section turns a challenge into
/// the response — that is all their side ever does, and it needs no account, no server and
/// no notification.
class GuardianScreen extends ConsumerStatefulWidget {
  const GuardianScreen({super.key});

  @override
  ConsumerState<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends ConsumerState<GuardianScreen> {
  final _name = TextEditingController();
  final _response = TextEditingController();
  final _theirSecret = TextEditingController();
  final _theirChallenge = TextEditingController();

  /// Generated once per visit, not per rebuild — a secret that changes while the other
  /// person is copying it is unpairable.
  late final String _offeredSecret = generateGuardianSecret();

  String? _notice;
  String? _error;
  String? _computed;

  /// Set once the owner has sent the secret and asked for proof. Until the Guardian
  /// answers this, nothing is paired.
  ApprovalRequest? _pairingChallenge;
  final _pairingAnswer = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _response.dispose();
    _theirSecret.dispose();
    _theirChallenge.dispose();
    _pairingAnswer.dispose();
    super.dispose();
  }

  /// Step one: ask them to prove they have it.
  void _askForProof() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the Guardian a name first.');
      return;
    }
    setState(() {
      _error = null;
      _pairingChallenge = ref.read(officeProvider.notifier).pairingChallenge();
    });
  }

  /// Step two: pair only if their phone answered correctly.
  Future<void> _confirmPairing() async {
    final challenge = _pairingChallenge;
    if (challenge == null) return;

    final ok = ref.read(officeProvider.notifier).verifyPairing(
          request: challenge,
          secret: _offeredSecret,
          response: _pairingAnswer.text,
        );

    if (!ok) {
      setState(() => _error =
          'That does not match. Either they have not set up the app yet, or '
          'the code did not arrive intact.');
      return;
    }

    await ref
        .read(officeProvider.notifier)
        .pairGuardian(name: _name.text, secret: _offeredSecret);
    if (mounted) {
      setState(() {
        _error = null;
        _pairingChallenge = null;
        _pairingAnswer.clear();
        _notice = 'Paired, and confirmed on their phone. '
            'Loosening now needs their agreement.';
      });
    }
  }

  Future<void> _submit() async {
    final verdict =
        await ref.read(officeProvider.notifier).submitApproval(_response.text);
    if (!mounted) return;

    setState(() {
      _notice = null;
      _error = null;
      switch (verdict) {
        case ApprovalVerdict.accepted:
          _notice = 'Approved. The change applies when its wait is up.';
          _response.clear();
        case ApprovalVerdict.wrongCode:
          _error = 'That code does not match. Check they read the right one.';
        case ApprovalVerdict.staleRequest:
          _error = 'That code was for a different request.';
        case ApprovalVerdict.expired:
          _error = 'That challenge has expired. Ask for a new one.';
      }
    });
  }

  void _answer() {
    final answer = ref
        .read(officeProvider.notifier)
        .answerChallenge(_theirChallenge.text, _theirSecret.text);

    setState(() {
      _computed = answer;
      _error = answer == null ? 'A challenge is six digits.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider).valueOrNull;
    if (office == null) {
      return const LedgerScaffold(
        title: 'Guardian',
        body: Text('Opening…', style: TextStyles.bodyText),
      );
    }

    return LedgerScaffold(
      eyebrow: 'Permit office',
      title: 'Guardian',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_notice case final String notice) ...[
            Text(notice, style: TextStyles.mono.copyWith(color: Palette.seal)),
            const SizedBox(height: Space.md),
          ],
          if (_error case final String error) ...[
            Text(error, style: TextStyles.mono.copyWith(color: Palette.stamp)),
            const SizedBox(height: Space.md),
          ],

          if (office.guardian case final GuardianPairing guardian)
            _PairedBlock(guardian: guardian)
          else
            _PairBlock(
              name: _name,
              secret: _offeredSecret,
              challenge: _pairingChallenge,
              answer: _pairingAnswer,
              onAskForProof: _askForProof,
              onConfirm: _confirmPairing,
            ),

          if (office.guardianPaired &&
              office.pendingChange != null) ...[
            const SizedBox(height: Space.xl),
            _ApprovalBlock(
              pending: office.pendingChange!,
              request: office.approvalRequest,
              approved: office.approvalGranted,
              response: _response,
              onRaise: () => ref.read(officeProvider.notifier).requestApproval(),
              onSubmit: _submit,
            ),
          ],

          const SizedBox(height: Space.xxl),
          const Hairline(),
          const SizedBox(height: Space.md),

          // Hidden once this phone has a Guardian of its own. Leaving it visible would
          // let the owner paste their own shared code in and answer their own challenges
          // without leaving the app — no rooting, no cleverness, just scrolling down.
          // The secret is still on the device, so this is friction rather than proof, but
          // it removes the one-tap version of the bypass.
          if (office.guardianPaired)
            const _GuardianModeHidden()
          else
            _GuardianModeBlock(
              secret: _theirSecret,
              challenge: _theirChallenge,
              computed: _computed,
              onAnswer: _answer,
            ),
          const SizedBox(height: Space.xxl),
        ],
      ),
    );
  }
}

/// A code, shown big and copyable.
///
/// Copy rather than text selection because `SelectableText` and `SelectionArea` both come
/// from Material, which this app deliberately does not import — and because these codes
/// exist to be *sent* to someone, so one tap to the clipboard beats a drag-select.
class CodeBlock extends StatefulWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.size = 24,
    this.colour,
    this.boxed = false,
  });

  final String code;
  final double size;
  final Color? colour;
  final bool boxed;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.code,
      style: TextStyles.numeral
          .copyWith(fontSize: widget.size, color: widget.colour),
      textAlign: TextAlign.center,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.boxed)
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              border: Border.all(color: Palette.ink, width: Stroke.heavy),
              borderRadius: Stroke.corner,
            ),
            child: text,
          )
        else
          text,
        const SizedBox(height: Space.sm),
        OfficeButton(
          label: _copied ? 'Copied' : 'Copy',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.code));
            if (mounted) setState(() => _copied = true);
          },
        ),
      ],
    );
  }
}

/// Shown in place of the Guardian half once this phone is the one being guarded.
class _GuardianModeHidden extends StatelessWidget {
  const _GuardianModeHidden();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('I AM THE GUARDIAN', style: TextStyles.eyebrow),
        const SizedBox(height: Space.sm),
        Text(
          'Not available on this phone. It has a Guardian of its own, and '
          'answering your own challenges here would make that meaningless.',
          style: TextStyles.caption,
        ),
      ],
    );
  }
}

class _PairBlock extends StatelessWidget {
  const _PairBlock({
    required this.name,
    required this.secret,
    required this.challenge,
    required this.answer,
    required this.onAskForProof,
    required this.onConfirm,
  });

  final TextEditingController name;
  final String secret;
  final ApprovalRequest? challenge;
  final TextEditingController answer;
  final VoidCallback onAskForProof;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('NO GUARDIAN', style: TextStyles.eyebrow),
        const SizedBox(height: Space.sm),
        Text(
          'A Guardian is someone who has to agree before any rule here gets '
          'looser. They do not need an account and nothing is sent anywhere — '
          'you both hold one code, and they answer with another.',
          style: TextStyles.bodyText,
        ),
        const SizedBox(height: Space.lg),

        Text('THEIR NAME', style: TextStyles.eyebrow),
        const SizedBox(height: Space.sm),
        OfficeField(
          controller: name,
          hint: 'So the app can say whose agreement it is waiting on',
          maxLines: 1,
        ),
        const SizedBox(height: Space.lg),

        Text('THE SHARED CODE', style: TextStyles.eyebrow),
        const SizedBox(height: Space.sm),
        CodeBlock(code: secret, size: 18, boxed: true),
        const SizedBox(height: Space.sm),
        Text(
          'Send this to them once, however you normally talk. They enter it '
          'under "I am the Guardian" on their own phone. Then delete your copy '
          '— if you keep it, you can answer your own requests, and the '
          'Guardian becomes decoration.',
          style: TextStyles.caption,
        ),
        const SizedBox(height: Space.md),

        if (challenge == null)
          OfficeButton(
            label: 'They have it — check',
            weight: ButtonWeight.primary,
            onPressed: onAskForProof,
          )
        else ...[
          const SizedBox(height: Space.lg),
          const Hairline(),
          const SizedBox(height: Space.lg),
          Text('PROVE IT REACHED THEM', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          Text(
            'Nothing is paired yet. Send them these six digits — their phone '
            'turns them into an answer only it can work out. If it comes back '
            'right, the app knows their side is real.',
            style: TextStyles.bodyText,
          ),
          const SizedBox(height: Space.md),
          CodeBlock(code: challenge!.challenge, size: 36),
          const SizedBox(height: Space.md),
          Text('THEIR ANSWER', style: TextStyles.eyebrow),
          const SizedBox(height: Space.sm),
          OfficeField(
            controller: answer,
            hint: 'Six digits from their phone',
            maxLines: 1,
          ),
          const SizedBox(height: Space.md),
          OfficeButton(
            label: 'Confirm the pairing',
            weight: ButtonWeight.primary,
            onPressed: onConfirm,
          ),
        ],
      ],
    );
  }
}

class _PairedBlock extends StatelessWidget {
  const _PairedBlock({required this.guardian});

  final GuardianPairing guardian;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GUARDIAN', style: TextStyles.eyebrow),
        const SizedBox(height: Space.sm),
        LedgerRow(label: 'Name', value: guardian.name),
        LedgerRow(
          label: 'Paired',
          value: '${guardian.pairedAt.day}/${guardian.pairedAt.month}/'
              '${guardian.pairedAt.year}',
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Every loosening now waits out its cooldown *and* needs their code. '
          'Removing them is itself a loosening — if they never answer, it goes '
          'through on its own after seven days, so a Guardian who disappears '
          'cannot lock you out permanently.',
          style: TextStyles.caption,
        ),
      ],
    );
  }
}

/// The challenge, and the box for what comes back.
class _ApprovalBlock extends StatelessWidget {
  const _ApprovalBlock({
    required this.pending,
    required this.request,
    required this.approved,
    required this.response,
    required this.onRaise,
    required this.onSubmit,
  });

  final PendingChange pending;
  final ApprovalRequest? request;
  final bool approved;
  final TextEditingController response;
  final VoidCallback onRaise;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        border: Border.all(
          color: approved ? Palette.seal : Palette.stamp,
          width: Stroke.heavy,
        ),
        borderRadius: Stroke.corner,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            approved ? 'APPROVED' : 'AWAITING THE GUARDIAN',
            style: TextStyles.eyebrow
                .copyWith(color: approved ? Palette.seal : Palette.stamp),
          ),
          const SizedBox(height: Space.sm),
          Text(pending.description, style: TextStyles.bodyStrong),

          if (approved) ...[
            const SizedBox(height: Space.sm),
            Text(
              'Agreed. It still waits out the rest of its cooldown.',
              style: TextStyles.caption,
            ),
          ] else if (request == null) ...[
            const SizedBox(height: Space.md),
            OfficeButton(
              label: 'Get a challenge',
              weight: ButtonWeight.primary,
              onPressed: onRaise,
            ),
          ] else ...[
            const SizedBox(height: Space.md),
            Text('READ THEM THIS', style: TextStyles.eyebrow),
            const SizedBox(height: Space.xs),
            CodeBlock(code: request!.challenge, size: 36),
            const SizedBox(height: Space.md),
            Text('THEIR ANSWER', style: TextStyles.eyebrow),
            const SizedBox(height: Space.sm),
            OfficeField(
              controller: response,
              hint: 'Six digits from their phone',
              maxLines: 1,
            ),
            const SizedBox(height: Space.md),
            OfficeButton(
              label: 'Submit',
              weight: ButtonWeight.primary,
              onPressed: onSubmit,
            ),
          ],
        ],
      ),
    );
  }
}

/// The Guardian's half. On their phone this is the only section that matters.
class _GuardianModeBlock extends StatelessWidget {
  const _GuardianModeBlock({
    required this.secret,
    required this.challenge,
    required this.computed,
    required this.onAnswer,
  });

  final TextEditingController secret;
  final TextEditingController challenge;
  final String? computed;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('I AM THE GUARDIAN', style: TextStyles.eyebrow),
        const SizedBox(height: Space.sm),
        Text(
          'If someone has asked you to hold their code, put it here. When they '
          'send you six digits, type those in and read back what appears.',
          style: TextStyles.bodyText,
        ),
        const SizedBox(height: Space.lg),

        Text('THEIR SHARED CODE', style: TextStyles.eyebrow),
        const SizedBox(height: Space.sm),
        OfficeField(
          controller: secret,
          hint: 'The code they sent you when you paired',
          maxLines: 1,
        ),
        const SizedBox(height: Space.lg),

        Text('THE CHALLENGE THEY SENT', style: TextStyles.eyebrow),
        const SizedBox(height: Space.sm),
        OfficeField(controller: challenge, hint: 'Six digits', maxLines: 1),
        const SizedBox(height: Space.md),
        OfficeButton(label: 'Work out the answer', onPressed: onAnswer),

        if (computed case final String answer) ...[
          const SizedBox(height: Space.lg),
          Text('READ THIS BACK', style: TextStyles.eyebrow),
          const SizedBox(height: Space.xs),
          CodeBlock(code: answer, size: 36, colour: Palette.seal),
          const SizedBox(height: Space.sm),
          Text(
            'Only do this if you are willing for them to have what they asked '
            'for. Saying no is simply not answering.',
            style: TextStyles.caption,
          ),
        ],
      ],
    );
  }
}
