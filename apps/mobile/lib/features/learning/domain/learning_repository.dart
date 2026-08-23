import 'learning_preferences.dart';

abstract interface class LearningRepository {
  Future<LearningPreferences> getPreferences();

  Future<LearningPreferences> updatePreferences(
    LearningPreferencesUpdate request,
  );

  Future<FocusReflectionHistoryClearResult> clearFocusReflections(
    FocusReflectionHistoryClearRequest request,
  );
}
