import 'package:insta_killer_domain/insta_killer_domain.dart';

/// Everything the app needs to persist, behind one seam.
///
/// The Android implementation writes through a Pigeon channel into native
/// `SharedPreferences`, because the enforcement services have to read the same values
/// from a process where no Flutter engine is running (D-002's discipline, applied to
/// Android). Keeping that behind an interface means the screens and their tests never
/// touch a platform channel.
abstract interface class OfficeRepository {
  Future<OfficeRules> loadRules();

  Future<void> saveRules(OfficeRules rules);

  /// FR-29 — append-only. There is deliberately no delete.
  Future<List<Event>> loadEvents();

  Future<void> append(Event event);

  Future<Permit?> loadActivePermit();

  Future<void> setActivePermit(Permit? permit);

  /// The wall-clock high-water mark backing [ClockGuard] (FR-20). Persisted because the
  /// whole point is to survive a restart.
  Future<DateTime?> loadClockHighWaterMark();

  Future<void> saveClockHighWaterMark(DateTime mark);

  /// FR-24 — the declaration written during onboarding, reused verbatim as the block
  /// screen's subtitle (FR-8) and shown back to the user at the Gate.
  Future<String?> loadDeclaration();

  Future<void> saveDeclaration(String text);

  /// FR-25 — a loosening waiting out its cooldown. At most one at a time: a queue of
  /// them would let the user stack up an escape and forget which one lands when.
  Future<PendingChange?> loadPendingChange();

  Future<void> savePendingChange(PendingChange? change);

  /// The drawn half of FR-24, as encoded strokes. Ceremony, not evidence — nothing
  /// verifies it, and nothing should imply that it does.
  Future<String?> loadSignature();

  Future<void> saveSignature(String encoded);

  /// FR-27 — the Guardian's shared secret.
  ///
  /// Stored on its own, never inside the rules blob: the rules get serialised into the
  /// event log and passed around inside PendingChange objects, and a secret should not
  /// travel wherever those go.
  Future<String?> loadGuardianSecret();

  Future<void> saveGuardianSecret(String? secret);

  Future<GuardianPairing?> loadGuardianPairing();

  Future<void> saveGuardianPairing(GuardianPairing? pairing);

  /// The outstanding "please agree to this", if one has been raised.
  Future<ApprovalRequest?> loadApprovalRequest();

  Future<void> saveApprovalRequest(ApprovalRequest? request);

  /// Whether the Guardian has agreed to the queued change. Cleared whenever the queued
  /// change is replaced, so agreement never carries over to a different request.
  Future<bool> loadApprovalGranted();

  Future<void> saveApprovalGranted(bool granted);
}

/// In-memory, for tests and for running the UI before the platform layer lands.
///
/// Not a stub with empty methods — it behaves correctly, so a test that passes against
/// it is testing the screen rather than the fake.
class InMemoryOfficeRepository implements OfficeRepository {
  InMemoryOfficeRepository({
    OfficeRules? rules,
    List<Event>? events,
    Permit? activePermit,
    String? declaration,
    PendingChange? pendingChange,
    String? guardianSecret,
    GuardianPairing? guardianPairing,
    ApprovalRequest? approvalRequest,
    bool approvalGranted = false,
  })  : _rules = rules ?? const OfficeRules(),
        _events = [...?events] {
    _activePermit = activePermit;
    _declaration = declaration;
    _pending = pendingChange;
    _guardianSecret = guardianSecret;
    _pairing = guardianPairing;
    _approvalRequest = approvalRequest;
    _approvalGranted = approvalGranted;
  }

  OfficeRules _rules;
  final List<Event> _events;
  Permit? _activePermit;
  DateTime? _highWaterMark;
  String? _declaration;
  PendingChange? _pending;
  String? _signature;
  String? _guardianSecret;
  GuardianPairing? _pairing;
  ApprovalRequest? _approvalRequest;
  bool _approvalGranted = false;

  @override
  Future<OfficeRules> loadRules() async => _rules;

  @override
  Future<void> saveRules(OfficeRules rules) async => _rules = rules;

  @override
  Future<List<Event>> loadEvents() async => List.unmodifiable(_events);

  @override
  Future<void> append(Event event) async => _events.add(event);

  @override
  Future<Permit?> loadActivePermit() async => _activePermit;

  @override
  Future<void> setActivePermit(Permit? permit) async => _activePermit = permit;

  @override
  Future<DateTime?> loadClockHighWaterMark() async => _highWaterMark;

  @override
  Future<void> saveClockHighWaterMark(DateTime mark) async =>
      _highWaterMark = mark;

  @override
  Future<String?> loadDeclaration() async => _declaration;

  @override
  Future<void> saveDeclaration(String text) async => _declaration = text;

  @override
  Future<PendingChange?> loadPendingChange() async => _pending;

  @override
  Future<void> savePendingChange(PendingChange? change) async =>
      _pending = change;

  @override
  Future<String?> loadSignature() async => _signature;

  @override
  Future<void> saveSignature(String encoded) async => _signature = encoded;

  @override
  Future<String?> loadGuardianSecret() async => _guardianSecret;

  @override
  Future<void> saveGuardianSecret(String? secret) async =>
      _guardianSecret = secret;

  @override
  Future<GuardianPairing?> loadGuardianPairing() async => _pairing;

  @override
  Future<void> saveGuardianPairing(GuardianPairing? pairing) async =>
      _pairing = pairing;

  @override
  Future<ApprovalRequest?> loadApprovalRequest() async => _approvalRequest;

  @override
  Future<void> saveApprovalRequest(ApprovalRequest? request) async =>
      _approvalRequest = request;

  @override
  Future<bool> loadApprovalGranted() async => _approvalGranted;

  @override
  Future<void> saveApprovalGranted(bool granted) async =>
      _approvalGranted = granted;
}
