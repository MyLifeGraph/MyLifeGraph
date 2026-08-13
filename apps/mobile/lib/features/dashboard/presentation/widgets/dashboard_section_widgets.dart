import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_info_disclosure.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../deadline_plans/domain/exam_plan_health.dart';

typedef TodayInfoHeaderBuilder = Widget Function(
  BuildContext context,
  Widget infoButton,
);

/// Thin Today adapter over the shared, non-persisted information disclosure.
///
/// The description is absent from both the widget and semantics trees while
/// closed. Its control remains independent from any surrounding accordion.
class TodayInfoDisclosure extends StatelessWidget {
  const TodayInfoDisclosure({
    super.key,
    required this.topic,
    required this.description,
    required this.headerBuilder,
    this.descriptionStyle,
  });

  final String topic;
  final String description;
  final TodayInfoHeaderBuilder headerBuilder;
  final TextStyle? descriptionStyle;

  @override
  Widget build(BuildContext context) {
    return AppInfoDisclosure(
      topic: topic,
      description: description,
      descriptionStyle: descriptionStyle,
      layout: AppInfoDisclosureLayout.compact,
      keyPrefix: 'today-info',
      headerBuilder: headerBuilder,
    );
  }
}

class TodayExamPlanHealthSection extends StatelessWidget {
  const TodayExamPlanHealthSection({
    super.key,
    required this.value,
    required this.onRetry,
    required this.onOpenPlan,
  });

  final AsyncValue<ExamPlanHealth?> value;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpenPlan;

  @override
  Widget build(BuildContext context) {
    if (!value.isLoading &&
        !value.hasError &&
        value.hasValue &&
        (value.valueOrNull == null ||
            value.valueOrNull!.needsAttention.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: AppCard(
        key: const ValueKey('today-exam-plan-health'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionTitle(
              title: 'Exam Plan Health',
              subtitle:
                  'Capacity warnings for active Exams. This does not replace the sleep-focused Exam week outlook and never replans automatically.',
            ),
            const SizedBox(height: AppSpacing.md),
            if (value.isLoading)
              const Row(
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Checking current Exam capacity…')),
                ],
              )
            else if (value.hasError)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Exam Plan Health could not be loaded. This transport error is not an Unknown capacity result.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(AppIcons.refresh),
                    label: const Text('Retry Exam Plan Health'),
                  ),
                ],
              )
            else
              Column(
                children: [
                  for (final exam in value.valueOrNull?.needsAttention ??
                      const <ExamPlanHealthItem>[]) ...[
                    ListTile(
                      key: ValueKey('today-exam-health-${exam.planId}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _todayHealthIcon(exam.status),
                        color: _todayHealthColor(context, exam.status),
                      ),
                      title: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(exam.title),
                          AppStatusPill(
                            label: _todayHealthLabel(exam.status),
                            icon: _todayHealthIcon(exam.status),
                            tone: _todayHealthTone(exam.status),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${exam.remainingMinutes} min remaining · '
                        '${exam.minutesToSchedule} min still to place · '
                        '${exam.reserveMinutes == null ? 'reserve unknown' : '${exam.reserveMinutes} min reserve'}',
                      ),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => onOpenPlan(exam.planId),
                    ),
                    if (exam != value.valueOrNull!.needsAttention.last)
                      const Divider(height: AppSpacing.lg),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _todayHealthLabel(ExamPlanHealthStatus status) => switch (status) {
      ExamPlanHealthStatus.green => 'Healthy capacity',
      ExamPlanHealthStatus.yellow => 'Plan soon',
      ExamPlanHealthStatus.red => 'Capacity shortfall',
      ExamPlanHealthStatus.unknown => 'Availability unknown',
    };

IconData _todayHealthIcon(ExamPlanHealthStatus status) => switch (status) {
      ExamPlanHealthStatus.green => AppIcons.checkCircleOutline,
      ExamPlanHealthStatus.yellow => AppIcons.warningAmberOutlined,
      ExamPlanHealthStatus.red => AppIcons.errorOutline,
      ExamPlanHealthStatus.unknown => AppIcons.infoOutline,
    };

AppStatusTone _todayHealthTone(ExamPlanHealthStatus status) => switch (status) {
      ExamPlanHealthStatus.green => AppStatusTone.success,
      ExamPlanHealthStatus.yellow => AppStatusTone.attention,
      ExamPlanHealthStatus.red => AppStatusTone.danger,
      ExamPlanHealthStatus.unknown => AppStatusTone.info,
    };

Color _todayHealthColor(BuildContext context, ExamPlanHealthStatus status) =>
    switch (status) {
      ExamPlanHealthStatus.green => Theme.of(context).colorScheme.primary,
      ExamPlanHealthStatus.yellow => Theme.of(context).colorScheme.tertiary,
      ExamPlanHealthStatus.red => Theme.of(context).colorScheme.error,
      ExamPlanHealthStatus.unknown => Theme.of(context).colorScheme.secondary,
    };

/// Presentation primitives shared only by the independently owned Dashboard
/// sections.
class DashboardSectionTitle extends StatelessWidget {
  const DashboardSectionTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final copy = TodayInfoDisclosure(
      topic: title,
      description: subtitle,
      headerBuilder: (context, infoButton) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          infoButton,
        ],
      ),
    );
    if (trailing == null) return copy;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(16) >= 24;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: AppSpacing.sm),
              trailing!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        );
      },
    );
  }
}

