import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/github_app_releases.dart';
import '../data/installed_app_version.dart';
import '../domain/app_update.dart';

export '../domain/app_update.dart';

final appUpdatesSupportedProvider = Provider<bool>(
  (_) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

enum UpdateCheck { idle, checking, current, available, failed }

class AppUpdatesState {
  const AppUpdatesState({
    this.installed,
    this.update,
    this.check = UpdateCheck.idle,
  });
  final InstalledAppVersion? installed;
  final AppUpdate? update;
  final UpdateCheck check;
}

final appUpdatesProvider =
    StateNotifierProvider<AppUpdatesController, AppUpdatesState>((ref) {
      final controller = AppUpdatesController(
        supported: ref.watch(appUpdatesSupportedProvider),
        readInstalled: readInstalledAppVersion,
        releases: GitHubAppReleases(),
      );
      return controller;
    });

class AppUpdatesController extends StateNotifier<AppUpdatesState> {
  AppUpdatesController({
    required this.supported,
    required this.readInstalled,
    required this.releases,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       super(const AppUpdatesState()) {
    if (supported) unawaited(loadInstalled());
  }
  final bool supported;
  final Future<InstalledAppVersion> Function() readInstalled;
  final GitHubAppReleases releases;
  final DateTime Function() now;
  static const noticeKey = 'app_update_highest_notified_build';
  Future<InstalledAppVersion>? _installed;
  Future<void>? _checking;
  DateTime? _lastAttempt;
  bool _claiming = false;

  Future<void> loadInstalled() async {
    try {
      final installed = await (_installed ??= readInstalled());
      if (mounted) {
        state = AppUpdatesState(
          installed: installed,
          update: state.update,
          check: state.check,
        );
      }
    } catch (_) {
      _installed = null;
      if (mounted) state = const AppUpdatesState(check: UpdateCheck.failed);
    }
  }

  Future<void> check({bool manual = false}) {
    if (!supported || !mounted) return Future.value();
    if (_checking != null) return _checking!;
    if (!manual && _lastAttempt != null) {
      final elapsed = now().difference(_lastAttempt!);
      if (!elapsed.isNegative && elapsed < const Duration(hours: 6)) {
        return Future.value();
      }
    }
    _lastAttempt = now();
    return _checking = _performCheck().whenComplete(() => _checking = null);
  }

  Future<void> _performCheck() async {
    state = AppUpdatesState(
      installed: state.installed,
      check: UpdateCheck.checking,
    );
    try {
      final installed = await (_installed ??= readInstalled());
      final update = await releases.newest(installed);
      if (mounted) {
        state = AppUpdatesState(
          installed: installed,
          update: update,
          check: update == null ? UpdateCheck.current : UpdateCheck.available,
        );
      }
    } catch (_) {
      _installed = null;
      if (mounted) {
        state = AppUpdatesState(
          installed: state.installed,
          check: UpdateCheck.failed,
        );
      }
    }
  }

  /// Persist before presentation: dismissal, back, download and process restart
  /// cannot re-prompt for this build. Never sync this device preference to an account.
  Future<bool> claimNotice(AppUpdate update) async {
    if (_claiming || !mounted) return false;
    _claiming = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (update.code <= (prefs.getInt(noticeKey) ?? 0)) return false;
      return await prefs.setInt(noticeKey, update.code);
    } catch (_) {
      return false; // Storage failure must not create a popup on every launch.
    } finally {
      _claiming = false;
    }
  }
}
