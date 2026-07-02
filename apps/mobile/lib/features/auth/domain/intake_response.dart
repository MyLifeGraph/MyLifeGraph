import 'app_session.dart';

class IntakeResponseDraft {
  const IntakeResponseDraft({
    required this.displayName,
    required this.primaryFocusAreas,
    required this.goals,
    required this.frictionPoints,
    required this.weekdayShape,
    required this.bestEnergyWindow,
    required this.coachingStyle,
    required this.reminderPreference,
    required this.existingHabits,
    required this.fixedCommitments,
    required this.contextNote,
    required this.calendarConnectionIntent,
  });

  final String? displayName;
  final List<String> primaryFocusAreas;
  final List<String> goals;
  final List<String> frictionPoints;
  final String weekdayShape;
  final String bestEnergyWindow;
  final String coachingStyle;
  final IntakeReminderPreference reminderPreference;
  final List<String> existingHabits;
  final List<TimetableDraft> fixedCommitments;
  final String? contextNote;
  final String calendarConnectionIntent;

  Map<String, dynamic> toJson() {
    return {
      'version': 'intake-v1',
      'responses': {
        if (displayName != null && displayName!.trim().isNotEmpty)
          'display_name': displayName!.trim(),
        'primary_focus_areas': primaryFocusAreas,
        'goals': goals,
        'friction_points': frictionPoints,
        'weekday_shape': weekdayShape,
        'best_energy_window': bestEnergyWindow,
        'coaching_style': coachingStyle,
        'reminder_preference': reminderPreference.toJson(),
        'existing_habits': existingHabits,
        'fixed_commitments':
            fixedCommitments.map(_commitmentToJson).toList(growable: false),
        if (contextNote != null && contextNote!.trim().isNotEmpty)
          'context_note': contextNote!.trim(),
        'calendar_connection_intent': calendarConnectionIntent,
      },
      'metadata': {
        'client': 'flutter',
        'source': 'onboarding',
      },
    };
  }

  Map<String, dynamic> _commitmentToJson(TimetableDraft draft) {
    return {
      'title': draft.title.trim(),
      if (draft.location.trim().isNotEmpty) 'location': draft.location.trim(),
      'weekday': draft.weekday,
      'starts_at': draft.startsAt,
      'ends_at': draft.endsAt,
    };
  }
}

class IntakeReminderPreference {
  const IntakeReminderPreference({
    required this.enabled,
    required this.quietHoursStart,
    required this.quietHoursEnd,
  });

  final bool enabled;
  final String quietHoursStart;
  final String quietHoursEnd;

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'quiet_hours': {
        'starts_at': quietHoursStart,
        'ends_at': quietHoursEnd,
      },
    };
  }
}
