import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/client_uuid.dart';
import '../domain/learning_preferences.dart';
import '../domain/learning_repository.dart';

class LearningSettingsState {
  const LearningSettingsState({
    required this.isLoading,
    required this.isSaving,
    required this.isClearing,
    required this.preferences,
    required this.error,
    required this.exactUpdateRetry,
    required this.exactClearRetry,
    required this.reloadRequired,
    required this.lastClearedCount,
  });

  const LearningSettingsState.initial()
      : isLoading = true,
        isSaving = false,
        isClearing = false,
        preferences = null,
        error = null,
        exactUpdateRetry = null,
        exactClearRetry = null,
        reloadRequired = false,
        lastClearedCount = null;

  final bool isLoading;
  final bool isSaving;
  final bool isClearing;
  final LearningPreferences? preferences;
  final Object? error;
  final LearningPreferencesUpdate? exactUpdateRetry;
  final FocusReflectionHistoryClearRequest? exactClearRetry;
  final bool reloadRequired;
  final int? lastClearedCount;

  bool get requiresExactRetry =>
      exactUpdateRetry != null || exactClearRetry != null;
}

class LearningSettingsController extends StateNotifier<LearningSettingsState> {
  LearningSettingsController({
    required LearningRepository repository,
    bool autoLoad = true,
  })  : _repository = repository,
        super(const LearningSettingsState.initial()) {
    if (autoLoad) Future<void>.microtask(load);
  }

  final LearningRepository _repository;
  bool _disposed = false;

  Future<void> load() async {
    if (state.isSaving || state.isClearing) return;
    state = LearningSettingsState(
      isLoading: true,
      isSaving: false,
      isClearing: false,
      preferences: state.preferences,
      error: null,
      exactUpdateRetry: null,
      exactClearRetry: null,
      reloadRequired: state.reloadRequired || state.requiresExactRetry,
      lastClearedCount: state.lastClearedCount,
    );
    try {
      final preferences = await _repository.getPreferences();
      if (_disposed) return;
      state = LearningSettingsState(
        isLoading: false,
        isSaving: false,
        isClearing: false,
        preferences: preferences,
        error: null,
        exactUpdateRetry: null,
        exactClearRetry: null,
        reloadRequired: false,
        lastClearedCount: state.lastClearedCount,
      );
    } catch (error) {
      if (_disposed) return;
      state = LearningSettingsState(
        isLoading: false,
        isSaving: false,
        isClearing: false,
        preferences: state.preferences,
        error: error,
        exactUpdateRetry: null,
        exactClearRetry: null,
        reloadRequired: state.reloadRequired,
        lastClearedCount: state.lastClearedCount,
      );
    }
  }

  Future<bool> save({
    required bool focusReflectionPromptEnabled,
    required bool personalPatternAnalysisEnabled,
    required bool learnedFocusPlanningEnabled,
  }) {
    final current = state.preferences;
    if (current == null ||
        state.isLoading ||
        state.isSaving ||
        state.isClearing ||
        state.requiresExactRetry ||
        state.reloadRequired) {
      return Future.value(false);
    }
    return _saveExact(
      LearningPreferencesUpdate(
        requestId: newClientUuid(),
        expectedRevision: current.revision,
        focusReflectionPromptEnabled: focusReflectionPromptEnabled,
        personalPatternAnalysisEnabled: personalPatternAnalysisEnabled,
        learnedFocusPlanningEnabled: learnedFocusPlanningEnabled,
      ),
    );
  }

  Future<bool> retryExact() {
    final update = state.exactUpdateRetry;
    if (update != null) return _saveExact(update);
    final clear = state.exactClearRetry;
    if (clear != null) return _clearExact(clear);
    return Future.value(false);
  }

  Future<bool> clearFocusReflections() {
    final current = state.preferences;
    if (current == null ||
        state.isLoading ||
        state.isSaving ||
        state.isClearing ||
        state.requiresExactRetry ||
        state.reloadRequired) {
      return Future.value(false);
    }
    return _clearExact(
      FocusReflectionHistoryClearRequest(
        requestId: newClientUuid(),
        expectedRevision: current.revision,
      ),
    );
  }

  Future<bool> _saveExact(LearningPreferencesUpdate request) async {
    state = LearningSettingsState(
      isLoading: false,
      isSaving: true,
      isClearing: false,
      preferences: state.preferences,
      error: null,
      exactUpdateRetry: state.exactUpdateRetry,
      exactClearRetry: null,
      reloadRequired: state.reloadRequired,
      lastClearedCount: state.lastClearedCount,
    );
    try {
      final preferences = await _repository.updatePreferences(request);
      if (_disposed) return false;
      state = LearningSettingsState(
        isLoading: false,
        isSaving: false,
        isClearing: false,
        preferences: preferences,
        error: null,
        exactUpdateRetry: null,
        exactClearRetry: null,
        reloadRequired: false,
        lastClearedCount: state.lastClearedCount,
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = LearningSettingsState(
        isLoading: false,
        isSaving: false,
        isClearing: false,
        preferences: state.preferences,
        error: error,
        exactUpdateRetry:
            error is LearningOutcomeUnknownException ? request : null,
        exactClearRetry: null,
        reloadRequired: error is LearningConflictException,
        lastClearedCount: state.lastClearedCount,
      );
      return false;
    }
  }

  Future<bool> _clearExact(
    FocusReflectionHistoryClearRequest request,
  ) async {
    state = LearningSettingsState(
      isLoading: false,
      isSaving: false,
      isClearing: true,
      preferences: state.preferences,
      error: null,
      exactUpdateRetry: null,
      exactClearRetry: state.exactClearRetry,
      reloadRequired: state.reloadRequired,
      lastClearedCount: state.lastClearedCount,
    );
    try {
      final result = await _repository.clearFocusReflections(request);
      if (_disposed) return false;
      state = LearningSettingsState(
        isLoading: false,
        isSaving: false,
        isClearing: false,
        preferences: state.preferences,
        error: null,
        exactUpdateRetry: null,
        exactClearRetry: null,
        reloadRequired: false,
        lastClearedCount: result.deletedCount,
      );
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = LearningSettingsState(
        isLoading: false,
        isSaving: false,
        isClearing: false,
        preferences: state.preferences,
        error: error,
        exactUpdateRetry: null,
        exactClearRetry:
            error is LearningOutcomeUnknownException ? request : null,
        reloadRequired: error is LearningConflictException,
        lastClearedCount: state.lastClearedCount,
      );
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
