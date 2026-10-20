import 'package:flutter/material.dart';

/// Stable partition of the original order, with viewport anchoring on selection.
/// A selection moves the row, never scrolls the reader to the selected group.
class BlockingTargetList extends StatefulWidget {
  const BlockingTargetList({
    required this.ids,
    required this.selected,
    required this.controller,
    required this.listKey,
    required this.itemBuilder,
    required this.onChanged,
    super.key,
  });
  final List<String> ids;
  final Set<String> selected;
  final ScrollController controller;
  final Key listKey;
  final Widget Function(String id, ValueChanged<bool> change) itemBuilder;
  final void Function(String id, bool selected) onChanged;

  List<String> get orderedIds => [
    ...ids.where(selected.contains),
    ...ids.where((id) => !selected.contains(id)),
  ];

  @override
  State<BlockingTargetList> createState() => BlockingTargetListState();
}

class BlockingTargetListState extends State<BlockingTargetList> {
  final _viewport = GlobalKey();
  final _rows = <String, GlobalKey>{};
  int _change = 0;
  double _bottomSlack = 0;

  /// Also used by additive presets/Clear: the same anchor policy as row taps.
  void preserveViewport(VoidCallback change, {Set<String> moved = const {}}) {
    String? anchor;
    double? before;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (widget.controller.hasClients &&
        widget.controller.offset > 0 &&
        viewport is RenderBox) {
      final top = viewport.localToGlobal(Offset.zero).dy;
      final bottom = top + viewport.size.height;
      for (final id in widget.orderedIds) {
        if (moved.contains(id)) continue;
        final row = _rows[id]?.currentContext?.findRenderObject();
        if (row is! RenderBox || !row.attached) continue;
        final y = row.localToGlobal(Offset.zero).dy;
        if (y >= top - .5 && y < bottom) {
          anchor = id;
          before = y;
          break;
        }
      }
    }
    final generation = ++_change;
    change();
    if (anchor == null || before == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _change || !widget.controller.hasClients) {
        return;
      }
      final row = _rows[anchor]?.currentContext?.findRenderObject();
      if (row is! RenderBox || !row.attached) return;
      final delta = row.localToGlobal(Offset.zero).dy - before!;
      final position = widget.controller.position;
      final desired = position.pixels + delta;
      if (desired > position.maxScrollExtent + .1) {
        // A preset may move the anchor close to the new end of the list.
        // Reserve the missing viewport space rather than pulling it upwards.
        setState(() => _bottomSlack += desired - position.maxScrollExtent);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              generation == _change &&
              widget.controller.hasClients) {
            widget.controller.jumpTo(
              desired.clamp(0, widget.controller.position.maxScrollExtent),
            );
          }
        });
        return;
      }
      final offset = desired.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((offset - position.pixels).abs() > .1) {
        widget.controller.jumpTo(offset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.orderedIds;
    final split = ids.indexWhere((id) => !widget.selected.contains(id));
    return Scrollbar(
      key: _viewport,
      controller: widget.controller,
      thumbVisibility: true,
      // The picker is already height-bounded. Keep row layout available across
      // a bulk preset reorder too, even when an anchor moves beyond the lazy
      // viewport cache. Otherwise only single-row moves can be anchored.
      child: SingleChildScrollView(
        key: widget.listKey,
        controller: widget.controller,
        primary: false,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < ids.length; i++) ...[
              if (i == split && split > 0) const Divider(height: 1),
              KeyedSubtree(
                key: _rows.putIfAbsent(ids[i], GlobalKey.new),
                child: widget.itemBuilder(
                  ids[i],
                  (value) => preserveViewport(
                    () => widget.onChanged(ids[i], value),
                    moved: {ids[i]},
                  ),
                ),
              ),
            ],
            if (_bottomSlack > 0) SizedBox(height: _bottomSlack),
          ],
        ),
      ),
    );
  }
}
