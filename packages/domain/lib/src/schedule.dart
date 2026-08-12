/// Recurring always-blocked windows (FR-23).
///
/// The grid is 15 minutes per cell, 96 cells a day, 672 a week. That granularity is not
/// a UI choice — it is iOS's `DeviceActivity` floor showing through, and the Hours screen
/// paints cells that *are* 15 minutes so the constraint is visible rather than explained.
library;

const int minutesPerCell = 15;
const int cellsPerDay = 24 * 60 ~/ minutesPerCell; // 96
const int cellsPerWeek = cellsPerDay * 7; // 672

/// A weekly repeating set of blocked quarter-hours.
///
/// Windows crossing midnight need no special handling: they are simply cells at the end
/// of one day and the start of the next.
class WeeklySchedule {
  WeeklySchedule(Iterable<int> blockedCells)
      : _cells = Set.unmodifiable(blockedCells.map(_requireValid));

  WeeklySchedule.empty() : _cells = const {};

  /// Every day, between two times of day. [endHour]:[endMinute] is exclusive.
  factory WeeklySchedule.daily({
    required int startHour,
    int startMinute = 0,
    required int endHour,
    int endMinute = 0,
  }) {
    final cells = <int>{};
    for (var day = 0; day < 7; day++) {
      cells.addAll(_rangeForDay(day, startHour, startMinute, endHour, endMinute));
    }
    return WeeklySchedule(cells);
  }

  final Set<int> _cells;

  Set<int> get blockedCells => _cells;

  bool get isEmpty => _cells.isEmpty;

  int get blockedMinutesPerWeek => _cells.length * minutesPerCell;

  /// Absolute cell index for an instant. Monday 00:00 is 0.
  static int cellFor(DateTime instant) {
    final dayIndex = instant.weekday - 1; // DateTime.monday == 1
    final minuteOfDay = instant.hour * 60 + instant.minute;
    return dayIndex * cellsPerDay + minuteOfDay ~/ minutesPerCell;
  }

  bool isBlockedAt(DateTime instant) => _cells.contains(cellFor(instant));

  /// When the current blocked run ends, or null if [instant] is not blocked.
  ///
  /// FR-17 and NFR-4 both require a refusal to name the next possible time, so this has
  /// to walk forward through contiguous cells rather than just reporting the current
  /// cell's end. Bounded at one week — a fully blocked schedule has no end, and the
  /// caller must say so rather than loop.
  DateTime? blockedUntil(DateTime instant) {
    if (!isBlockedAt(instant)) return null;
    if (_cells.length == cellsPerWeek) return null; // blocked forever

    final startCell = cellFor(instant);
    var steps = 0;
    var cursor = _cellStart(instant);
    var cell = startCell;

    while (_cells.contains(cell) && steps < cellsPerWeek) {
      cursor = cursor.add(const Duration(minutes: minutesPerCell));
      cell = (cell + 1) % cellsPerWeek;
      steps++;
    }
    return cursor;
  }

  WeeklySchedule withCells(Iterable<int> cells) =>
      WeeklySchedule({..._cells, ...cells});

  WeeklySchedule withoutCells(Iterable<int> cells) =>
      WeeklySchedule(_cells.where((c) => !cells.contains(c)));

  List<int> toJson() => _cells.toList()..sort();

  static WeeklySchedule fromJson(List<Object?> json) =>
      WeeklySchedule(json.cast<int>());

  static int _requireValid(int cell) {
    if (cell < 0 || cell >= cellsPerWeek) {
      throw ArgumentError.value(cell, 'cell', 'must be 0..${cellsPerWeek - 1}');
    }
    return cell;
  }

  static Iterable<int> _rangeForDay(
    int dayIndex,
    int startHour,
    int startMinute,
    int endHour,
    int endMinute,
  ) {
    final start = (startHour * 60 + startMinute) ~/ minutesPerCell;
    final end = (endHour * 60 + endMinute) ~/ minutesPerCell;
    final base = dayIndex * cellsPerDay;

    if (start <= end) {
      return [for (var i = start; i < end; i++) base + i];
    }
    // Crosses midnight: to the end of this day, then into the next.
    final nextBase = ((dayIndex + 1) % 7) * cellsPerDay;
    return [
      for (var i = start; i < cellsPerDay; i++) base + i,
      for (var i = 0; i < end; i++) nextBase + i,
    ];
  }

  static DateTime _cellStart(DateTime instant) {
    final minuteOfDay = instant.hour * 60 + instant.minute;
    final flooredMinute = (minuteOfDay ~/ minutesPerCell) * minutesPerCell;
    return DateTime(
      instant.year,
      instant.month,
      instant.day,
      flooredMinute ~/ 60,
      flooredMinute % 60,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WeeklySchedule &&
      other._cells.length == _cells.length &&
      other._cells.containsAll(_cells);

  @override
  int get hashCode => Object.hashAllUnordered(_cells);
}
