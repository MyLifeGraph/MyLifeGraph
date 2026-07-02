import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../data/datasources/daily_check_in_supabase_data_source.dart';

class DailyCheckInPage extends ConsumerStatefulWidget {
  const DailyCheckInPage({super.key});

  @override
  ConsumerState<DailyCheckInPage> createState() => _DailyCheckInPageState();
}

class _DailyCheckInPageState extends ConsumerState<DailyCheckInPage> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd.MM.yyyy').format(DateTime.now());

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            sliver: SliverList.list(
              children: [
                _InputHeader(
                  label: 'INPUT LAYER',
                  title: 'Daily Check-In',
                  subtitle:
                      'Save sleep, mood, energy, activity and reflection as context for the coach.',
                  icon: Icons.fact_check_outlined,
                  onBack: context.pop,
                ),
                const SizedBox(height: AppSpacing.xl),
                _FormPanel(
                  children: [
                    _LabeledField(
                      label: 'Date',
                      value: date,
                      icon: Icons.calendar_today,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _DropdownLike(label: 'Mood', value: 'Good'),
                    const SizedBox(height: AppSpacing.lg),
                    const _LabeledField(label: 'Stress 1-10', value: '4'),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: 1.08,
                  children: const [
                    _SmallInputCard(
                      icon: Icons.nightlight_round,
                      label: 'Sleep hours',
                      value: '7,2',
                    ),
                    _SmallInputCard(
                      icon: Icons.directions_walk,
                      label: 'Steps',
                      value: '8200',
                    ),
                    _SmallInputCard(
                      icon: Icons.phone_android,
                      label: 'Screen time',
                      value: '4,5',
                    ),
                    _SmallInputCard(
                      icon: Icons.timer_outlined,
                      label: 'Focus minutes',
                      value: '90',
                    ),
                    _SmallInputCard(
                      icon: Icons.monitor_heart_outlined,
                      label: 'Activity 1-10',
                      value: '6',
                    ),
                    _SmallInputCard(
                      icon: Icons.battery_5_bar_outlined,
                      label: 'Energy 1-10',
                      value: '6',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const _FormPanel(
                  children: [
                    _LabeledField(label: 'Sleep quality 1-10', value: '7'),
                    SizedBox(height: AppSpacing.lg),
                    _LabeledField(label: 'Workout minutes', value: '25'),
                    SizedBox(height: AppSpacing.lg),
                    _LabeledField(
                      label: 'Day focus',
                      value: 'One thing that would make today successful',
                      icon: Icons.adjust,
                    ),
                    SizedBox(height: AppSpacing.lg),
                    _LabeledField(
                      label: 'Nutrition',
                      value: 'Balanced, late meals, high protein, skipped meal',
                    ),
                    SizedBox(height: AppSpacing.lg),
                    _LabeledField(
                      label: 'Reflection',
                      value: 'What affected your energy, mood, or focus today?',
                      maxLines: 4,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveCheckIn,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isSaving ? 'Saving...' : 'Save check-in'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCheckIn() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      _showMessage('Supabase is not configured.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await DailyCheckInSupabaseDataSource(client).saveDefaultCheckIn();
      await ref
          .read(snapshotRefreshServiceProvider)
          .refreshDailyAfterUserSignal();
      if (mounted) {
        _showMessage('Daily Check-In saved to Supabase.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not save yet. Check RLS policies for daily logs.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _InputHeader extends StatelessWidget {
  const _InputHeader({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
  });

  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 4,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 48,
                      height: 1,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFA8B5BE),
                      height: 1.55,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF15242A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF2A424A), width: 2),
          ),
          child: IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _InputPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SmallInputCard extends StatelessWidget {
  const _SmallInputCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _InputPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child:
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          const Spacer(),
          _FieldBox(value: value),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.value,
    this.icon,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final IconData? icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _FieldBox(value: value, maxLines: maxLines),
      ],
    );
  }
}

class _DropdownLike extends StatelessWidget {
  const _DropdownLike({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        _FieldBox(value: value, trailing: Icons.keyboard_arrow_down),
      ],
    );
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({
    required this.value,
    this.trailing,
    this.maxLines = 1,
  });

  final String value;
  final IconData? trailing;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: maxLines > 1 ? 140 : 58),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1218),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF303B47), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment:
            maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFEFF4F6),
                  ),
            ),
          ),
          if (trailing != null) Icon(trailing),
        ],
      ),
    );
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel({
    required this.child,
    required this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF122329),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2A424A), width: 2),
      ),
      child: child,
    );
  }
}
