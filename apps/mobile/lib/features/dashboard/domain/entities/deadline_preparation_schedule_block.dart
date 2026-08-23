class DeadlinePreparationScheduleBlock {
  const DeadlinePreparationScheduleBlock({
    required this.id,
    required this.planId,
    required this.planTitle,
    required this.revision,
    required this.sequence,
    required this.startsAt,
    required this.endsAt,
    required this.plannedMinutes,
  });

  final String id;
  final String planId;
  final String planTitle;
  final int revision;
  final int sequence;
  final DateTime startsAt;
  final DateTime endsAt;
  final int plannedMinutes;
}
