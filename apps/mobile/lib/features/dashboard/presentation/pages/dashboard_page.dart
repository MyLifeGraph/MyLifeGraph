import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../optimization/domain/entities/recommendation.dart';
import '../../../optimization/presentation/providers/optimization_providers.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import '../providers/dashboard_providers.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final Set<String> _expandedTaskIds = {};
  final Set<String> _completedTaskIds = {};
  final Set<String> _deletedTaskIds = {};
  bool _isCompletedHistoryExpanded = true;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    final recommendations =
        ref.watch(recommendationsProvider).valueOrNull ?? [];

    return AsyncValueView(
      value: snapshot,
      data: (data) => _DashboardHome(
        snapshot: data,
        recommendations: recommendations,
        expandedTaskIds: _expandedTaskIds,
        completedTaskIds: _completedTaskIds,
        deletedTaskIds: _deletedTaskIds,
        isCompletedHistoryExpanded: _isCompletedHistoryExpanded,
        onToggleTask: _toggleTask,
        onCompleteTask: _completeTask,
        onRestoreTask: _restoreTask,
        onDeleteTask: _deleteTask,
        onToggleCompletedHistory: () {
          setState(() {
            _isCompletedHistoryExpanded = !_isCompletedHistoryExpanded;
          });
        },
      ),
    );
  }

  void _toggleTask(String id) {
    setState(() {
      if (!_expandedTaskIds.add(id)) {
        _expandedTaskIds.remove(id);
      }
    });
  }

  void _completeTask(String id) {
    setState(() {
      _completedTaskIds.add(id);
      _expandedTaskIds.remove(id);
    });
    _updateTaskStatus(id, 'DONE');
  }

  void _restoreTask(String id) {
    setState(() {
      _completedTaskIds.remove(id);
      _deletedTaskIds.remove(id);
    });
    _updateTaskStatus(id, 'TODO');
  }

  void _deleteTask(String id) {
    setState(() {
      _deletedTaskIds.add(id);
      _completedTaskIds.remove(id);
      _expandedTaskIds.remove(id);
    });
    _updateTaskStatus(id, 'CANCELLED');
  }

  Future<void> _updateTaskStatus(String id, String status) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      return;
    }
    try {
      await client.from(SupabaseTables.tasks).update({
        'status': status,
        'updatedAt': DateTime.now().toIso8601String(),
      }).eq('id', id);
      ref.invalidate(dashboardSnapshotProvider);
    } catch (_) {
      return;
    }
  }
}

class _DashboardHome extends StatelessWidget {
  const _DashboardHome({
    required this.snapshot,
    required this.recommendations,
    required this.expandedTaskIds,
    required this.completedTaskIds,
    required this.deletedTaskIds,
    required this.isCompletedHistoryExpanded,
    required this.onToggleTask,
    required this.onCompleteTask,
    required this.onRestoreTask,
    required this.onDeleteTask,
    required this.onToggleCompletedHistory,
  });

  final DashboardSnapshot snapshot;
  final List<Recommendation> recommendations;
  final Set<String> expandedTaskIds;
  final Set<String> completedTaskIds;
  final Set<String> deletedTaskIds;
  final bool isCompletedHistoryExpanded;
  final ValueChanged<String> onToggleTask;
  final ValueChanged<String> onCompleteTask;
  final ValueChanged<String> onRestoreTask;
  final ValueChanged<String> onDeleteTask;
  final VoidCallback onToggleCompletedHistory;

