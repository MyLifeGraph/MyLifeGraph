enum DashboardAppointmentStatus {
  notApplicable,
  open,
  completed,
  fullyRated,
}

enum DashboardFullWeekItemKind { setupCommitment, preparation }

class DashboardFullWeekProjection {
  DashboardFullWeekProjection({
    required this.displayedLocalDate,
    required this.weekStartsOn,
    required List<DashboardFullWeekDay> days,
    this.commitmentLoadError,
    this.preparationLoadError,
    this.ratingLoadError,
  }) : days = List.unmodifiable(days) {
    if (days.length != 7 ||
        !_sameDate(days.first.localDate, weekStartsOn) ||
        days.asMap().entries.any(
              (entry) => !_sameDate(
                entry.value.localDate,
                _datePlusDays(weekStartsOn, entry.key),
              ),
            )) {
      throw const DashboardFullWeekException(
        'Full-week projection must contain one ordered Monday-to-Sunday week.',
      );
    }
  }

  factory DashboardFullWeekProjection.empty(DateTime displayedLocalDate) {
    return const DashboardFullWeekProjector().project(
      displayedLocalDate: displayedLocalDate,
    );
  }

  final DateTime displayedLocalDate;
  final DateTime weekStartsOn;
  final List<DashboardFullWeekDay> days;
  final String? commitmentLoadError;
  final String? preparationLoadError;
  final String? ratingLoadError;

  bool get hasPartialSourceFailure =>
      commitmentLoadError != null || preparationLoadError != null;

  bool get ratingStatusUnavailable => ratingLoadError != null;
}

class DashboardFullWeekDay {
  DashboardFullWeekDay({
    required this.localDate,
    required List<DashboardFullWeekItem> items,
  }) : items = List.unmodifiable(items);

  final DateTime localDate;
  final List<DashboardFullWeekItem> items;
}

class DashboardFullWeekItem {
  const DashboardFullWeekItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.timeLabel,
    required this.sortMinutes,
    required this.status,
    this.location,
    this.planId,
    this.blockId,
    this.preparationState,
  });

  final String id;
  final DashboardFullWeekItemKind kind;
  final String title;
  final String timeLabel;
  final int sortMinutes;
  final DashboardAppointmentStatus status;
  final String? location;
  final String? planId;
  final String? blockId;
  final String? preparationState;
}

class DashboardSetupCommitmentFact {
  const DashboardSetupCommitmentFact({
    required this.id,
    required this.title,
    required this.weekday,
    required this.startsAt,
    required this.endsAt,
    required this.sortMinutes,
    this.location,
    this.validFrom,
    this.validUntil,
  });

  final String id;
  final String title;
  final int weekday;
  final String startsAt;
  final String endsAt;
  final int sortMinutes;
  final String? location;
  final DateTime? validFrom;
  final DateTime? validUntil;
}

class DashboardPreparationBlockFact {
  const DashboardPreparationBlockFact({
    required this.id,
    required this.planId,
    required this.planTitle,
    required this.localDate,
    required this.localStartTime,
    required this.localEndTime,
    required this.sortMinutes,
    required this.state,
    required this.recoveryMinutes,
    required this.reservedLocalEndTime,
  });

  final String id;
  final String planId;
  final String planTitle;
  final String localDate;
  final String localStartTime;
  final String localEndTime;
  final int sortMinutes;
  final String state;
  final int recoveryMinutes;
  final String reservedLocalEndTime;
}

class DashboardBlockFocusFact {
  const DashboardBlockFocusFact({
    required this.sessionId,
    required this.terminal,
    required this.hasValidReflection,
  });

  final String sessionId;
  final bool terminal;
  final bool hasValidReflection;
}

class DashboardFullWeekProjector {
  const DashboardFullWeekProjector();

