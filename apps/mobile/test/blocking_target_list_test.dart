import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_target_list.dart';

void main() {
  for (final count in [25, 250]) {
    testWidgets('$count targets: immediate partition and stable viewport', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final ids = List.generate(count, (i) => 'target-$i');
      final selected = <String>{};
      final list = GlobalKey<BlockingTargetListState>();
      late StateSetter updateList;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 300,
                child: StatefulBuilder(
                  builder: (context, update) {
                    updateList = update;
                    return BlockingTargetList(
                      key: list,
                      ids: ids,
                      selected: selected,
                      controller: controller,
                      listKey: const ValueKey('targets'),
                      itemBuilder: (id, change) => CheckboxListTile(
                        key: ValueKey(id),
                        title: Text(id),
                        value: selected.contains(id),
                        onChanged: (value) => change(value!),
                      ),
                      onChanged: (id, value) => update(() {
                        value ? selected.add(id) : selected.remove(id);
                      }),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(560);
      await tester.pumpAndSettle();
      final anchor = find.byKey(const ValueKey('target-11'));
      final before = tester.getTopLeft(anchor).dy;
      await tester.tap(find.byKey(const ValueKey('target-12')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds
            .first,
        'target-12',
      );
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .5));
      expect(controller.offset, greaterThan(0));
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('target-12')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds,
        ids,
      );
      expect(controller.offset, 0);
      controller.jumpTo(560);
      await tester.pumpAndSettle();
      final bulkBefore = tester.getTopLeft(anchor).dy;
      final moved = ids.skip(14).toSet();
      list.currentState!.preserveViewport(
        () => updateList(() => selected.addAll(moved)),
        moved: moved,
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, closeTo(bulkBefore, .5));
      list.currentState!.preserveViewport(
        () => updateList(selected.clear),
        moved: moved,
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, closeTo(bulkBefore, .5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
