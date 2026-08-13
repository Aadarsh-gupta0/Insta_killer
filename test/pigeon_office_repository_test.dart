import 'package:flutter_test/flutter_test.dart';
import 'package:insta_killer/platform/office_api.g.dart';
import 'package:insta_killer/platform/pigeon_office_repository.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

/// Stands in for Kotlin. Stores blobs in a map, exactly as SharedPreferences does, and
/// records the grant calls so the tests can assert on the one thing the native side
/// actually acts on.
class FakeHost extends OfficeHostApi {
  final Map<String, String> blobs = {};
  final List<int> grantsBegun = [];
  int grantsEnded = 0;

  @override
  Future<String?> read(String key) async => blobs[key];

  @override
  Future<void> write(String key, String value) async => blobs[key] = value;

  @override
  Future<void> beginGrant(int endsAtEpochMs) async =>
      grantsBegun.add(endsAtEpochMs);

  @override
  Future<void> endGrant() async => grantsEnded++;
}

void main() {
  late FakeHost host;
  late PigeonOfficeRepository repo;

  setUp(() {
    host = FakeHost();
    repo = PigeonOfficeRepository(host: host);
  });

  group('rules', () {
    test('round-trip through JSON', () async {
      final rules = OfficeRules(
        quota: const QuotaPolicy(
          permitsPerDay: 5,
          boundary: DayBoundary(hour: 4, minute: 30),
        ),
        schedule: WeeklySchedule.daily(startHour: 23, endHour: 2),
        strictMode: false,
        grantDuration: const Duration(minutes: 20),
        blockedAppCount: 2,
      );

      await repo.saveRules(rules);
      final restored = await repo.loadRules();

      expect(restored.quota.permitsPerDay, 5);
      expect(restored.quota.boundary, const DayBoundary(hour: 4, minute: 30));
      expect(restored.schedule, rules.schedule);
      expect(restored.strictMode, isFalse);
      expect(restored.grantDuration, const Duration(minutes: 20));
      expect(restored.blockedAppCount, 2);
    });

    test('an empty store yields the strict defaults', () async {
      final rules = await repo.loadRules();
      expect(rules.quota.permitsPerDay, 3);
      expect(rules.strictMode, isTrue);
      expect(rules.grantDuration, const Duration(minutes: 15));
    });

    test('corrupt JSON falls back to the defaults rather than throwing', () async {
      host.blobs['rules'] = '{not json at all';

      final rules = await repo.loadRules();
      expect(rules.strictMode, isTrue,
          reason: 'failing open would mean nothing is blocked');
      expect(rules.quota.permitsPerDay, 3);
    });

    test('a partial record keeps the strict default for missing fields',
        () async {
      // What an older build's data looks like after a field is added.
      host.blobs['rules'] = '{"quota":{"permitsPerDay":9,"boundary":{"hour":6,"minute":0}}}';

      final rules = await repo.loadRules();
      expect(rules.quota.permitsPerDay, 9);
      expect(rules.strictMode, isTrue);
      expect(rules.grantDuration, const Duration(minutes: 15));
    });
  });

  group('the event log', () {
    test('appends and reloads in order', () async {
      await repo.append(
          Event(at: DateTime(2026, 8, 12, 9), kind: EventKind.attemptBlocked));
      await repo.append(Event(
        at: DateTime(2026, 8, 12, 10),
        kind: EventKind.permitIssued,
        permitId: 'p-1',
        reason: 'checking the group chat',
      ));

      final events = await repo.loadEvents();
      expect(events, hasLength(2));
      expect(events.first.kind, EventKind.attemptBlocked);
      expect(events.last.permitId, 'p-1');
      expect(events.last.reason, 'checking the group chat');
    });

    test('preserves instants across the JSON boundary', () async {
      final at = DateTime(2026, 8, 12, 23, 47, 13);
      await repo.append(Event(at: at, kind: EventKind.attemptBlocked));

      final restored = (await repo.loadEvents()).single;
      expect(restored.at.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
    });

    test('a corrupt log reads as empty rather than crashing the app', () async {
      host.blobs['events'] = 'garbage';
      expect(await repo.loadEvents(), isEmpty);
    });
  });

  group('permits and the native grant', () {
    final issuedAt = DateTime(2026, 8, 12, 14);

    Permit permit() => Permit(
          id: 'p-1',
          issued: ClockStamp(wall: issuedAt, monotonic: const Duration(hours: 3)),
          duration: const Duration(minutes: 15),
          reason: 'checking the group chat',
        );

    test('issuing writes the permit and hands native a deadline', () async {
      await repo.setActivePermit(permit());

      expect(
        host.grantsBegun.single,
        issuedAt.add(const Duration(minutes: 15)).millisecondsSinceEpoch,
        reason: 'the watcher only understands a wall-clock deadline',
      );

      final restored = await repo.loadActivePermit();
      expect(restored!.id, 'p-1');
      expect(restored.duration, const Duration(minutes: 15));
      expect(restored.issued.monotonic, const Duration(hours: 3),
          reason: 'the monotonic reading must survive, or FR-20 cannot work');
    });

    test('clearing ends the grant natively', () async {
      await repo.setActivePermit(permit());
      await repo.setActivePermit(null);

      expect(host.grantsEnded, 1);
      expect(await repo.loadActivePermit(), isNull);
    });

    test('no permit reads as null, not as an error', () async {
      expect(await repo.loadActivePermit(), isNull);
      host.blobs['permit'] = '';
      expect(await repo.loadActivePermit(), isNull);
      host.blobs['permit'] = 'corrupt';
      expect(await repo.loadActivePermit(), isNull);
    });
  });

  group('declaration and clock mark', () {
    test('declaration round-trips, and blank reads as absent', () async {
      expect(await repo.loadDeclaration(), isNull);

      await repo.saveDeclaration('I want my evenings back.');
      expect(await repo.loadDeclaration(), 'I want my evenings back.');

      await repo.saveDeclaration('');
      expect(await repo.loadDeclaration(), isNull);
    });

    test('the clock high-water mark survives to the millisecond', () async {
      final mark = DateTime(2026, 8, 12, 14, 30, 15, 250);
      await repo.saveClockHighWaterMark(mark);

      final restored = await repo.loadClockHighWaterMark();
      expect(restored!.millisecondsSinceEpoch, mark.millisecondsSinceEpoch);
    });

    test('a corrupt mark reads as absent', () async {
      host.blobs['clock.mark'] = 'not-a-number';
      expect(await repo.loadClockHighWaterMark(), isNull);
    });
  });
}
