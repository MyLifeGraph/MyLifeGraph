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
  });

  final String id;
  final String email;
  final String name;
  final String timezone;
  final AppRole role;
  final bool onboardingDone;
  final String authProvider;

  bool get isGuest => role == AppRole.guest;
  bool get isAdmin => role == AppRole.admin;

  AppProfile copyWith({
    String? name,
    String? email,
    String? timezone,
    AppRole? role,
    bool? onboardingDone,
    String? authProvider,
  }) {
    return AppProfile(
      id: id,
      email: email ?? this.email,
      name: name ?? this.name,
      timezone: timezone ?? this.timezone,
      role: role ?? this.role,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      authProvider: authProvider ?? this.authProvider,
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

class TimetableDraft {
  const TimetableDraft({
    required this.title,
    required this.location,
    required this.weekday,
    required this.startsAt,
    required this.endsAt,
  });

  final String title;
  final String location;
  final int weekday;
  final String startsAt;
  final String endsAt;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'location': location,
      'weekday': weekday,
      'startsAt': startsAt,
      'endsAt': endsAt,
    };
  }

  static TimetableDraft fromJson(Map<String, dynamic> json) {
    return TimetableDraft(
      title: '${json['title'] ?? ''}',
      location: '${json['location'] ?? ''}',
      weekday: (json['weekday'] as num?)?.toInt() ?? 1,
      startsAt: '${json['startsAt'] ?? '08:15'}',
      endsAt: '${json['endsAt'] ?? '09:45'}',
    );
  }
}
