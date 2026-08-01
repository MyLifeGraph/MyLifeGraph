import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

abstract interface class AppThemeSelectionStore {
  Future<AppThemeId?> read();

  Future<void> write(AppThemeId id);
}

class SharedPreferencesAppThemeSelectionStore
    implements AppThemeSelectionStore {
  const SharedPreferencesAppThemeSelectionStore();

  static const preferenceKey = 'app_theme_mode';

  @override
  Future<AppThemeId?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(preferenceKey);
    if (stored == null) return null;
    return switch (stored) {
      'dark' => AppThemeId.dark,
      'light' => AppThemeId.light,
      'space' => AppThemeId.space,
      _ => AppThemeId.dark,
    };
  }

  @override
  Future<void> write(AppThemeId id) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(preferenceKey, id.name);
    if (!saved) {
      throw StateError('Theme preference storage rejected the write.');
    }
  }
}

final appThemeSelectionStoreProvider = Provider<AppThemeSelectionStore>(
  (_) => const SharedPreferencesAppThemeSelectionStore(),
);

final appThemeSelectionProvider =
    NotifierProvider<AppThemeSelectionController, AppThemeId>(
  AppThemeSelectionController.new,
);

class AppThemeSelectionController extends Notifier<AppThemeId> {
  bool _changedDuringRestore = false;
  var _selectionRevision = 0;
  AppThemeId _lastConfirmedSelection = AppThemeId.dark;
  Future<void> _writeTail = Future<void>.value();

  @override
  AppThemeId build() {
    _writeTail = _restore(ref.watch(appThemeSelectionStoreProvider));
    return AppThemeId.dark;
  }

  Future<void> _restore(AppThemeSelectionStore store) async {
    try {
      final saved = await store.read();
      if (saved != null) {
        _lastConfirmedSelection = saved;
        if (!_changedDuringRestore) {
          state = saved;
        }
      }
    } catch (_) {
      // Keep the deterministic default when local preference storage is
      // unavailable. This background restore must never leak an async error.
    }
  }

  Future<bool> select(AppThemeId selected) async {
    _changedDuringRestore = true;
    final revision = ++_selectionRevision;
    state = selected;
    final store = ref.read(appThemeSelectionStoreProvider);
    final operation = _writeTail.then((_) async {
      try {
        await store.write(selected);
        _lastConfirmedSelection = selected;
        return true;
      } catch (_) {
        if (_selectionRevision == revision && state == selected) {
          state = _lastConfirmedSelection;
        }
        return false;
      }
    });
    _writeTail = operation.then<void>((_) {});
    return operation;
  }
}
