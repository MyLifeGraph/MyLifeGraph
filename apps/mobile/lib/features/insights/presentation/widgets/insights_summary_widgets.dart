part of '../pages/insights_page.dart';

class _InsightsLoadError extends StatelessWidget {
  const _InsightsLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.cloudOffOutlined, size: 36),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Could not load account insights.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Check your connection and try loading Insights again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightsViewToggle extends StatelessWidget {
  const _InsightsViewToggle({required this.selected, required this.onChanged});

  final _InsightsView selected;
  final ValueChanged<_InsightsView> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SegmentedButton<_InsightsView>(
        key: const Key('insights-view-toggle'),
        expandedInsets: EdgeInsets.zero,
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          side: BorderSide.none,
          padding: const EdgeInsets.all(AppSpacing.sm),
        ),
        segments: [
          ButtonSegment(
            value: _InsightsView.overview,
            label: const Text('Overview'),
            icon: MediaQuery.textScalerOf(context).scale(14) <= 18
                ? const Icon(AppIcons.insightsOutlined, size: 18)
                : null,
          ),
          ButtonSegment(
            value: _InsightsView.advanced,
            label: const Text('Advanced'),
            icon: MediaQuery.textScalerOf(context).scale(14) <= 18
                ? const Icon(AppIcons.tuneOutlined, size: 18)
                : null,
          ),
        ],
        selected: {selected},
        onSelectionChanged: (values) => onChanged(values.single),
      ),
    ),
  );
}

class _SparseInsightsHome extends StatelessWidget {
  const _SparseInsightsHome({
    required this.view,
    required this.onViewChanged,
    required this.advancedPane,
    required this.onPaneSelected,
    required this.skillsetCard,
    required this.windowSelector,
    required this.isMobile,
    required this.report,
    required this.observation,
    required this.skillset,
    required this.personalPatterns,
    required this.sleepRecommendation,
    required this.showPersonalPatterns,
    required this.onRefresh,
  });

  final _InsightsView view;
  final ValueChanged<_InsightsView> onViewChanged;
  final _AdvancedPane advancedPane;
  final ValueChanged<_AdvancedPane> onPaneSelected;
  final Widget skillsetCard;
  final Widget windowSelector;
  final bool isMobile;
  final CorrelationReport report;
  final CoachingObservation observation;
  final AsyncValue<SkillsetProfile>? skillset;
  final AsyncValue<PersonalPatterns?> personalPatterns;
  final AsyncValue<SleepRecommendation?> sleepRecommendation;
  final bool showPersonalPatterns;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final measured = report.metrics.isEmpty
        ? 'No comparable signal has enough data in this window yet.'
        : '${report.metrics.single.label} is available, but a relationship needs a second measured signal.';
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
                  _InsightsHeader(isMobile: isMobile, onRefresh: onRefresh),
                  SizedBox(height: isMobile ? AppSpacing.lg : AppSpacing.xl),
                  _InsightsViewToggle(selected: view, onChanged: onViewChanged),
                  const SizedBox(height: AppSpacing.md),
                  Visibility(
                    visible: view == _InsightsView.overview,
                    maintainState: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showPersonalPatterns) ...[
                          _PersonalStudyPatternCard(
                            patterns: personalPatterns,
                            onRetry: onRefresh,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _SleepRecommendationCard(
                            value: sleepRecommendation,
                            onRetry: onRefresh,
                          ),
                        ] else
                          _CoachingObservationCard(observation: observation),
                        const SizedBox(height: AppSpacing.md),
                        if (skillset != null)
                          _SkillsetProfileCard(
                            skillset: skillset!,
                            onRetry: onRefresh,
                          ),
                      ],
                    ),
                  ),
                  Visibility(
                    visible: view == _InsightsView.advanced,
                    maintainState: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AdvancedPaneTabs(
                          selected: advancedPane,
                          onSelected: onPaneSelected,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (advancedPane != _AdvancedPane.discovered) ...[
                          windowSelector,
                          const SizedBox(height: AppSpacing.md),
                        ],
                        if (advancedPane == _AdvancedPane.skillset)
                          skillsetCard
                        else
                          _InsightsPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Not enough signals yet',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(measured),
                              ],
                            ),
                          ),
                      ],
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
}

class _InsightsHeader extends StatelessWidget {
  const _InsightsHeader({required this.isMobile, required this.onRefresh});

  final bool isMobile;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppPageHeading(
      title: Text(
        'Insights',
        style: isMobile
            ? Theme.of(context).textTheme.headlineMedium
            : Theme.of(context).textTheme.headlineLarge,
      ),
      actions: AppHeaderActions(
        pageActions: [_InsightsRefreshButton(onRefresh: onRefresh)],
      ),
    );
  }
}