  DashboardFullWeekProjection project({
    required DateTime displayedLocalDate,
    List<DashboardSetupCommitmentFact> commitments = const [],
    List<DashboardPreparationBlockFact> preparationBlocks = const [],
    Map<String, List<DashboardBlockFocusFact>> focusByBlock = const {},
    String? commitmentLoadError,
    String? preparationLoadError,
    String? ratingLoadError,
  }) {
    if (commitments.length > 200 || preparationBlocks.length > 240) {
      throw const DashboardFullWeekException(
        'Full-week projection exceeded its bounded size.',
      );
    }
    final displayed = _dateOnly(displayedLocalDate);
    final monday = _datePlusDays(displayed, -(displayed.weekday - 1));
    final itemsByDate = <String, List<DashboardFullWeekItem>>{
      for (var index = 0; index < 7; index += 1)
        _dateKey(_datePlusDays(monday, index)): [],
    };

    final seenCommitments = <String>{};
    for (final commitment in commitments) {
      if (!seenCommitments.add(commitment.id) ||
          commitment.weekday < DateTime.monday ||
          commitment.weekday > DateTime.sunday ||
          commitment.title.trim().isEmpty ||
          commitment.sortMinutes < 0 ||
          commitment.sortMinutes >= 24 * 60 ||
          (commitment.validFrom != null &&
              commitment.validUntil != null &&
              commitment.validUntil!.isBefore(commitment.validFrom!))) {
        throw const DashboardFullWeekException(
          'Setup commitment projection is invalid.',
        );
      }
      final date = _datePlusDays(monday, commitment.weekday - 1);
      if ((commitment.validFrom != null &&
              date.isBefore(_dateOnly(commitment.validFrom!))) ||
          (commitment.validUntil != null &&
              date.isAfter(_dateOnly(commitment.validUntil!)))) {
        continue;
      }
      itemsByDate[_dateKey(date)]!.add(
        DashboardFullWeekItem(
          id: commitment.id,
          kind: DashboardFullWeekItemKind.setupCommitment,
          title: commitment.title,
          timeLabel: _timeRange(commitment.startsAt, commitment.endsAt),
          sortMinutes: commitment.sortMinutes,
          status: DashboardAppointmentStatus.notApplicable,
          location: commitment.location,
        ),
      );
    }

    final seenBlocks = <String>{};
    for (final block in preparationBlocks) {
      if (!seenBlocks.add(block.id) ||
          block.planId.trim().isEmpty ||
          block.planTitle.trim().isEmpty ||
          block.sortMinutes < 0 ||
          block.sortMinutes >= 24 * 60 ||
          !const {'upcoming', 'partial', 'completed', 'missed'}
              .contains(block.state)) {
        throw const DashboardFullWeekException(
          'Preparation block projection is invalid.',
        );
      }
      final dayItems = itemsByDate[block.localDate];
      if (dayItems == null) continue;
      final focusFacts = focusByBlock[block.id] ?? const [];
      final completed = block.state == 'completed';
      final fullyRated = ratingLoadError == null &&
          completed &&
          focusFacts.isNotEmpty &&
          focusFacts.every(
            (fact) => fact.terminal && fact.hasValidReflection,
          );
      dayItems.add(
        DashboardFullWeekItem(
          id: block.id,
          kind: DashboardFullWeekItemKind.preparation,
          title: block.planTitle,
          timeLabel: block.recoveryMinutes == 0
              ? _timeRange(block.localStartTime, block.localEndTime)
              : '${_timeRange(block.localStartTime, block.localEndTime)} focus + '
                  '${block.recoveryMinutes} min recovery · reserved until '
                  '${block.reservedLocalEndTime}',
          sortMinutes: block.sortMinutes,
          status: fullyRated
              ? DashboardAppointmentStatus.fullyRated
              : completed
                  ? DashboardAppointmentStatus.completed
                  : DashboardAppointmentStatus.open,
          planId: block.planId,
          blockId: block.id,
          preparationState: block.state,
        ),
      );
    }

    final days = List.generate(7, (index) {
      final date = _datePlusDays(monday, index);
      final items = itemsByDate[_dateKey(date)]!
        ..sort((left, right) {
          final byTime = left.sortMinutes.compareTo(right.sortMinutes);
          if (byTime != 0) return byTime;
          final byTitle = left.title.compareTo(right.title);
          if (byTitle != 0) return byTitle;
          return left.id.compareTo(right.id);
        });
      return DashboardFullWeekDay(localDate: date, items: items);
    });

    return DashboardFullWeekProjection(
      displayedLocalDate: displayed,
      weekStartsOn: monday,
      days: days,
      commitmentLoadError: commitmentLoadError,
      preparationLoadError: preparationLoadError,
      ratingLoadError: ratingLoadError,
    );
  }
}

class DashboardFullWeekException implements Exception {
  const DashboardFullWeekException(this.message);

  final String message;

  @override
  String toString() => message;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _datePlusDays(DateTime value, int days) {
  final utc = DateTime.utc(value.year, value.month, value.day).add(
    Duration(days: days),
  );
  return DateTime(utc.year, utc.month, utc.day);
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _timeRange(String start, String end) =>
    end.trim().isEmpty ? start : '$start–$end';
