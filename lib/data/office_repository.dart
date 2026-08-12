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
  })  : _rules = rules ?? const OfficeRules(),
        _events = [...?events] {
    _activePermit = activePermit;
    _declaration = declaration;
  }

  OfficeRules _rules;
  final List<Event> _events;
  Permit? _activePermit;
  DateTime? _highWaterMark;
  String? _declaration;

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
}