class _InsightsRefreshButton extends StatelessWidget {
  const _InsightsRefreshButton({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Refresh correlations',
      onPressed: onRefresh,
      icon: const Icon(AppIcons.refresh),
    );
  }
}

class _PersonalStudyPatternCard extends StatelessWidget {
  const _PersonalStudyPatternCard({
    required this.patterns,
    required this.onRetry,
  });

  final AsyncValue<PersonalPatterns?> patterns;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _InsightsPanel(
      panelKey: const Key('personal-study-pattern-panel'),
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          container: true,
          label: 'Personal study pattern',
          child: patterns.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(child: Text('Loading personal study pattern…')),
                ],
              ),
            ),
            error: (error, __) => Padding(
              key: const Key('personal-study-pattern-error'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PERSONAL STUDY PATTERN',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Personal evidence is temporarily unavailable.',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Your Focus history is unchanged. Try loading the pattern '
                    'again.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(AppIcons.refresh),
                    label: const Text('Retry personal pattern'),
                  ),
                ],
              ),
            ),
            data: (value) {
              if (value == null) return const SizedBox.shrink();
              return _PersonalStudyPatternContent(patterns: value);
            },
          ),
        ),
      ),
    );
  }
}

class _PersonalStudyPatternContent extends StatelessWidget {
  const _PersonalStudyPatternContent({required this.patterns});

  final PersonalPatterns patterns;

