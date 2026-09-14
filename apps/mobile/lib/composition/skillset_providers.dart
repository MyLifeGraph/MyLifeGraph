import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/capabilities/app_surface_capabilities.dart';
import '../features/insights/domain/entities/skillset_display_preferences.dart';
import '../features/insights/presentation/providers/insights_providers.dart';
import 'auth_providers.dart';

// Device-local display choices only. Never gate Capture or share between owners.
final skillsetPreferenceScopeProvider = Provider<String?>((ref) {
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (session == null) return null;
  return session.isGuestSession ? 'guest' : 'account:${session.profile.id}';
});

final skillsetPreferencesLoaderProvider =
    Provider<Future<SharedPreferences> Function()>(
      (ref) => SharedPreferences.getInstance,
    );

final skillsetDisplayPreferencesProvider =
    StateNotifierProvider<
      SkillsetDisplayPreferencesController,
      SkillsetDisplayPreferences
    >((ref) {
      return SkillsetDisplayPreferencesController(
        ref.watch(skillsetPreferenceScopeProvider),
        ref.watch(skillsetPreferencesLoaderProvider),
      );
    });

final skillsetDimensionsProvider = Provider<Set<String>>(
  (ref) => ref.watch(skillsetDisplayPreferencesProvider).dimensions,
);

class SkillsetDisplayPreferencesController
    extends StateNotifier<SkillsetDisplayPreferences> {
  SkillsetDisplayPreferencesController(this.scope, this.loadPreferences)
    : super(SkillsetDisplayPreferences()) {
    _tail = _restore();
  }

  final String? scope;
  final Future<SharedPreferences> Function() loadPreferences;
  bool _changed = false;
  Future<void> _tail = Future.value();

  String get _key => 'insights_skillset_display_v1:$scope';
  Future<void> get settled => _tail;

  Future<void> _restore() async {
    if (scope == null) return;
    try {
      final preferences = await loadPreferences();
      final raw = preferences.getString(_key);
      if (raw == null || !mounted || _changed) return;
      final saved = jsonDecode(raw);
      if (saved is! Map<String, dynamic> || saved['dimensions'] is! List) {
        return;
      }
      final dimensions = (saved['dimensions'] as List)
          .whereType<String>()
          .where(supportedSkillsetDimensions.contains)
          .toSet();
      state = SkillsetDisplayPreferences(
        dimensions: dimensions,
        chart: saved['chart'] == 'bars'
            ? SkillsetChartView.bars
            : SkillsetChartView.radar,
      );
    } catch (_) {
      // Optional device storage must not block Insights or expose stored data.
    }
  }

  Future<bool> toggle(String id) {
    if (!supportedSkillsetDimensions.contains(id)) return Future.value(false);
    final dimensions = {...state.dimensions};
    if (!dimensions.remove(id)) dimensions.add(id);
    return _save(
      SkillsetDisplayPreferences(dimensions: dimensions, chart: state.chart),
    );
  }

  Future<bool> selectChart(SkillsetChartView chart) => _save(
    SkillsetDisplayPreferences(dimensions: state.dimensions, chart: chart),
  );

  Future<bool> _save(SkillsetDisplayPreferences next) {
    _changed = true;
    state = next;
    if (scope == null) return Future.value(false);
    final encoded = jsonEncode({
      'dimensions': next.dimensions.toList(),
      'chart': next.chart.name,
    });
    final operation = _tail.then((_) async {
      try {
        final preferences = await loadPreferences();
        return await preferences.setString(_key, encoded);
      } catch (_) {
        return false;
      }
    });
    _tail = operation.then<void>((_) {});
    return operation;
  }
}

final optionalSkillsetCaptureProvider = Provider<bool>(
  (ref) =>
      ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo ||
      (ref
              .watch(personalPatternsProvider)
              .valueOrNull
              ?.supportsSkillsetCapture ??
          false),
);
