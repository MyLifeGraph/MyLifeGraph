import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/data/habit_completion_supabase_data_source.dart';

void main() {
  test('generic management excludes every setup-managed habit', () {
    for (final setupState in ['active', 'paused']) {
      final metadata = {
        'managed_by': 'setup',
        'setup_state': setupState,
      };

      expect(
        isHabitVisibleForFetch(metadata, excludeSetupManaged: true),
        isFalse,
      );
    }
  });

  test('completion keeps active setup habits but hides non-materialized states',
      () {
    expect(
      isHabitVisibleForFetch(
        const {'managed_by': 'setup', 'setup_state': 'active'},
        excludeSetupManaged: false,
      ),
      isTrue,
    );
    for (final setupState in ['candidate', 'archived']) {
      expect(
        isHabitVisibleForFetch(
          {'managed_by': 'setup', 'setup_state': setupState},
          excludeSetupManaged: false,
        ),
        isFalse,
      );
    }
  });

  test('manual habits remain available in generic management', () {
    expect(
      isHabitVisibleForFetch(
        const {'source': 'flutter-habit-management-v1'},
        excludeSetupManaged: true,
      ),
      isTrue,
    );
  });
}
