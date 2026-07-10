enum QuickCheckInSaveTarget { guest, supabase }

String quickCheckInMoodCode(int rating) {
  if (rating >= 9) {
    return 'great';
  }
  if (rating >= 7) {
    return 'good';
  }
  if (rating >= 5) {
    return 'neutral';
  }
  if (rating >= 3) {
    return 'low';
  }
  return 'very_low';
}

String quickCheckInMoodLabel(int rating) {
  return switch (quickCheckInMoodCode(rating)) {
    'great' => 'Great',
    'good' => 'Good',
    'neutral' => 'Neutral',
    'low' => 'Low',
    _ => 'Heavy',
  };
}

class QuickCheckInDraft {
  const QuickCheckInDraft({
    required this.captureId,
    required this.capturedAt,
    required this.mood,
    required this.energy,
    required this.sleepHours,
    required this.stress,
    required this.contextNote,
  });

  factory QuickCheckInDraft.empty(DateTime capturedAt) {
    return QuickCheckInDraft(
      captureId: 'daily-${capturedAt.toUtc().microsecondsSinceEpoch}',
      capturedAt: capturedAt,
      mood: null,
      energy: null,
      sleepHours: null,
      stress: null,
      contextNote: '',
    );
  }

  factory QuickCheckInDraft.fromJson(Map<String, dynamic> json) {
    final capturedAt = DateTime.parse('${json['createdAt']}');
    final draft = QuickCheckInDraft(
      captureId:
          '${json['captureId'] ?? 'daily-${capturedAt.toUtc().microsecondsSinceEpoch}'}',
      capturedAt: capturedAt,
      mood: (json['mood'] as num?)?.toInt(),
      energy: (json['energy'] as num?)?.toInt(),
      sleepHours: (json['sleepHours'] as num?)?.toDouble(),
      stress: (json['stress'] as num?)?.toInt(),
      contextNote: '${json['contextNote'] ?? json['coachNotes'] ?? ''}'.trim(),
    );
    draft.validate();
    return draft;
  }

  final String captureId;
  final DateTime capturedAt;
  final int? mood;
  final int? energy;
  final double? sleepHours;
  final int? stress;
  final String contextNote;

  bool get isComplete =>
      mood != null && energy != null && sleepHours != null && stress != null;

  String get entryDate {
    final month = capturedAt.month.toString().padLeft(2, '0');
    final day = capturedAt.day.toString().padLeft(2, '0');
    return '${capturedAt.year}-$month-$day';
  }

  QuickCheckInDraft copyWith({
    int? mood,
    int? energy,
    double? sleepHours,
    int? stress,
    String? contextNote,
  }) {
    return QuickCheckInDraft(
      captureId: captureId,
      capturedAt: capturedAt,
      mood: mood ?? this.mood,
      energy: energy ?? this.energy,
      sleepHours: sleepHours ?? this.sleepHours,
      stress: stress ?? this.stress,
      contextNote: contextNote ?? this.contextNote,
    );
  }

  QuickCheckInDraft normalized() {
    return copyWith(contextNote: contextNote.trim());
  }

  void validate() {
    if (captureId.trim().isEmpty) {
      throw const FormatException('The check-in capture id is required.');
    }
    if (!isComplete) {
      throw const FormatException('All check-in ratings must be selected.');
    }
    _validateRating('mood', mood!);
    _validateRating('energy', energy!);
    _validateRating('stress', stress!);
    if (sleepHours! < 0 || sleepHours! > 12) {
      throw const FormatException('Sleep hours must be between 0 and 12.');
    }
    final halfHours = sleepHours! * 2;
    if ((halfHours - halfHours.round()).abs() > 0.0001) {
      throw const FormatException('Sleep hours must use half-hour steps.');
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    final value = normalized();
    return {
      'captureId': value.captureId,
      'createdAt': value.capturedAt.toIso8601String(),
      'entryDate': value.entryDate,
      'mood': value.mood,
      'energy': value.energy,
      'sleepHours': value.sleepHours,
      'stress': value.stress,
      'contextNote': value.contextNote,
    };
  }

  static void _validateRating(String field, int value) {
    if (value < 1 || value > 10) {
      throw FormatException('$field must be between 1 and 10.');
    }
  }
}

abstract interface class QuickCheckInStore {
  QuickCheckInSaveTarget get target;

  Future<QuickCheckInDraft?> loadToday(DateTime today);

  Future<void> save(QuickCheckInDraft draft);
}

class QuickCheckInUnavailableException implements Exception {
  const QuickCheckInUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
