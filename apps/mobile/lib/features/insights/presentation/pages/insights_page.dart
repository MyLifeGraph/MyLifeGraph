import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/entities/correlation.dart';
import '../../domain/entities/insight.dart';
import '../../domain/entities/personal_patterns.dart';
import '../../domain/entities/sleep_recommendation.dart';
import '../../domain/services/correlation_analyzer.dart';
import '../../domain/services/coaching_observation.dart';
import '../../../optimization/domain/entities/skillset_profile.dart';
import 'package:my_life_graph/composition/optimization_providers.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import '../providers/insights_providers.dart';
import '../widgets/insights_skillset_card.dart';
import '../../../../composition/skillset_providers.dart';
import '../../domain/entities/skillset_observations.dart';

part '../widgets/insights_exploration_widgets.dart';
part '../widgets/insights_summary_widgets.dart';

class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final report = ref.watch(correlationReportProvider);
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    final showExampleSkillset = capabilities.isLocalDemo;
    final personalPatterns = ref.watch(personalPatternsProvider);
    final sleepRecommendation = ref.watch(sleepRecommendationProvider);
    final skillset = showExampleSkillset
        ? ref.watch(skillsetProfileProvider)
        : null;
    void retry() {
      ref.invalidate(insightsProvider);
      ref.invalidate(correlationReportProvider);
      ref.invalidate(personalPatternsProvider);
      ref.invalidate(sleepRecommendationProvider);
    }

    if ((insights.hasError && !insights.hasValue) ||
        (report.hasError && !report.hasValue)) {
      return AppPage(
        title: 'Insights',
        compactHeader: true,
        actions: [
          AppHeaderActions(
            pageActions: [_InsightsRefreshButton(onRefresh: retry)],
          ),
        ],
        children: [_InsightsLoadError(onRetry: retry)],
      );
    }
    if (!insights.hasValue || !report.hasValue) {
      return AppPage(
        title: 'Insights',
        compactHeader: true,
        actions: [
          AppHeaderActions(
            pageActions: [_InsightsRefreshButton(onRefresh: retry)],
          ),
        ],
        children: const [Center(child: CircularProgressIndicator())],
      );
    }

    return _InsightsHome(
      insights: insights.requireValue,
      report: report.requireValue,
      skillset: skillset,
      personalPatterns: personalPatterns,
      sleepRecommendation: sleepRecommendation,
      showPersonalPatterns: !showExampleSkillset,
    );
  }
}

class _InsightsHome extends ConsumerStatefulWidget {
  const _InsightsHome({
    required this.insights,
    required this.report,
    required this.skillset,
    required this.personalPatterns,
    required this.sleepRecommendation,
    required this.showPersonalPatterns,
  });

  final List<Insight> insights;
  final CorrelationReport report;
  final AsyncValue<SkillsetProfile>? skillset;
  final AsyncValue<PersonalPatterns?> personalPatterns;
  final AsyncValue<SleepRecommendation?> sleepRecommendation;
  final bool showPersonalPatterns;

  @override
  ConsumerState<_InsightsHome> createState() => _InsightsHomeState();
}

enum _AdvancedPane { compare, topPatterns, trend, skillset, matrix, discovered }

enum _InsightsView { overview, advanced }

// UI-only choices for this app session, like the shared Insights window.
// No account data or authentication dependency belongs in these preferences.
final _insightsViewProvider = StateProvider<_InsightsView>((_) => _InsightsView.overview);
final _advancedPaneProvider = StateProvider<_AdvancedPane>((_) => _AdvancedPane.compare);

class _InsightsHomeState extends ConsumerState<_InsightsHome> {
  _InsightsView get _view => ref.watch(_insightsViewProvider);
  set _view(_InsightsView value) => ref.read(_insightsViewProvider.notifier).state = value;
  String _metricAId = 'sleep_hours';
  String _metricBId = 'useful_progress';
  _AdvancedPane get _advancedPane => ref.watch(_advancedPaneProvider);
  set _advancedPane(_AdvancedPane value) => ref.read(_advancedPaneProvider.notifier).state = value;
  final Set<String> _trendMetricIds = {'sleep_hours', 'useful_progress'};