  @override
  Widget build(BuildContext context) {
    final status = switch (patterns.status) {
      PersonalPatternsStatus.disabled => 'Disabled',
      PersonalPatternsStatus.collecting => 'Collecting',
      PersonalPatternsStatus.emerging => 'Emerging',
      PersonalPatternsStatus.stable => 'Stable',
    };
    final coverage = (patterns.sample.ratingCoverage * 100).round();
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                AppIcons.schoolOutlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              Text(
                'PERSONAL STUDY PATTERN',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Chip(label: Text(status), visualDensity: VisualDensity.compact),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            patterns.summary,
            key: const Key('personal-study-pattern-summary'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${patterns.sample.ratedSessions} rated sessions · $coverage% coverage · 90-day window',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
    if (patterns.status == PersonalPatternsStatus.disabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${patterns.timezone} · '
                  '${patterns.sample.ratedLocalDays} rated days',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(patterns.limitations.first),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        ExpansionTile(
          key: const Key('personal-study-pattern-evidence'),
          title: const Text('Details'),
          subtitle: Text(
            '${patterns.timezone} · '
            '${patterns.sample.ratedLocalDays} rated days',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: [
            if (patterns.patterns.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No comparison has enough observations to display yet.',
                ),
              )
            else
              for (final pattern in patterns.patterns)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pattern.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(pattern.summary),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${pattern.evidence.preferredCount} in '
                        '${pattern.evidence.preferredGroup} · '
                        '${pattern.evidence.comparisonCount} in '
                        '${pattern.evidence.comparisonGroup}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      for (final detail in pattern.evidence.details)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            '• $detail',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
            const Divider(),
            for (final limitation in patterns.limitations)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '• $limitation',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SleepRecommendationCard extends StatelessWidget {
  const _SleepRecommendationCard({required this.value, required this.onRetry});

  final AsyncValue<SleepRecommendation?> value;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _InsightsPanel(
      panelKey: const Key('sleep-recommendation-panel'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Semantics(
        container: true,
        label: 'Sleep recommendation',
        child: value.when(
          loading: () => const Row(
            key: Key('sleep-recommendation-loading'),
            children: [
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Loading sleep recommendation…')),
            ],
          ),
          error: (error, __) => Column(
            key: const Key('sleep-recommendation-error'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SLEEP RECOMMENDATION',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Sleep evidence is temporarily unavailable.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Your study pattern is unchanged. No fallback window was created.',
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Retry sleep recommendation'),
              ),
            ],
          ),
          data: (recommendation) => recommendation == null
              ? const SizedBox.shrink()
              : _SleepRecommendationContent(value: recommendation),
        ),
      ),
    );
  }
}

class _SleepRecommendationContent extends StatelessWidget {
  const _SleepRecommendationContent({required this.value});

  final SleepRecommendation value;

  @override
  Widget build(BuildContext context) {
    final (status, tone) = switch (value.status) {
      SleepRecommendationStatus.disabled => ('Disabled', AppStatusTone.neutral),
      SleepRecommendationStatus.collecting => (
        'Collecting ${value.progress}',
        AppStatusTone.info,
      ),
      SleepRecommendationStatus.unstable => (
        'Unstable',
        AppStatusTone.attention,
      ),
      SleepRecommendationStatus.ready => ('Ready', AppStatusTone.success),
    };
    final ready = value.recommendation;
    return Column(
      key: Key('sleep-recommendation-${value.status.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              AppIcons.bedtimeOutlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            Text(
              'SLEEP RECOMMENDATION',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            AppStatusPill(label: status, tone: tone),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          ready == null
              ? 'No stable window yet'
              : 'Best-supported sleep window',
          key: const Key('sleep-recommendation-title'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (ready == null)
          Text(value.summary)
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final inline =
                  constraints.maxWidth < 600 &&
                  constraints.maxWidth >= 260 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 18;
              final metricWidth = constraints.maxWidth < 600
                  ? constraints.maxWidth
                  : (constraints.maxWidth - AppSpacing.md * 2) / 3;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  SizedBox(
                    width: metricWidth,
                    child: _SleepWindowMetric(
                      inline: inline,
                      value: ready.bedtime.label,
                      label: 'Sleep start',
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: _SleepWindowMetric(
                      inline: inline,
                      value: ready.wakeTime.label,
                      label: 'Wake time',
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: _SleepWindowMetric(
                      inline: inline,
                      value: ready.duration.label,
                      label: 'Duration',
                    ),
                  ),
                ],
              );
            },
          ),
          if (ready.warning == 'below_confirmed_sleep_target') ...[
            const SizedBox(height: AppSpacing.md),
            const AppSurface(
              key: Key('sleep-recommendation-warning'),
              variant: AppSurfaceVariant.warning,
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'This observed duration is below your median confirmed sleep '
                'target. Your target has not been changed.',
              ),
            ),
          ],
        ],
        if (ready != null || value.limitations.isNotEmpty)
          ExpansionTile(
            title: const Text('Details'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
            children: [
              if (ready != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(value.summary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${ready.candidateDays} matching days compared with '
                    '${ready.comparisonDays} other eligible days · ${value.timezone}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ] else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${value.eligibleFocusDays} eligible Focus days · '
                    '${value.validNights} valid nights · 90-day window',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              for (final limitation in value.limitations)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '• $limitation',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _SleepWindowMetric extends StatelessWidget {
  const _SleepWindowMetric({
    required this.label,
    required this.value,
    required this.inline,
  });

  final String label;
  final String value;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = Text(label, style: theme.textTheme.bodyMedium);
    final number = Text(
      value,
      textAlign: TextAlign.start,
      style: theme.textTheme.titleMedium,
    );
    return inline
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 100, child: caption),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: number),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [caption, number],
          );
  }
}

class _InsightsCardLabel extends StatelessWidget {
  const _InsightsCardLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ExcludeSemantics(
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
      ],
    );
  }
}

class _CoachingObservationCard extends StatelessWidget {
  const _CoachingObservationCard({required this.observation});

  final CoachingObservation observation;

  @override
  Widget build(BuildContext context) {
    final confidence = switch (observation.confidence) {
      ObservationConfidence.insufficient => 'Insufficient',
      ObservationConfidence.emerging => 'Emerging',
      ObservationConfidence.stronger => 'Stronger',
    };
    return _InsightsPanel(
      panelKey: const Key('insights-observation-panel'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InsightsCardLabel(
            icon: AppIcons.lightbulbOutline,
            label: 'ONE OBSERVATION',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            observation.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(observation.summary),
          const SizedBox(height: AppSpacing.sm),
          Chip(
            label: Text('$confidence confidence'),
            visualDensity: VisualDensity.compact,
          ),
          ExpansionTile(
            title: const Text('Details'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${observation.evidenceWindow} · ${observation.dataQuality}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (observation.experiment != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withAlpha(90),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Text(observation.experiment!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SkillsetProfileCard extends StatelessWidget {
  const _SkillsetProfileCard({required this.skillset, required this.onRetry});

  final AsyncValue<SkillsetProfile> skillset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _InsightsPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: skillset.when(
        loading: () => const Row(
          children: [
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Loading example skill profile…')),
          ],
        ),
        error: (error, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _InsightsCardLabel(
              icon: AppIcons.autoGraphOutlined,
              label: 'EXAMPLE SKILL PROFILE',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Example skill profile unavailable.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This optional example could not be loaded. Your saved activity '
              'is unchanged.',
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Retry example'),
            ),
          ],
        ),
        data: (profile) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _InsightsCardLabel(
              icon: AppIcons.autoGraphOutlined,
              label: 'EXAMPLE SKILL PROFILE',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${profile.primaryArchetype} · ${profile.overallScore} / 100',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Local demo for ${profile.userName} · example data only',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            if (profile.scores.isEmpty)
              const Text('No individual skill signals were stored.')
            else
              ...profile.scores.map(
                (score) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final description = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            score.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            score.signal,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      );
                      final stackScore =
                          constraints.maxWidth < 280 ||
                          MediaQuery.textScalerOf(context).scale(14) > 21;
                      if (stackScore) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            description,
                            const SizedBox(height: AppSpacing.xs),
                            Text('${score.score} / 100'),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: description),
                          const SizedBox(width: AppSpacing.md),
                          Text('${score.score} / 100'),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
