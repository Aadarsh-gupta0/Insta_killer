import 'dart:convert';

import 'package:insta_killer_domain/insta_killer_domain.dart';

import '../data/office_repository.dart';
import 'office_api.g.dart';

/// The real repository: Dart owns the schema, Android owns the file.
///
/// Everything except the active permit is stored as JSON that Kotlin never parses. That
/// is what keeps the rules in one language — a native service physically cannot make a
/// quota decision if it cannot read the quota.
///
/// The active permit is the exception, and only half an exception: the [Permit] itself is
/// JSON like everything else, but issuing one also writes a plain timestamp that
/// `ForegroundWatcher` compares against. That timestamp is the entire native contract.
class PigeonOfficeRepository implements OfficeRepository {
  PigeonOfficeRepository({OfficeHostApi? host})
      : _host = host ?? OfficeHostApi();

  final OfficeHostApi _host;

  static const _rulesKey = 'rules';
  static const _eventsKey = 'events';
  static const _permitKey = 'permit';
  static const _markKey = 'clock.mark';
  static const _declarationKey = 'declaration';

  @override
  Future<OfficeRules> loadRules() async {
    final raw = await _host.read(_rulesKey);
    if (raw == null) return const OfficeRules();
    try {
      return OfficeRules.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      // Corrupt settings resolve to the defaults, which are the strict ones. Throwing
      // here would leave the app with no rules, and no rules means nothing is blocked.
      return const OfficeRules();
    }
  }

  @override
  Future<void> saveRules(OfficeRules rules) =>
      _host.write(_rulesKey, jsonEncode(rules.toJson()));

  @override
  Future<List<Event>> loadEvents() async {
    final raw = await _host.read(_eventsKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List<Object?>)
          .map((e) => Event.fromJson((e! as Map).cast<String, Object?>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// FR-29 — append-only.
  ///
  /// Read-modify-write, which is safe here only because Dart is the sole writer: the
  /// services record nothing but their own heartbeat. If a service ever needs to append,
  /// this has to become a real store rather than a JSON blob (D-001's reasoning, which
  /// applies the moment there are two writers).
  @override
  Future<void> append(Event event) async {
    final events = await loadEvents();
    await _host.write(
      _eventsKey,
      jsonEncode([...events, event].map((e) => e.toJson()).toList()),
    );
  }

  @override
  Future<Permit?> loadActivePermit() async {
    final raw = await _host.read(_permitKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Permit.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setActivePermit(Permit? permit) async {
    if (permit == null) {
      await _host.write(_permitKey, '');
      await _host.endGrant();
      return;
    }

    await _host.write(_permitKey, jsonEncode(permit.toJson()));
    // The watcher only understands a deadline. Note this is the *wall-clock* end: the
    // monotonic reading stays in the permit for FR-20, and a user who rolls the clock
    // back to extend a permit gets the block back early rather than late, because the
    // domain's status() resolves toward the stricter reading on the next foreground.
    await _host.beginGrant(permit.nominalEnd.millisecondsSinceEpoch);
  }

  @override
  Future<DateTime?> loadClockHighWaterMark() async {
    final raw = await _host.read(_markKey);
    final ms = int.tryParse(raw ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> saveClockHighWaterMark(DateTime mark) =>
      _host.write(_markKey, mark.millisecondsSinceEpoch.toString());

  @override
  Future<String?> loadDeclaration() async {
    final raw = await _host.read(_declarationKey);
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  @override
  Future<void> saveDeclaration(String text) =>
      _host.write(_declarationKey, text);
}
