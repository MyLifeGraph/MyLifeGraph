import 'package:flutter/material.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/app_feature_palette.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_surface.dart';
import 'blocking_screen_preview.dart';

class BlockingCustomEditor extends StatefulWidget {
  const BlockingCustomEditor({
    super.key,
    required this.custom,
    required this.iconBuilder,
    required this.onSave,
    required this.error,
    this.strictEnabled = false,
  });
  final bool strictEnabled;
  final Map<String, Object> custom;
  final IconData Function(String) iconBuilder;
  final Future<bool> Function(Map<String, Object>) onSave;
  final String? Function() error;
  @override
  State<BlockingCustomEditor> createState() => _BlockingCustomEditorState();
}

class _BlockingCustomEditorState extends State<BlockingCustomEditor> {
  late final _title = TextEditingController(
    text: widget.custom['title'] as String? ?? 'Stay focused',
  );
  late final _message = TextEditingController(
    text:
        widget.custom['message'] as String? ??
        'Take a breath. Choose your next step.',
  );
  late String _icon = widget.custom['icon'] as String? ?? 'shield';
  late String _tone = widget.custom['tone'] as String? ?? 'glass';
  late String _accent = widget.custom['accent'] as String? ?? 'theme';
  late String _layout = widget.custom['layout'] as String? ?? 'balanced';
  late int _wait = widget.custom['waitSeconds'] as int? ?? 0;
  bool _saving = false;
  String? _error;
  Map<String, Object> get _draft => {
    ...widget.custom,
    'title': _title.text.trim(),
    'message': _message.text.trim(),
    'icon': _icon,
    'tone': _tone,
    'accent': _accent,
    'layout': _layout,
    'waitSeconds': _wait,
  };
  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Block screen',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(AppIcons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      SizedBox(
                        height: 250,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: 360,
                            height: 400,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadii.xl),
                              child: BlockingScreenPreview(
                                custom: _draft,
                                counters: const {'today': 0, 'total': 0},
                                strictLocked: widget.strictEnabled,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final id in [
                            'shield',
                            'work',
                            'games',
                            'social',
                            'sleep',
                            'study',
                          ])
                            Semantics(
                              selected: _icon == id,
                              child: IconButton.filledTonal(
                                tooltip: id,
                                onPressed: () => setState(() => _icon = id),
                                style: IconButton.styleFrom(
                                  backgroundColor: _icon == id
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                      : Colors.transparent,
                                ),
                                icon: Icon(widget.iconBuilder(id)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _title,
                        readOnly: _saving,
                        maxLength: 60,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      TextField(
                        controller: _message,
                        readOnly: _saving,
                        maxLength: 200,
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Message'),
                      ),
                      Text(
                        'Accent',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Row(
                        key: const ValueKey('blocking-accent-options'),
                        children: [
                          for (final (id, color) in [
                            ('theme', Theme.of(context).colorScheme.primary),
                            ('mint', AppFeaturePalette.mint),
                            ('blue', AppFeaturePalette.blue),
                            ('violet', AppFeaturePalette.violet),
                            ('rose', AppFeaturePalette.rose),
                          ])
                            Expanded(
                              child: Semantics(
                                selected: _accent == id,
                                child: IconButton(
                                  constraints: const BoxConstraints(
                                    minHeight: 48,
                                  ),
                                  tooltip: id,
                                  onPressed: () => setState(() => _accent = id),
                                  icon: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      if (_accent == id)
                                        const Icon(
                                          AppIcons.check,
                                          size: 19,
                                          color: AppFeaturePalette.onAccent,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final scale =
                              MediaQuery.textScalerOf(context).scale(14) / 14;
                          final columns = constraints.maxWidth >= 300 * scale
                              ? 3
                              : 1;
                          final width =
                              (constraints.maxWidth - 8 * (columns - 1)) /
                              columns;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final id in [
                                'compact',
                                'balanced',
                                'spacious',
                              ])
                                SizedBox(
                                  width: width,
                                  child: ChoiceChip(
                                    showCheckmark: false,
                                    label: SizedBox(
                                      width: double.infinity,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            height: 52,
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  widget.iconBuilder(_icon),
                                                  size: 20,
                                                ),
                                                SizedBox(
                                                  height: id == 'compact'
                                                      ? 3
                                                      : id == 'balanced'
                                                      ? 7
                                                      : 11,
                                                ),
                                                Container(
                                                  width: 32,
                                                  height: 3,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                                const SizedBox(height: 4),
                                                Container(
                                                  width: 20,
                                                  height: 3,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.outline,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            id[0].toUpperCase() +
                                                id.substring(1),
                                          ),
                                        ],
                                      ),
                                    ),
                                    selected: _layout == id,
                                    onSelected: (_) =>
                                        setState(() => _layout = id),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _tone,
                        decoration: const InputDecoration(
                          labelText: 'Background',
                        ),
                        items: [
                          for (final (id, label) in [
                            ('glass', 'Liquid Glass'),
                            ('dark', 'Dark'),
                            ('light', 'Light'),
                            ('space', 'Space'),
                          ])
                            DropdownMenuItem(value: id, child: Text(label)),
                        ],
                        onChanged: (value) => setState(() => _tone = value!),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Return delay',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final seconds in [1, 3, 5, 10, 15])
                            ChoiceChip(
                              showCheckmark: false,
                              label: Text('${seconds}s'),
                              selected: _wait == seconds,
                              onSelected: (_) =>
                                  setState(() => _wait = seconds),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        key: ValueKey(_wait),
                        initialValue: _wait,
                        decoration: const InputDecoration(
                          labelText: 'More delays',
                        ),
                        items: [
                          for (final seconds in [
                            0,
                            1,
                            3,
                            5,
                            10,
                            15,
                            20,
                            60,
                            180,
                            300,
                            600,
                            900,
                          ])
                            DropdownMenuItem(
                              value: seconds,
                              child: Text(
                                seconds == 0
                                    ? 'Immediately'
                                    : seconds < 60
                                    ? '${seconds}s'
                                    : '${seconds ~/ 60}m',
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _wait = value!),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                ),
              ),
              AppSurface(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Semantics(liveRegion: true, child: Text(_error!)),
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _saving = true;
                                _error = null;
                              });
                              final saved = await widget.onSave(_draft);
                              if (!context.mounted) return;
                              if (saved) {
                                Navigator.pop(context);
                              } else {
                                setState(() {
                                  _saving = false;
                                  _error =
                                      widget.error() ??
                                      'Could not save. Try again.';
                                });
                              }
                            },
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