class DashboardStatusPill extends StatelessWidget {
  const DashboardStatusPill({
    super.key,
    required this.icon,
    required this.label,
    this.tone = AppStatusTone.neutral,
  });

  final IconData icon;
  final String label;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) => AppStatusPill(
        label: label,
        icon: icon,
        tone: tone,
      );
}

class DashboardInlineMessage extends StatelessWidget {
  const DashboardInlineMessage({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message)),
      ],
    );
  }
}

class DashboardSectionErrorCard extends StatelessWidget {
  const DashboardSectionErrorCard({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(
            AppIcons.cloudOffOutlined,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class DashboardEmptySectionCard extends StatelessWidget {
  const DashboardEmptySectionCard({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class DashboardInlineExpansionCard extends StatefulWidget {
  const DashboardInlineExpansionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  State<DashboardInlineExpansionCard> createState() =>
      _DashboardInlineExpansionCardState();
}

class _DashboardInlineExpansionCardState
    extends State<DashboardInlineExpansionCard> {
  final FocusNode _focusNode = FocusNode();
  bool _showFocusHighlight = false;

  @override
  void didUpdateWidget(DashboardInlineExpansionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _focusNode.unfocus();
      _showFocusHighlight = false;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.md,
              end: AppSpacing.sm,
            ),
            child: TodayInfoDisclosure(
              topic: widget.title,
              description: widget.subtitle,
              headerBuilder: (context, infoButton) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Semantics(
                      container: true,
                      button: true,
                      expanded: widget.expanded,
                      label:
                          '${widget.expanded ? 'Collapse' : 'Expand'} ${widget.title}',
                      onTap: widget.onToggle,
                      child: ExcludeSemantics(
                        child: FocusableActionDetector(
                          focusNode: _focusNode,
                          descendantsAreFocusable: false,
                          descendantsAreTraversable: false,
                          includeFocusSemantics: false,
                          mouseCursor: SystemMouseCursors.click,
                          onShowFocusHighlight: _handleFocusHighlight,
                          actions: <Type, Action<Intent>>{
                            ActivateIntent: CallbackAction<ActivateIntent>(
                              onInvoke: (_) {
                                widget.onToggle();
                                return null;
                              },
                            ),
                          },
                          child: DecoratedBox(
                            key: ValueKey(
                              'dashboard-expansion-focus-ring-${widget.title}',
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                              border: Border.all(
                                color: _showFocusHighlight
                                    ? context.visualTokens.focus
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: InkWell(
                              key: ValueKey(
                                'dashboard-expansion-control-${widget.title}',
                              ),
                              onTap: widget.onToggle,
                              canRequestFocus: false,
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 44),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(widget.title)),
                                    const SizedBox(width: AppSpacing.sm),
                                    Icon(
                                      widget.expanded
                                          ? AppIcons.expandLess
                                          : AppIcons.expandMore,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  infoButton,
                ],
              ),
            ),
          ),
          if (widget.expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: widget.child,
            ),
          ],
        ],
      ),
    );
  }

  void _handleFocusHighlight(bool value) {
    if (mounted && value != _showFocusHighlight) {
      setState(() => _showFocusHighlight = value);
    }
  }
}
