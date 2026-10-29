import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_target_list.dart';

void main() {
  for (final variableHeight in [false, true]) {
    testWidgets(
      'mixed target selections keep visible anchors; varied=$variableHeight',
      (t) async {
        final random = Random(202610291837);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final ids = List.generate(80, (i) => 'site-$i.example');
        final selected = <String>{};
        var source = ids;
        var shown = true;
        late StateSetter update;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 320,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      if (!shown) return const SizedBox();
                      return BlockingTargetList(
                        ids: source,
                        selected: selected,
                        controller: controller,
                        listKey: const ValueKey('list'),
                        onChanged: (id, checked) => setState(() {
                          checked ? selected.add(id) : selected.remove(id);
                        }),
                        itemBuilder: (id, change) => SizedBox(
                          key: ValueKey(id),
                          height: variableHeight
                              ? 48 + ids.indexOf(id) % 3 * 18
                              : 56,
                          child: CheckboxListTile(
                            title: Text(id),
                            value: selected.contains(id),
                            onChanged: (checked) => change(checked!),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        for (var step = 0; step < 50; step++) {
          final max = controller.position.maxScrollExtent;
          controller.jumpTo(max * (.15 + random.nextDouble() * .65));
          await t.pumpAndSettle();
          final viewport = t.getRect(find.byKey(const ValueKey('list')));
          final visible =
              source.where((id) {
                final rect = t.getRect(find.byKey(ValueKey(id)));
                return rect.top >= viewport.top &&
                    rect.bottom <= viewport.bottom;
              }).toList()..sort(
                (a, b) => t
                    .getTopLeft(find.byKey(ValueKey(a)))
                    .dy
                    .compareTo(t.getTopLeft(find.byKey(ValueKey(b))).dy),
              );
          expect(visible.length, greaterThanOrEqualTo(2));
          final anchor = find.byKey(ValueKey(visible.first));
          final before = t.getTopLeft(anchor).dy;
          // Preserve one physically visible anchor; select/deselect the other
          // rows before layout, not merely items adjacent in the source array.
          for (final id in visible.skip(1).take(1 + random.nextInt(3))) {
            await t.tap(find.byKey(ValueKey(id)));
          }
          await t.pumpAndSettle();
          expect(
            t.getTopLeft(anchor).dy,
            closeTo(before, .5),
            reason: 'step=$step',
          );
          final list = t.widget<BlockingTargetList>(
            find.byType(BlockingTargetList),
          );
          expect(list.orderedIds, [
            ...source.where(selected.contains),
            ...source.where((id) => !selected.contains(id)),
          ]);
          expect(t.takeException(), isNull, reason: 'step=$step');
        }
        // Search replacement and removal of the widget can overtake a queued
        // selection callback. Neither may access disposed scroll/layout state.
        controller.jumpTo(0);
        await t.pumpAndSettle();
        final first = t
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds
            .first;
        await t.tap(find.byKey(ValueKey(first)));
        update(() => source = <String>[]);
        await t.pumpAndSettle();
        expect(controller.position.maxScrollExtent, 0);
        update(() => source = ids);
        await t.pumpAndSettle();
        final next = t
            .widget<BlockingTargetList>(find.byType(BlockingTargetList))
            .orderedIds
            .first;
        await t.tap(find.byKey(ValueKey(next)));
        update(() => shown = false);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
