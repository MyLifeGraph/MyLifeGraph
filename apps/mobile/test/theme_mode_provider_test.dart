import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_theme_selection_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('restores and persists the selected Space theme', () async {
    final store = _MemoryThemeSelectionStore(AppThemeId.space);
    final container = ProviderContainer(
      overrides: [
        appThemeSelectionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appThemeSelectionProvider), AppThemeId.dark);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appThemeSelectionProvider), AppThemeId.space);

    final saved = await container
        .read(appThemeSelectionProvider.notifier)
        .select(AppThemeId.light);

    expect(saved, isTrue);
    expect(container.read(appThemeSelectionProvider), AppThemeId.light);
    expect(store.saved, AppThemeId.light);
  });

  for (final id in AppThemeId.values) {
    test('shared preferences restores the existing ${id.name} value', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesAppThemeSelectionStore.preferenceKey: id.name,
      });
      const store = SharedPreferencesAppThemeSelectionStore();

      expect(await store.read(), id);
      await store.write(id);

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(
          SharedPreferencesAppThemeSelectionStore.preferenceKey,
        ),
        id.name,
      );
    });
  }

  test('unknown persisted values fall back to Dark', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesAppThemeSelectionStore.preferenceKey: 'sepia',
    });

    expect(
      await const SharedPreferencesAppThemeSelectionStore().read(),
      AppThemeId.dark,
    );
  });

  test('a user choice wins over a slower restore', () async {
    final store = _DelayedThemeSelectionStore();
    final container = ProviderContainer(
      overrides: [
        appThemeSelectionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    container.read(appThemeSelectionProvider);
    final choice = container
        .read(appThemeSelectionProvider.notifier)
        .select(AppThemeId.space);
    store.complete(AppThemeId.light);
    expect(await choice, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appThemeSelectionProvider), AppThemeId.space);
  });

  test('storage failures stay observed and keep a truthful theme state',
      () async {
    final store = _FailingThemeSelectionStore();
    final container = ProviderContainer(
      overrides: [
        appThemeSelectionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appThemeSelectionProvider), AppThemeId.dark);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appThemeSelectionProvider), AppThemeId.dark);

    final saved = await container
        .read(appThemeSelectionProvider.notifier)
        .select(AppThemeId.space);

    expect(saved, isFalse);
    expect(container.read(appThemeSelectionProvider), AppThemeId.dark);
  });

  test('rapid choices are persisted in invocation order', () async {
    final store = _ControlledThemeSelectionStore();
    final container = ProviderContainer(
      overrides: [
        appThemeSelectionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    container.read(appThemeSelectionProvider);
    await Future<void>.delayed(Duration.zero);
    final space = container
        .read(appThemeSelectionProvider.notifier)
        .select(AppThemeId.space);
    final light = container
        .read(appThemeSelectionProvider.notifier)
        .select(AppThemeId.light);

    expect(container.read(appThemeSelectionProvider), AppThemeId.light);
    await Future<void>.delayed(Duration.zero);
    expect(store.started, [AppThemeId.space]);
    store.completeNext();
    await Future<void>.delayed(Duration.zero);
    expect(store.started, [AppThemeId.space, AppThemeId.light]);
    store.completeNext();

    expect(await space, isTrue);
    expect(await light, isTrue);
    expect(store.completed, [AppThemeId.space, AppThemeId.light]);
    expect(container.read(appThemeSelectionProvider), AppThemeId.light);
  });

  test('an older failed write cannot roll back a newer choice', () async {
    final store = _ControlledThemeSelectionStore();
    final container = ProviderContainer(
      overrides: [
        appThemeSelectionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    container.read(appThemeSelectionProvider);
    await Future<void>.delayed(Duration.zero);
    final space = container
        .read(appThemeSelectionProvider.notifier)
        .select(AppThemeId.space);
    final light = container
        .read(appThemeSelectionProvider.notifier)
        .select(AppThemeId.light);
    await Future<void>.delayed(Duration.zero);
    store.failNext();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appThemeSelectionProvider), AppThemeId.light);
    store.completeNext();

    expect(await space, isFalse);
    expect(await light, isTrue);
    expect(container.read(appThemeSelectionProvider), AppThemeId.light);
  });

  test('two rapid failed writes return to the last durable theme', () async {
    final store = _ControlledThemeSelectionStore();
    final container = ProviderContainer(
      overrides: [
        appThemeSelectionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    container.read(appThemeSelectionProvider);
    await Future<void>.delayed(Duration.zero);
    final space = container
        .read(appThemeSelectionProvider.notifier)
        .select(AppThemeId.space);
    final light = container
        .read(appThemeSelectionProvider.notifier)
        .select(AppThemeId.light);
    await Future<void>.delayed(Duration.zero);
    store.failNext();
    await Future<void>.delayed(Duration.zero);
    store.failNext();

    expect(await space, isFalse);
    expect(await light, isFalse);
    expect(container.read(appThemeSelectionProvider), AppThemeId.dark);
  });
}

class _MemoryThemeSelectionStore implements AppThemeSelectionStore {
  _MemoryThemeSelectionStore(this.initial);

  final AppThemeId? initial;
  AppThemeId? saved;

  @override
  Future<AppThemeId?> read() async => initial;

  @override
  Future<void> write(AppThemeId id) async {
    saved = id;
  }
}

class _DelayedThemeSelectionStore implements AppThemeSelectionStore {
  final _completer = Completer<AppThemeId?>();

  void complete(AppThemeId id) => _completer.complete(id);

  @override
  Future<AppThemeId?> read() => _completer.future;

  @override
  Future<void> write(AppThemeId id) async {}
}

class _FailingThemeSelectionStore implements AppThemeSelectionStore {
  @override
  Future<AppThemeId?> read() => Future.error(StateError('read failed'));

  @override
  Future<void> write(AppThemeId id) => Future.error(StateError('write failed'));
}

class _ControlledThemeSelectionStore implements AppThemeSelectionStore {
  final started = <AppThemeId>[];
  final completed = <AppThemeId>[];
  final _pending = <(AppThemeId, Completer<void>)>[];

  @override
  Future<AppThemeId?> read() async => null;

  @override
  Future<void> write(AppThemeId id) {
    final completer = Completer<void>();
    started.add(id);
    _pending.add((id, completer));
    return completer.future.then((_) => completed.add(id));
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
