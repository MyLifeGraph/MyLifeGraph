import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../domain/app_session.dart';
import '../providers/auth_providers.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _nameController = TextEditingController();
  final List<_TimetableBlockController> _blocks = [
    _TimetableBlockController.defaults(),
  ];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final session = authState.valueOrNull;

    if (session != null && _nameController.text.isEmpty) {
      _nameController.text =
          session.profile.isGuest ? '' : session.profile.name;
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.md : AppSpacing.xl,
                AppSpacing.lg,
                compact ? AppSpacing.md : AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PERSONAL COACH',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 4,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Build your day-aware coach',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Add the important blocks manually now. You can edit this later in Settings.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _OnboardingColors.muted(context),
                          height: 1.55,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _OnboardingSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your profile',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Name optional',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _OnboardingSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your timetable',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Subjects, activities and fixed blocks.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color:
                                              _OnboardingColors.muted(context),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.calendar_month_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        for (var index = 0; index < _blocks.length; index++)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _TimetableBlockForm(
                              controller: _blocks[index],
                              canRemove: _blocks.length > 1,
                              onRemove: () => _removeBlock(index),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _addBlock,
                            icon: const Icon(Icons.add),
                            label: const Text('Add another block'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _OnboardingSurface(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFFA72F).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.schedule,
                            color: Color(0xFFFFA72F),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Why this matters',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'The timetable becomes context for stress alerts, focus blocks, and recovery suggestions.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: _OnboardingColors.muted(context),
                                      height: 1.45,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving...' : 'Enter app'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: TextButton(
                      onPressed: _saving ? null : _skipTimetable,
                      child: const Text('Skip timetable for now'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _addBlock() {
    setState(() => _blocks.add(_TimetableBlockController.defaults()));
  }

  void _removeBlock(int index) {
    final removed = _blocks.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _skipTimetable() async {
    await _complete([]);
  }

  Future<void> _save() async {
    final drafts = _blocks
        .map((block) => block.toDraft())
        .where((draft) => draft.title.trim().isNotEmpty)
        .toList();
    await _complete(drafts);
  }

  Future<void> _complete(List<TimetableDraft> drafts) async {
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).completeOnboarding(
            name: _nameController.text.trim(),
            timetable: drafts,
          );
      if (mounted) {
        context.go(AppRoutes.dashboard);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save onboarding: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _TimetableBlockController {
  _TimetableBlockController({
    required String title,
    required String location,
    required this.weekday,
    required String startsAt,
    required String endsAt,
  })  : titleController = TextEditingController(text: title),
        locationController = TextEditingController(text: location),
        startsAtController = TextEditingController(text: startsAt),
        endsAtController = TextEditingController(text: endsAt);

  factory _TimetableBlockController.defaults() {
    return _TimetableBlockController(
      title: 'Math',
      location: 'Room 204',
      weekday: 1,
      startsAt: '08:15',
      endsAt: '09:45',
    );
  }

  final TextEditingController titleController;
  final TextEditingController locationController;
  final TextEditingController startsAtController;
  final TextEditingController endsAtController;
  int weekday;

  TimetableDraft toDraft() {
    return TimetableDraft(
      title: titleController.text,
      location: locationController.text,
      weekday: weekday,
      startsAt: startsAtController.text,
      endsAt: endsAtController.text,
    );
  }

  void dispose() {
    titleController.dispose();
    locationController.dispose();
    startsAtController.dispose();
    endsAtController.dispose();
  }
}

class _TimetableBlockForm extends StatefulWidget {
  const _TimetableBlockForm({
    required this.controller,
    required this.canRemove,
    required this.onRemove,
  });

  final _TimetableBlockController controller;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  State<_TimetableBlockForm> createState() => _TimetableBlockFormState();
}

class _TimetableBlockFormState extends State<_TimetableBlockForm> {
  static const _weekdays = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _OnboardingColors.row(context),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller.titleController,
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 112,
                child: DropdownButtonFormField<int>(
                  initialValue: widget.controller.weekday,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: _weekdays.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => widget.controller.weekday = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: widget.controller.locationController,
            decoration: const InputDecoration(labelText: 'Room or context'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller.startsAtController,
                  decoration: const InputDecoration(labelText: 'Starts'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: widget.controller.endsAtController,
                  decoration: const InputDecoration(labelText: 'Ends'),
                ),
              ),
            ],
          ),
          if (widget.canRemove) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OnboardingSurface extends StatelessWidget {
  const _OnboardingSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _OnboardingColors.panel(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _OnboardingColors.border(context), width: 2),
      ),
      child: child,
    );
  }
}

class _OnboardingColors {
  const _OnboardingColors._();

  static bool _light(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static Color panel(BuildContext context) =>
      _light(context) ? Colors.white : const Color(0xFF122329);

  static Color row(BuildContext context) =>
      _light(context) ? const Color(0xFFEAF1F0) : const Color(0xFF202B32);

  static Color border(BuildContext context) =>
      _light(context) ? const Color(0xFFD4E1DF) : const Color(0xFF2A424A);

  static Color muted(BuildContext context) =>
      _light(context) ? const Color(0xFF607078) : const Color(0xFFA8B5BE);
}
