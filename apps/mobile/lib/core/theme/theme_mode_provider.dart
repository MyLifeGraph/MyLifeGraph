import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ThemeModeStore {
  Future<ThemeMode?> read();

  Future<void> write(ThemeMode mode);
}

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  const SharedPreferencesThemeModeStore();

  static const preferenceKey = 'app_theme_mode';

  @override
  Future<ThemeMode?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(preferenceKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
  }

  @override
  Future<void> write(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      preferenceKey,
      mode == ThemeMode.light ? 'light' : 'dark',
    );
    if (!saved) {
      throw StateError('Theme preference storage rejected the write.');
    }
  }
}

final themeModeStoreProvider = Provider<ThemeModeStore>(
  (_) => const SharedPreferencesThemeModeStore(),
);

final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, ThemeMode>(
  AppThemeModeController.new,
);

class AppThemeModeController extends Notifier<ThemeMode> {
  bool _changedDuringRestore = false;
  var _selectionRevision = 0;
  ThemeMode _lastConfirmedMode = ThemeMode.dark;
  Future<void> _writeTail = Future<void>.value();

  @override
  ThemeMode build() {
    _writeTail = _restore(ref.watch(themeModeStoreProvider));
    return ThemeMode.dark;
  }

  Future<void> _restore(ThemeModeStore store) async {
    try {
      final saved = await store.read();
      if (saved != null) {
        _lastConfirmedMode = saved;
        if (!_changedDuringRestore) {
          state = saved;
        }
      }
    } catch (_) {
      // Keep the deterministic default when local preference storage is
      // unavailable. This background restore must never leak an async error.
    }
  }

  Future<bool> setLightMode(bool enabled) async {
    _changedDuringRestore = true;
    final revision = ++_selectionRevision;
    final selected = enabled ? ThemeMode.light : ThemeMode.dark;
    state = selected;
    final store = ref.read(themeModeStoreProvider);
    final operation = _writeTail.then((_) async {
      try {
        await store.write(selected);
        _lastConfirmedMode = selected;
        return true;
      } catch (_) {
        if (_selectionRevision == revision && state == selected) {
          state = _lastConfirmedMode;
        }
        return false;
      }
    });
    _writeTail = operation.then<void>((_) {});
    return operation;
  }
}
