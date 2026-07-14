import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/theme_mode_provider.dart';

void main() {
  test('restores and persists the selected theme mode', () async {
    final store = _MemoryThemeModeStore(ThemeMode.light);
    final container = ProviderContainer(
      overrides: [themeModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(container.read(appThemeModeProvider), ThemeMode.dark);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appThemeModeProvider), ThemeMode.light);

    final saved =
        await container.read(appThemeModeProvider.notifier).setLightMode(false);

    expect(saved, isTrue);
    expect(container.read(appThemeModeProvider), ThemeMode.dark);
    expect(store.saved, ThemeMode.dark);
  });

  test('a user choice wins over a slower restore', () async {
    final store = _DelayedThemeModeStore();
    final container = ProviderContainer(
      overrides: [themeModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    container.read(appThemeModeProvider);
    final choice =
        container.read(appThemeModeProvider.notifier).setLightMode(true);
    store.complete(ThemeMode.dark);
    expect(await choice, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appThemeModeProvider), ThemeMode.light);
  });

  test('storage failures stay observed and keep a truthful theme state',
      () async {
    final store = _FailingThemeModeStore();
    final container = ProviderContainer(
      overrides: [themeModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(container.read(appThemeModeProvider), ThemeMode.dark);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appThemeModeProvider), ThemeMode.dark);

    final saved =
        await container.read(appThemeModeProvider.notifier).setLightMode(true);

    expect(saved, isFalse);
    expect(container.read(appThemeModeProvider), ThemeMode.dark);
  });

  test('rapid choices are persisted in invocation order', () async {
    final store = _ControlledThemeModeStore();
    final container = ProviderContainer(
      overrides: [themeModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    container.read(appThemeModeProvider);
    await Future<void>.delayed(Duration.zero);
    final light =
        container.read(appThemeModeProvider.notifier).setLightMode(true);
    final dark =
        container.read(appThemeModeProvider.notifier).setLightMode(false);

    expect(container.read(appThemeModeProvider), ThemeMode.dark);
    await Future<void>.delayed(Duration.zero);
    expect(store.started, [ThemeMode.light]);
    store.completeNext();
    await Future<void>.delayed(Duration.zero);
    expect(store.started, [ThemeMode.light, ThemeMode.dark]);
    store.completeNext();

    expect(await light, isTrue);
    expect(await dark, isTrue);
    expect(store.completed, [ThemeMode.light, ThemeMode.dark]);
    expect(container.read(appThemeModeProvider), ThemeMode.dark);
  });

  test('an older failed write cannot roll back a newer choice', () async {
    final store = _ControlledThemeModeStore();
    final container = ProviderContainer(
      overrides: [themeModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    container.read(appThemeModeProvider);
    await Future<void>.delayed(Duration.zero);
    final light =
        container.read(appThemeModeProvider.notifier).setLightMode(true);
    final dark =
        container.read(appThemeModeProvider.notifier).setLightMode(false);
    await Future<void>.delayed(Duration.zero);
    store.failNext();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appThemeModeProvider), ThemeMode.dark);
    store.completeNext();

    expect(await light, isFalse);
    expect(await dark, isTrue);
    expect(container.read(appThemeModeProvider), ThemeMode.dark);
  });

  test('two rapid failed writes return to the last durable mode', () async {
    final store = _ControlledThemeModeStore();
    final container = ProviderContainer(
      overrides: [themeModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    container.read(appThemeModeProvider);
    await Future<void>.delayed(Duration.zero);
    final light =
        container.read(appThemeModeProvider.notifier).setLightMode(true);
    final dark =
        container.read(appThemeModeProvider.notifier).setLightMode(false);
    await Future<void>.delayed(Duration.zero);
    store.failNext();
    await Future<void>.delayed(Duration.zero);
    store.failNext();

    expect(await light, isFalse);
    expect(await dark, isFalse);
    expect(container.read(appThemeModeProvider), ThemeMode.dark);
  });
}

class _MemoryThemeModeStore implements ThemeModeStore {
  _MemoryThemeModeStore(this.initial);

  final ThemeMode? initial;
  ThemeMode? saved;

  @override
  Future<ThemeMode?> read() async => initial;

  @override
  Future<void> write(ThemeMode mode) async {
    saved = mode;
  }
}

class _DelayedThemeModeStore implements ThemeModeStore {
  final _completer = Completer<ThemeMode?>();

  void complete(ThemeMode mode) => _completer.complete(mode);

  @override
  Future<ThemeMode?> read() => _completer.future;

  @override
  Future<void> write(ThemeMode mode) async {}
}

class _FailingThemeModeStore implements ThemeModeStore {
  @override
  Future<ThemeMode?> read() => Future.error(StateError('read failed'));

  @override
  Future<void> write(ThemeMode mode) =>
      Future.error(StateError('write failed'));
}

class _ControlledThemeModeStore implements ThemeModeStore {
  final started = <ThemeMode>[];
  final completed = <ThemeMode>[];
  final _pending = <(ThemeMode, Completer<void>)>[];

  @override
  Future<ThemeMode?> read() async => null;

  @override
  Future<void> write(ThemeMode mode) {
    final completer = Completer<void>();
    started.add(mode);
    _pending.add((mode, completer));
    return completer.future.then((_) => completed.add(mode));
  }

  void completeNext() {
    final next = _pending.removeAt(0);
    next.$2.complete();
  }

  void failNext() {
    final next = _pending.removeAt(0);
    next.$2.completeError(StateError('write failed'));
  }
}
