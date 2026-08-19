import 'pilot_participation.dart' as participation;

enum AppRole {
  user,
  vip,
  admin,
  guest;

  static AppRole fromDatabase(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'vip' => AppRole.vip,
      'admin' => AppRole.admin,
      'guest' => AppRole.guest,
      _ => AppRole.user,
    };
  }

  String get databaseValue => name;
}

class AppProfile {
  const AppProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.timezone,
    required this.role,
    required this.onboardingDone,
    required this.authProvider,
    this.dailyPreparationBudgetMinutes,
    this.timezoneRevision = 1,
    this.preparationBudgetRevision = 1,
    this.pilotParticipationNoticeVersion,
    this.pilotParticipationAcceptedAt,
  });

  final String id;
  final String email;
  final String name;
  final String timezone;
  final AppRole role;
  final bool onboardingDone;
  final String authProvider;
  final int? dailyPreparationBudgetMinutes;
  final int timezoneRevision;
  final int preparationBudgetRevision;
  final String? pilotParticipationNoticeVersion;
  final DateTime? pilotParticipationAcceptedAt;

  bool get isGuest => role == AppRole.guest;
  bool get isAdmin => role == AppRole.admin;
  bool get hasCurrentPilotParticipation =>
      pilotParticipationNoticeVersion ==
          participation.pilotParticipationNoticeVersion &&
      pilotParticipationAcceptedAt?.isUtc == true;

  AppProfile copyWith({
    String? name,
    String? email,
    String? timezone,
    AppRole? role,
    bool? onboardingDone,
    String? authProvider,
    int? timezoneRevision,
    String? pilotParticipationNoticeVersion,
    DateTime? pilotParticipationAcceptedAt,
  }) {
    return AppProfile(
      id: id,
      email: email ?? this.email,
      name: name ?? this.name,
      timezone: timezone ?? this.timezone,
      role: role ?? this.role,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      authProvider: authProvider ?? this.authProvider,
      dailyPreparationBudgetMinutes: dailyPreparationBudgetMinutes,
      timezoneRevision: timezoneRevision ?? this.timezoneRevision,
      preparationBudgetRevision: preparationBudgetRevision,
      pilotParticipationNoticeVersion: pilotParticipationNoticeVersion ??
          this.pilotParticipationNoticeVersion,
      pilotParticipationAcceptedAt:
          pilotParticipationAcceptedAt ?? this.pilotParticipationAcceptedAt,
    );
  }

  AppProfile withDailyPreparationBudget(
    int? minutes, {
    int? revision,
  }) {
    return AppProfile(
      id: id,
      email: email,
      name: name,
      timezone: timezone,
      role: role,
      onboardingDone: onboardingDone,
      authProvider: authProvider,
      dailyPreparationBudgetMinutes: minutes,
      timezoneRevision: timezoneRevision,
      preparationBudgetRevision: revision ?? preparationBudgetRevision,
      pilotParticipationNoticeVersion: pilotParticipationNoticeVersion,
      pilotParticipationAcceptedAt: pilotParticipationAcceptedAt,
    );
  }
}

class AppSession {
  const AppSession.authenticated(this.profile) : isGuestSession = false;
  const AppSession.guest(this.profile) : isGuestSession = true;

  final AppProfile profile;
  final bool isGuestSession;

  bool get isAuthenticated => !isGuestSession;
  bool get requiresOnboarding => !profile.onboardingDone;
}