  @override
  void didUpdateWidget(covariant _InsightsHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.report.metrics.length >= 2) {
      _ensureSelectedMetricsExist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final windowDays = ref.watch(insightsWindowDaysProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 620;
    final observation = const CoachingObservationBuilder().build(widget.report);
    if (widget.report.metrics.length < 2) {
      return _SparseInsightsHome(
        view: _view,
        onViewChanged: (view) => setState(() => _view = view),
        advancedPane: _advancedPane,
        onPaneSelected: (pane) => setState(() => _advancedPane = pane),
        skillsetCard: _skillsetCard(),
        windowSelector: _windowSelector(isMobile: isMobile, windowDays: windowDays),
        isMobile: isMobile,
        report: widget.report,
        observation: observation,
        skillset: widget.skillset,
        personalPatterns: widget.personalPatterns,
        sleepRecommendation: widget.sleepRecommendation,
        showPersonalPatterns: widget.showPersonalPatterns,
        onRefresh: () {
          ref.invalidate(correlationReportProvider);
          ref.invalidate(insightsProvider);
          ref.invalidate(personalPatternsProvider);
          ref.invalidate(sleepRecommendationProvider);
          if (widget.skillset != null) {
            ref.invalidate(skillsetProfileProvider);
          }
        },
      );
    }
    _ensureSelectedMetricsExist();
    final activeResult = widget.report.resultFor(_metricAId, _metricBId);
    final values = const CorrelationAnalyzer().pairValues(
      points: widget.report.points,
      metricAId: _metricAId,
      metricBId: _metricBId,
    );
    final metricA = widget.report.metricById(_metricAId);
    final metricB = widget.report.metricById(_metricBId);
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? AppSpacing.md : AppSpacing.lg,
              isMobile ? AppSpacing.md : AppSpacing.lg,
              isMobile ? AppSpacing.md : AppSpacing.lg,
              AppSpacing.xl,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InsightsHeader(
                    isMobile: isMobile,
                    onRefresh: () {
                      ref.invalidate(correlationReportProvider);
                      ref.invalidate(insightsProvider);
                      ref.invalidate(personalPatternsProvider);
                      ref.invalidate(sleepRecommendationProvider);
                      if (widget.skillset != null) {
                        ref.invalidate(skillsetProfileProvider);
                      }
                    },
                  ),
                  SizedBox(height: isMobile ? AppSpacing.lg : AppSpacing.xl),
                  _InsightsViewToggle(
                    selected: _view,
                    onChanged: (view) => setState(() => _view = view),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Visibility(
                    visible: _view == _InsightsView.overview,
                    maintainState: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.showPersonalPatterns) ...[
                          _PersonalStudyPatternCard(
                            patterns: widget.personalPatterns,
                            onRetry: () =>
                                ref.invalidate(personalPatternsProvider),
                          ),
                          SizedBox(
                            height: isMobile ? AppSpacing.md : AppSpacing.lg,
                          ),
                          _SleepRecommendationCard(
                            value: widget.sleepRecommendation,
                            onRetry: () =>
                                ref.invalidate(sleepRecommendationProvider),
                          ),
                        ] else
                          _CoachingObservationCard(observation: observation),
                        SizedBox(
                          height: isMobile ? AppSpacing.md : AppSpacing.lg,
                        ),
                        if (widget.skillset != null) ...[
                          _SkillsetProfileCard(
                            skillset: widget.skillset!,
                            onRetry: () =>
                                ref.invalidate(skillsetProfileProvider),
                          ),
                          SizedBox(
                            height: isMobile ? AppSpacing.md : AppSpacing.lg,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Visibility(
                    visible: _view == _InsightsView.advanced,
                    maintainState: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _advancedChildren(
                        isMobile: isMobile,
                        windowDays: windowDays,
                        metricA: metricA,
                        metricB: metricB,
                        activeResult: activeResult,
                        values: values,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _advancedChildren({
    required bool isMobile,
    required int windowDays,
    required CorrelationMetric metricA,
    required CorrelationMetric metricB,
    required CorrelationResult? activeResult,
    required List<MetricPairValues> values,
  }) {
    return [
      _AdvancedPaneTabs(
        selected: _advancedPane,
        onSelected: (pane) => setState(() => _advancedPane = pane),
      ),
      const SizedBox(height: AppSpacing.md),
      if (const {_AdvancedPane.topPatterns, _AdvancedPane.trend, _AdvancedPane.skillset, _AdvancedPane.matrix}
          .contains(_advancedPane)) ...[
        _windowSelector(isMobile: isMobile, windowDays: windowDays),
        const SizedBox(height: AppSpacing.md),
      ],
      switch (_advancedPane) {
        _AdvancedPane.compare => Column(
          children: [
            _controlsPanel(isMobile: isMobile, windowDays: windowDays),
            const SizedBox(height: AppSpacing.md),
            _CorrelationCard(
              metricA: metricA,
              metricB: metricB,
              result: activeResult,
              values: values,
              isMobile: isMobile,
            ),
          ],
        ),
        _AdvancedPane.topPatterns => _TopPatternsCard(
          report: widget.report,
          isMobile: isMobile,
        ),
        _AdvancedPane.trend => _trendOverlayCard(isMobile: isMobile),
        _AdvancedPane.skillset => _skillsetCard(),
        _AdvancedPane.matrix => _correlationMatrixCard(isMobile: isMobile),
        _AdvancedPane.discovered => _DiscoveredPatternsCard(
          insights: widget.insights,
          isMobile: isMobile,
        ),
      },
    ];
  }

  Widget _windowSelector({required bool isMobile, required int windowDays}) =>
      _WindowSelector(
        value: windowDays,
        compact: isMobile,
        onChanged: (days) => ref.read(insightsWindowDaysProvider.notifier).state = days,
      );

  Widget _skillsetCard() => InsightsSkillsetCard(
    report:
        widget.showPersonalPatterns &&
            widget.personalPatterns.valueOrNull?.supportsSkillsetCapture == true
        ? skillsetReport(
            widget.personalPatterns.requireValue!.skillsetPoints,
            widget.personalPatterns.requireValue!.window.localEndsOn,
            ref.watch(insightsWindowDaysProvider),
          )
        : widget.report,
    isDemo: !widget.showPersonalPatterns,
    selectedIds: ref.watch(skillsetDimensionsProvider),
    onToggle: (id) {
      final next = {...ref.read(skillsetDimensionsProvider)};
      if (!next.remove(id)) next.add(id);
      ref.read(skillsetDimensionsProvider.notifier).state = next;
    },
  );

  Widget _controlsPanel({required bool isMobile, required int windowDays}) {
    return _ControlsPanel(
      isMobile: isMobile,
      windowDays: windowDays,
      metrics: widget.report.metrics,
      metricAId: _metricAId,
      metricBId: _metricBId,
      onWindowChanged: (value) {
        ref.read(insightsWindowDaysProvider.notifier).state = value;
      },
      onMetricAChanged: (value) {
        if (value == null) return;
        setState(() {
          _metricAId = value;
          if (_metricAId == _metricBId ||
              const CorrelationPairPolicy().isBlocked(_metricAId, _metricBId)) {
            _metricBId = _fallbackMetricId(
              except: _metricAId,
              pairedWith: _metricAId,
            );
          }
        });
      },
      onMetricBChanged: (value) {
        if (value == null) return;
        setState(() {
          _metricBId = value;
          if (_metricAId == _metricBId ||
              const CorrelationPairPolicy().isBlocked(_metricAId, _metricBId)) {
            _metricAId = _fallbackMetricId(
              except: _metricBId,
              pairedWith: _metricBId,
            );
          }
        });
      },
    );
  }

  Widget _trendOverlayCard({required bool isMobile}) {
    return _TrendOverlayCard(
      report: widget.report,
      selectedMetricIds: _trendMetricIds,
      onMetricToggled: (metricId) {
        setState(() {
          if (_trendMetricIds.contains(metricId)) {
            if (_trendMetricIds.length > 1) {
              _trendMetricIds.remove(metricId);
            }
          } else if (_trendMetricIds.every(
            (selected) =>
                !const CorrelationPairPolicy().isBlocked(selected, metricId),
          )) {
            _trendMetricIds.add(metricId);
          }
        });
      },
      isMobile: isMobile,
    );
  }

  Widget _correlationMatrixCard({required bool isMobile}) {
    return _CorrelationMatrixCard(
      report: widget.report,
      selectedMetricAId: _metricAId,
      selectedMetricBId: _metricBId,
      isMobile: isMobile,
      onPairSelected: (metricAId, metricBId) {
        setState(() {
          _metricAId = metricAId;
          _metricBId = metricBId;
        });
      },
    );
  }

  void _ensureSelectedMetricsExist() {
    final metricIds = widget.report.metrics.map((metric) => metric.id).toSet();
    if (!metricIds.contains(_metricAId)) {
      _metricAId = widget.report.metrics.first.id;
    }
    if (!metricIds.contains(_metricBId) ||
        _metricAId == _metricBId ||
        const CorrelationPairPolicy().isBlocked(_metricAId, _metricBId)) {
      _metricBId = _fallbackMetricId(
        except: _metricAId,
        pairedWith: _metricAId,
      );
    }
    _trendMetricIds.removeWhere((id) => !metricIds.contains(id));
    if (_trendMetricIds.length < 2 &&
        !_trendMetricIds.contains(_metricBId) &&
        _trendMetricIds.every(
          (selected) =>
              !const CorrelationPairPolicy().isBlocked(selected, _metricBId),
        )) {
      _trendMetricIds.add(_metricBId);
    }
    if (_trendMetricIds.isEmpty) {
      _trendMetricIds.add(_metricAId);
      _trendMetricIds.add(_metricBId);
    }
  }

  String _fallbackMetricId({required String except, String? pairedWith}) {
    final candidates = widget.report.metrics.where(
      (metric) =>
          metric.id != except &&
          (pairedWith == null ||
              !const CorrelationPairPolicy().isBlocked(metric.id, pairedWith)),
    );
    for (final preferred in const ['useful_progress', 'focus_minutes']) {
      for (final candidate in candidates) {
        if (candidate.id == preferred) return candidate.id;
      }
    }
    return candidates.isEmpty
        ? widget.report.metrics.first.id
        : candidates.first.id;
  }
}