  @override
  Widget build(BuildContext context) {
    final tasks = _tasksFromSnapshot(snapshot, recommendations);
    final upcomingTasks = tasks
        .where((task) => !completedTaskIds.contains(task.id))
        .where((task) => !deletedTaskIds.contains(task.id))
        .toList();
    final completedTasks = tasks
        .where((task) => completedTaskIds.contains(task.id))
        .where((task) => !deletedTaskIds.contains(task.id))
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 520;
        final pagePadding = isMobile ? AppSpacing.md : AppSpacing.lg;

        return SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  isMobile ? AppSpacing.sm : AppSpacing.md,
                  pagePadding,
                  AppSpacing.xl,
                ),
                sliver: SliverList.list(
                  children: [
                    _DashboardHeader(isMobile: isMobile),
                    SizedBox(height: isMobile ? AppSpacing.md : AppSpacing.lg),
                    _WellnessScoreCard(
                      snapshot: snapshot,
                      isMobile: isMobile,
                    ),
                    SizedBox(height: isMobile ? AppSpacing.md : AppSpacing.lg),
                    _StatsGrid(snapshot: snapshot, isMobile: isMobile),
                    SizedBox(height: isMobile ? AppSpacing.md : AppSpacing.lg),
                    _ScheduleCard(snapshot: snapshot, isMobile: isMobile),
                    const SizedBox(height: AppSpacing.lg),
                    _SectionHeader(
                      title: 'Upcoming',
                      trailing: 'Swipe left to delete',
                      isMobile: isMobile,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (upcomingTasks.isEmpty)
                      const _EmptyStateCard(message: 'No upcoming items.')
                    else
                      ...upcomingTasks.map(
                        (task) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _SwipeTaskCard(
                            task: task,
                            isExpanded: expandedTaskIds.contains(task.id),
                            isMobile: isMobile,
                            onTap: () => onToggleTask(task.id),
                            onComplete: () => onCompleteTask(task.id),
                            onDelete: () => onDeleteTask(task.id),
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    _CompletedHistoryCard(
                      completedTasks: completedTasks,
                      isExpanded: isCompletedHistoryExpanded,
                      onToggleExpanded: onToggleCompletedHistory,
                      onRestore: onRestoreTask,
                      onDelete: onDeleteTask,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_DashboardTask> _tasksFromSnapshot(
    DashboardSnapshot snapshot,
    List<Recommendation> recommendations,
  ) {
    final prepareHints = recommendations
        .map((recommendation) => recommendation.reason)
        .take(2)
        .toList();

    return snapshot.todayPlan.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final priority = switch (item.type.toLowerCase()) {
        'focus' => 'high priority',
        'movement' => 'medium priority',
        _ => 'normal priority',
      };

      return _DashboardTask(
        id: item.id,
        title: item.title,
        meta: '${DateFormat('M/d/yyyy').format(DateTime.now())} - $priority',
        icon: _iconForPlanType(item.type),
        description:
            '${item.time} ${item.type} block. ${prepareHints.isEmpty ? 'Use this moment to protect your next useful action.' : prepareHints[index % prepareHints.length]}',
        checklist: const [
          'Break it into one next action.',
          'Reserve a protected focus block if it feels heavy.',
          'Check whether this conflicts with your timetable.',
        ],
      );
    }).toList();
  }

  IconData _iconForPlanType(String type) {
    return switch (type.toLowerCase()) {
      'focus' => Icons.center_focus_strong,
      'nutrition' => Icons.restaurant_outlined,
      'movement' => Icons.directions_walk,
      _ => Icons.task_alt_outlined,
    };
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('EEEE, MMMM d').format(DateTime.now());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Hey there',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: isMobile ? 30 : null,
                    ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _DashboardColors.iconTile(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _DashboardColors.border(context)),
              ),
              child: IconButton(
                tooltip: 'Settings',
                onPressed: () => context.go(AppRoutes.settings),
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF8F3D),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WellnessScoreCard extends StatelessWidget {
  const _WellnessScoreCard({
    required this.snapshot,
    required this.isMobile,
  });

  final DashboardSnapshot snapshot;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final heroTextColor = _DashboardColors.onHero(context);
    final heroMutedColor = _DashboardColors.onHeroMuted(context);
    final miniTiles = [
      _MiniMetric(
        'Mood',
        '${_average(snapshot.energyTrend)}',
        Icons.mood_outlined,
      ),
      _MiniMetric('Energy', '${snapshot.energyTrend.last}', Icons.bolt),
      _MiniMetric('Focus', '${snapshot.focusMinutesToday}m', Icons.timer),
      _MiniMetric('Sleep', '${snapshot.recoveryScore}', Icons.bedtime_outlined),
    ];

    return Container(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _DashboardColors.heroGradient(context),
        ),
        border: Border.all(color: _DashboardColors.heroBorder(context)),
        boxShadow: [
          BoxShadow(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: -12,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Today\'s wellness score',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: heroTextColor,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: _DashboardColors.heroPill(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${snapshot.streakDays} day streak',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: heroTextColor,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${snapshot.optimizationScore}',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: isMobile ? 48 : 56,
                        color: heroTextColor,
                      ),
                ),
                TextSpan(
                  text: ' /100',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: heroMutedColor,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;
              final gap = compact ? AppSpacing.xs : AppSpacing.sm;

              return SizedBox(
                height: compact ? 82 : 94,
                child: Row(
                  children: [
                    for (var index = 0; index < miniTiles.length; index++) ...[
                      if (index > 0) SizedBox(width: gap),
                      Expanded(
                        child: _WellnessMiniTile(
                          metric: miniTiles[index],
                          isCompact: compact,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  int _average(List<int> values) {
    if (values.isEmpty) {
      return 0;
    }
    return (values.reduce((a, b) => a + b) / values.length).round();
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.snapshot,
    required this.isMobile,
  });

  final DashboardSnapshot snapshot;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatMetric(
        icon: Icons.directions_walk,
        title: 'Steps',
        value: '${snapshot.optimizationScore * 100}',
        trend: _trend(snapshot.energyTrend),
        color: const Color(0xFF5BE7C4),
      ),
      _StatMetric(
        icon: Icons.bedtime_outlined,
        title: 'Sleep',
        value: '${(snapshot.recoveryScore / 10).toStringAsFixed(1)}h',
        trend: _trend(snapshot.energyTrend.reversed.toList()),
        color: const Color(0xFF8EA7FF),
      ),
      _StatMetric(
        icon: Icons.phone_android,
        title: 'Screen Time',
        value:
            '${((240 - snapshot.focusMinutesToday).clamp(60, 360) / 60).toStringAsFixed(1)}h',
        trend: '-${(snapshot.focusMinutesToday / 30).clamp(1, 9).round()}%',
        color: const Color(0xFFFFC857),
      ),
      _StatMetric(
        icon: Icons.water_drop_outlined,
        title: 'Hydration',
        value: '${(snapshot.optimizationScore / 40).toStringAsFixed(1)}L',
        trend: '+${(snapshot.recoveryScore / 12).round()}%',
        color: const Color(0xFFFF8F70),
      ),
    ];

    if (isMobile) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 1,
        children: stats.map((stat) => _StatCard(metric: stat)).toList(),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.16,
      children: stats.map((stat) => _StatCard(metric: stat)).toList(),
    );
  }

  String _trend(List<int> values) {
    if (values.length < 2) {
      return '0%';
    }
    final diff = values.last - values.first;
    final prefix = diff >= 0 ? '+' : '';
    return '$prefix$diff%';
  }
}

class _ScheduleCard extends StatefulWidget {
  const _ScheduleCard({
    required this.snapshot,
    required this.isMobile,
  });

  final DashboardSnapshot snapshot;
  final bool isMobile;

  @override
  State<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<_ScheduleCard> {
  final PageController _pageController = PageController();
  int _selectedDays = 1;
  int _pageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final trend = widget.snapshot.energyTrend;
    final days = List.generate(
      7,
      (index) {
        final value = index < trend.length ? trend[index] : 0;
        final date = monday.add(Duration(days: index));
        return _ScheduleDay(
          DateFormat('E').format(date),
          DateFormat('MMM d').format(date),
          (value / 100).clamp(0.08, 1),
          (widget.snapshot.recoveryScore / 100).clamp(0.08, 1),
          value,
        );
      },
    );
    final pageCount = _selectedDays == 7
        ? 1
        : (days.length / _selectedDays).ceil().clamp(1, 99);
    final selectedWindow = _windowForPage(days);
    final activityScore = selectedWindow.isEmpty
        ? 0
        : (selectedWindow.map((day) => day.activity).reduce((a, b) => a + b) /
                selectedWindow.length)
            .round();
    final windowHeight = switch (_selectedDays) {
      1 => 330.0,
      2 => 300.0,
      3 => 300.0,
      _ => 210.0,
    };

    return _RoundedPanel(
      padding: EdgeInsets.all(widget.isMobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Schedule',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Classes, study blocks and activity score',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              _DayDropdown(
                value: _selectedDays,
                onChanged: _changeSelectedDays,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: widget.isMobile ? windowHeight : windowHeight - 16,
            child: ScrollConfiguration(
              behavior: const _ScheduleDragScrollBehavior(),
              child: PageView.builder(
                controller: _pageController,
                itemCount: pageCount,
                onPageChanged: (index) {
                  setState(() => _pageIndex = index);
                },
                itemBuilder: (context, index) {
                  final window = _windowForPage(days, page: index);
                  return _ScheduleWindow(
                    days: window,
                    selectedDays: _selectedDays,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              pageCount,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: index == _pageIndex ? 34 : 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: index == _pageIndex
                      ? Theme.of(context).colorScheme.primary
                      : _DashboardColors.pill(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.32),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity score',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Average across selected days',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Text(
                  '$activityScore',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _changeSelectedDays(int days) {
    setState(() {
      _selectedDays = days;
      _pageIndex = 0;
    });
    _pageController.jumpToPage(0);
  }

  List<_ScheduleDay> _windowForPage(List<_ScheduleDay> days, {int? page}) {
    if (_selectedDays == 7) {
      return days.take(7).toList();
    }
    final index = page ?? _pageIndex;
    final start = index * _selectedDays;
    if (start >= days.length) {
      return const [];
    }
    final end = (start + _selectedDays).clamp(0, days.length);
    return days.sublist(start, end);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.trailing,
    required this.isMobile,
  });

  final String title;
  final String trailing;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(trailing, style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text(trailing, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _SwipeTaskCard extends StatelessWidget {
  const _SwipeTaskCard({
    required this.task,
    required this.isExpanded,
    required this.isMobile,
    required this.onTap,
    required this.onComplete,
    required this.onDelete,
  });

  final _DashboardTask task;
  final bool isExpanded;
  final bool isMobile;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('upcoming-${task.id}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {
        DismissDirection.endToStart: 0.34,
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.md),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B6B).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.34),
          ),
        ),
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B6B),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, color: Colors.black),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: _TaskCard(
        task: task,
        isExpanded: isExpanded,
        isMobile: isMobile,
        onTap: onTap,
        onMarkDone: onComplete,
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.isExpanded,
    required this.isMobile,
    required this.onTap,
    required this.onMarkDone,
  });

  final _DashboardTask task;
  final bool isExpanded;
  final bool isMobile;
  final VoidCallback onTap;
  final VoidCallback onMarkDone;

  @override
  Widget build(BuildContext context) {
    return _RoundedPanel(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.all(isMobile ? AppSpacing.sm : AppSpacing.md),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      task.icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          task.meta,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: _TaskExpandedContent(
                  task: task,
                  onMarkDone: onMarkDone,
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 180),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskExpandedContent extends StatelessWidget {
  const _TaskExpandedContent({
    required this.task,
    required this.onMarkDone,
  });

  final _DashboardTask task;
  final VoidCallback onMarkDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _DashboardColors.button(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Text(
            'PREPARE',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...task.checklist.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onMarkDone,
              child: const Text('Mark done'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedHistoryCard extends StatelessWidget {
  const _CompletedHistoryCard({
    required this.completedTasks,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onRestore,
    required this.onDelete,
  });

  final List<_DashboardTask> completedTasks;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onRestore;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return _RoundedPanel(
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggleExpanded,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Completed History',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${completedTasks.length} completed tasks',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: completedTasks.isEmpty
                  ? const _CompletedEmptyState()
                  : Column(
                      children: completedTasks
                          .map(
                            (task) => _CompletedTaskRow(
                              task: task,
                              onRestore: () => onRestore(task.id),
                              onDelete: () => onDelete(task.id),
                            ),
                          )
                          .toList(),
                    ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _CompletedTaskRow extends StatelessWidget {
  const _CompletedTaskRow({
    required this.task,
    required this.onRestore,
    required this.onDelete,
  });

  final _DashboardTask task;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: _DashboardColors.button(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF5BE7C4)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child:
                Text(task.title, style: Theme.of(context).textTheme.bodyLarge),
          ),
          IconButton(
            tooltip: 'Restore',
            onPressed: onRestore,
            icon: const Icon(Icons.restore),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _DashboardColors {
  const _DashboardColors._();

  static bool _light(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static Color panel(BuildContext context) =>
      _light(context) ? const Color(0xFFFFFFFF) : const Color(0xFF121720);

  static Color row(BuildContext context) =>
      _light(context) ? const Color(0xFFEAF1F0) : const Color(0xFF202B32);

  static Color button(BuildContext context) =>
      _light(context) ? const Color(0xFFF7FAFA) : const Color(0xFF0D121A);

  static Color border(BuildContext context) =>
      _light(context) ? const Color(0xFFD4E1DF) : const Color(0xFF242B38);

  static Color iconTile(BuildContext context) =>
      _light(context) ? const Color(0xFFFFFFFF) : const Color(0xFF151A24);

  static Color pill(BuildContext context) =>
      _light(context) ? const Color(0xFFDDE8E6) : const Color(0xFF2A323C);

  static Color mutedText(BuildContext context) =>
      _light(context) ? const Color(0xFF607078) : const Color(0xFFA8B5BE);

  static Color heroBorder(BuildContext context) =>
      _light(context) ? const Color(0xFFB8D9D2) : const Color(0xFF294048);

  static Color onHero(BuildContext context) =>
      _light(context) ? const Color(0xFF0D1B22) : Colors.white;

  static Color onHeroMuted(BuildContext context) =>
      _light(context) ? const Color(0xFF607078) : const Color(0xFFA5B0C0);

  static Color heroPill(BuildContext context) =>
      _light(context) ? const Color(0xFFD8F2EC) : const Color(0xFF202837);

  static Color heroTile(BuildContext context) => _light(context)
      ? Colors.white.withValues(alpha: 0.72)
      : Colors.white.withValues(alpha: 0.06);

  static List<Color> heroGradient(BuildContext context) => _light(context)
      ? const [
          Color(0xFFE9FBF6),
          Color(0xFFF8FCFB),
          Color(0xFFDFF4EF),
        ]
      : const [
          Color(0xFF172A2D),
          Color(0xFF10151F),
          Color(0xFF121822),
        ];
}

class _RoundedPanel extends StatelessWidget {
  const _RoundedPanel({
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _DashboardColors.panel(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _DashboardColors.border(context)),
      ),
      child: child,
    );
  }
}

class _WellnessMiniTile extends StatelessWidget {
  const _WellnessMiniTile({
    required this.metric,
    this.isCompact = false,
  });

  final _MiniMetric metric;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      padding: EdgeInsets.all(isCompact ? AppSpacing.xs : AppSpacing.sm),
      decoration: BoxDecoration(
        color: _DashboardColors.heroTile(context),
        borderRadius: BorderRadius.circular(isCompact ? 14 : 18),
      ),
      child: isCompact
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  metric.icon,
                  size: 18,
                  color: _DashboardColors.onHero(context),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    metric.value,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: _DashboardColors.onHero(context),
                          fontSize: 13,
                        ),
                  ),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    metric.label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _DashboardColors.onHeroMuted(context),
                        ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  metric.icon,
                  size: 20,
                  color: _DashboardColors.onHero(context),
                ),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    metric.value,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: _DashboardColors.onHero(context),
                        ),
                  ),
                ),
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _DashboardColors.onHeroMuted(context),
                      ),
                ),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.metric});

  final _StatMetric metric;

  @override
  Widget build(BuildContext context) {
    return _RoundedPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, color: metric.color),
              const Spacer(),
              Text(
                metric.trend,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: metric.trend.startsWith('-')
                          ? const Color(0xFFFF8F70)
                          : Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const Spacer(),
          Text(metric.title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(metric.value, style: Theme.of(context).textTheme.headlineMedium),
        ],
      ),
    );
  }
}

class _DayDropdown extends StatelessWidget {
  const _DayDropdown({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Select schedule range',
      initialValue: value,
      color: _DashboardColors.panel(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 1, child: Text('1 day')),
        PopupMenuItem(value: 2, child: Text('2 days')),
        PopupMenuItem(value: 3, child: Text('3 days')),
        PopupMenuItem(value: 7, child: Text('7 days')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _DashboardColors.button(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _DashboardColors.border(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value == 1 ? '1 day' : '$value days',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.keyboard_arrow_down, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ScheduleDragScrollBehavior extends MaterialScrollBehavior {
  const _ScheduleDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class _ScheduleWindow extends StatelessWidget {
  const _ScheduleWindow({
    required this.days,
    required this.selectedDays,
  });

  final List<_ScheduleDay> days;
  final int selectedDays;

  @override
  Widget build(BuildContext context) {
    if (selectedDays == 7) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _CompactScheduleDay(day: day),
              ),
            ),
        ],
      );
    }

    return Container(
      decoration: const BoxDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < selectedDays; index++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: selectedDays == 1 ? 0 : 8,
                ),
                child: index < days.length
                    ? _ScheduleDayPanel(
                        day: days[index],
                        selectedDays: selectedDays,
                      )
                    : const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScheduleDayPanel extends StatelessWidget {
  const _ScheduleDayPanel({
    required this.day,
    required this.selectedDays,
  });

  final _ScheduleDay day;
  final int selectedDays;

  @override
  Widget build(BuildContext context) {
    final compact = selectedDays >= 3;
    final events = day.label == 'Mon'
        ? const [
            ('Math', '08:15-09:45'),
          ]
        : const [
            ('Empty 1', '--:--'),
            ('Empty 2', '--:--'),
          ];

    return Container(
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: _DashboardColors.row(context),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _DashboardColors.mutedText(context),
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final event
              in events.take(selectedDays == 3 ? 2 : events.length))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ScheduleEventTile(
                title: event.$1,
                time: event.$2,
                compact: compact,
              ),
            ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  day.dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                '${day.activity}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (day.activity / 100).clamp(0.03, 1),
              minHeight: compact ? 8 : 10,
              backgroundColor: _DashboardColors.button(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleEventTile extends StatelessWidget {
  const _ScheduleEventTile({
    required this.title,
    required this.time,
    required this.compact,
  });

  final String title;
  final String time;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: _DashboardColors.button(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            time,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CompactScheduleDay extends StatelessWidget {
  const _CompactScheduleDay({required this.day});

  final _ScheduleDay day;

  @override
  Widget build(BuildContext context) {
    final shortLabel = day.label.length > 1 ? '${day.label[0]}.' : day.label;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: _DashboardColors.row(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            shortLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _DashboardColors.mutedText(context),
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: day.energy.clamp(0.25, 1),
                child: Container(
                  width: 30,
                  decoration: BoxDecoration(
                    color: _DashboardColors.button(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'M${(day.movement * 10).round()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (day.activity / 100).clamp(0.03, 1),
              minHeight: 6,
              backgroundColor: _DashboardColors.button(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _RoundedPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _CompletedEmptyState extends StatelessWidget {
  const _CompletedEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _DashboardColors.button(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'No completed items yet.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _DashboardTask {
  const _DashboardTask({
    required this.id,
    required this.title,
    required this.meta,
    required this.icon,
    required this.description,
    required this.checklist,
  });

  final String id;
  final String title;
  final String meta;
  final IconData icon;
  final String description;
  final List<String> checklist;
}

class _MiniMetric {
  const _MiniMetric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _StatMetric {
  const _StatMetric({
    required this.icon,
    required this.title,
    required this.value,
    required this.trend,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String trend;
  final Color color;
}

class _ScheduleDay {
  const _ScheduleDay(
    this.label,
    this.dateLabel,
    this.energy,
    this.movement,
    this.activity,
  );

  final String label;
  final String dateLabel;
  final double energy;
  final double movement;
  final int activity;
}
