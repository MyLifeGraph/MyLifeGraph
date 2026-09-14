import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_life_graph/composition/skillset_providers.dart';
import 'package:my_life_graph/features/insights/domain/entities/skillset_display_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  SkillsetDisplayPreferencesController controller(String? owner) =>
      SkillsetDisplayPreferencesController(
        owner,
        SharedPreferences.getInstance,
      );

  test(
    'dimensions and chart survive a new controller and preserve empty selection',
    () async {
      final first = controller('account:one');
      await first.settled;
      await first.toggle('motivation');
      await first.toggle('discipline');
      await first.selectChart(SkillsetChartView.bars);
      first.dispose();
      final second = controller('account:one');
      await second.settled;
      expect(second.state.dimensions, {
        ...defaultSkillsetDimensions,
        'motivation',
        'discipline',
      });
      expect(second.state.chart, SkillsetChartView.bars);
      for (final id in {...second.state.dimensions}) {
        await second.toggle(id);
      }
      second.dispose();
      final third = controller('account:one');
      await third.settled;
      expect(third.state.dimensions, isEmpty);
      expect(third.state.chart, SkillsetChartView.bars);
      third.dispose();
    },
  );

  test('account switches and guest preferences stay isolated', () async {
    final scope = StateProvider<String?>((_) => 'account:one');
    final container = ProviderContainer(
      overrides: [
        skillsetPreferenceScopeProvider.overrideWith((ref) => ref.watch(scope)),
      ],
    );
    addTearDown(container.dispose);
    final first = container.read(skillsetDisplayPreferencesProvider.notifier);
    await first.settled;
    await first.toggle('motivation');
    for (final owner in ['account:two', 'guest']) {
      container.read(scope.notifier).state = owner;
      final next = container.read(skillsetDisplayPreferencesProvider.notifier);
      await next.settled;
      expect(
        container.read(skillsetDimensionsProvider),
        defaultSkillsetDimensions,
      );
    }
    container.read(scope.notifier).state = 'account:one';
    await container.read(skillsetDisplayPreferencesProvider.notifier).settled;
    expect(container.read(skillsetDimensionsProvider), contains('motivation'));
  });

  test('late restore does not overwrite an immediate edit', () async {
    SharedPreferences.setMockInitialValues({
      'insights_skillset_display_v1:account:one': jsonEncode({
        'dimensions': ['mood'],
        'chart': 'bars',
      }),
    });
    final pending = Completer<SharedPreferences>();
    final preferences = SkillsetDisplayPreferencesController(
      'account:one',
      () => pending.future,
    );
    final change = preferences.toggle('motivation');
    pending.complete(await SharedPreferences.getInstance());
    expect(await change, isTrue);
    expect(preferences.state.dimensions, {
      ...defaultSkillsetDimensions,
      'motivation',
    });
    final restored = controller('account:one');
    await restored.settled;
    expect(restored.state.dimensions, preferences.state.dimensions);
    preferences.dispose();
    restored.dispose();
  });

  test('rapid edits are saved in order', () async {
    final preferences = controller('account:one');
    await preferences.settled;
    final changes = [
      preferences.toggle('motivation'),
      preferences.toggle('discipline'),
      preferences.selectChart(SkillsetChartView.bars),
      preferences.toggle('motivation'),
    ];
    expect(await Future.wait(changes), everyElement(isTrue));
    final restored = controller('account:one');
    await restored.settled;
    expect(restored.state.dimensions, {
      ...defaultSkillsetDimensions,
      'discipline',
    });
    expect(restored.state.chart, SkillsetChartView.bars);
    preferences.dispose();
    restored.dispose();
  });

  test(
    'unknown dimensions are ignored and invalid storage keeps defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        'insights_skillset_display_v1:account:one': jsonEncode({
          'dimensions': ['mood', 'unknown', 4],
          'chart': 'unknown',
        }),
        'insights_skillset_display_v1:account:two': 'invalid JSON',
      });
      final one = controller('account:one');
      final two = controller('account:two');
      await Future.wait([one.settled, two.settled]);
      expect(one.state.dimensions, {'mood'});
      expect(one.state.chart, SkillsetChartView.radar);
      expect(await one.toggle('unknown'), isFalse);
      expect(two.state.dimensions, defaultSkillsetDimensions);
      one.dispose();
      two.dispose();
    },
  );

  test(
    'unavailable storage keeps UI usable and reports a failed save',
    () async {
      final preferences = SkillsetDisplayPreferencesController(
        'account:one',
        () async => throw StateError('unavailable'),
      );
      await preferences.settled;
      expect(await preferences.toggle('motivation'), isFalse);
      expect(preferences.state.dimensions, contains('motivation'));
      preferences.dispose();
    },
  );

  test(
    'late restore after disposal and signed-out state do not write',
    () async {
      final pending = Completer<SharedPreferences>();
      final preferences = SkillsetDisplayPreferencesController(
        'account:one',
        () => pending.future,
      );
      preferences.dispose();
      pending.complete(await SharedPreferences.getInstance());
      await preferences.settled;
      final signedOut = controller(null);
      expect(await signedOut.toggle('motivation'), isFalse);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      signedOut.dispose();
    },
  );
}
