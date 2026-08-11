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

class _SparseInsightsHome extends StatelessWidget {
  const _SparseInsightsHome({
    required this.isMobile,
    required this.report,
    required this.observation,
    required this.skillset,
    required this.personalPatterns,
    required this.sleepRecommendation,
    required this.showPersonalPatterns,
    required this.onRefresh,
  });

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
              isMobile ? AppSpacing.sm : AppSpacing.lg,
              isMobile ? AppSpacing.md : AppSpacing.lg,
              AppSpacing.xl,
            ),
            sliver: SliverList.list(
              children: [
                _InsightsHeader(isMobile: isMobile, onRefresh: onRefresh),
                SizedBox(height: isMobile ? AppSpacing.lg : AppSpacing.xl),
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
                _InsightsPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keep using the features you already need',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(measured),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Completed focus sessions now count automatically. Unmeasured screen, movement, or focus values are not offered as empty metrics.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (skillset != null)
                  _SkillsetProfileCard(
                    skillset: skillset!,
                    onRetry: onRefresh,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsHeader extends StatelessWidget {
  const _InsightsHeader({
    required this.isMobile,
    required this.onRefresh,
  });

  final bool isMobile;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PATTERNS AND TRENDS',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontSize: isMobile ? 12 : 14,
                letterSpacing: isMobile ? 2.5 : 4,
              ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Insights',
          style: isMobile
              ? Theme.of(context).textTheme.headlineMedium
              : Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Start with transparent personal evidence. Open advanced exploration when you want to inspect individual signals.',
          key: const Key('insights-header-description'),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.7,
              ),
        ),
      ],
    );

    final actions = AppHeaderActions(
      pageActions: [
        _InsightsRefreshButton(onRefresh: onRefresh),
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          copy,
          const SizedBox(height: AppSpacing.md),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: copy),
        const SizedBox(width: AppSpacing.md),
        Flexible(child: actions),
      ],
    );
  }
}

class _InsightsRefreshButton extends StatelessWidget {
  const _InsightsRefreshButton({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      onPressed: onRefresh,
      icon: const Icon(AppIcons.refresh, size: 18),
      label: const Text('Refresh correlations'),
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
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERSONAL STUDY PATTERN',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            patterns.summary,
            key: const Key('personal-study-pattern-summary'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Chip(label: Text(status)),
              Chip(
                label: Text(
                  '${patterns.sample.ratedSessions} rated sessions',
                ),
              ),
              Chip(label: Text('$coverage% coverage')),
              const Chip(label: Text('90-day window')),
            ],
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
          title: const Text('Evidence and limits'),
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
  const _SleepRecommendationCard({
    required this.value,
    required this.onRetry,
  });

  final AsyncValue<SleepRecommendation?> value;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _InsightsPanel(
      panelKey: const Key('sleep-recommendation-panel'),
      padding: const EdgeInsets.all(AppSpacing.lg),
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
                'Your existing personal study pattern is still available. '
                'No fallback sleep window was created.',
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
      SleepRecommendationStatus.disabled => (
          'Disabled',
          AppStatusTone.neutral,
        ),
      SleepRecommendationStatus.collecting => (
          'Collecting ${value.progress}',
          AppStatusTone.info,
        ),
      SleepRecommendationStatus.unstable => (
          'Unstable',
          AppStatusTone.attention,
        ),
      SleepRecommendationStatus.ready => (
          'Ready',
          AppStatusTone.success,
        ),
    };
    final ready = value.recommendation;
    return Column(
      key: Key('sleep-recommendation-${value.status.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SLEEP RECOMMENDATION',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Text(
              ready == null
                  ? 'No stable window yet'
                  : 'Best-supported sleep window',
              key: const Key('sleep-recommendation-title'),
              style: Theme.of(context).textTheme.titleLarge,
            );
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: AppSpacing.sm),
                  AppStatusPill(label: status, tone: tone),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: AppSpacing.sm),
                AppStatusPill(label: status, tone: tone),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(value.summary),
        const SizedBox(height: AppSpacing.md),
        if (ready == null)
          Text(
            '${value.eligibleFocusDays} eligible Focus days · '
            '${value.validNights} valid nights · 90-day window',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final metricWidth = constraints.maxWidth < 600
                  ? constraints.maxWidth
                  : (constraints.maxWidth - AppSpacing.lg * 2) / 3;
              return Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: metricWidth,
                    child: AppMetric(
                      value: ready.bedtime.label,
                      label: 'Sleep start',
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: AppMetric(
                      value: ready.wakeTime.label,
                      label: 'Wake time',
                      supportingText: ready.wakeDayOffset == 0
                          ? 'Same local day'
                          : 'Following local day',
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: AppMetric(
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
          const SizedBox(height: AppSpacing.md),
          Text(
            '${ready.candidateDays} matching days compared with '
            '${ready.comparisonDays} other eligible days · ${value.timezone}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (value.limitations.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final limitation in value.limitations)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '• $limitation',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
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
          Text(
            'ONE OBSERVATION',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            observation.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(observation.summary),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Chip(label: Text('$confidence confidence')),
              Chip(label: Text(observation.evidenceWindow)),
              Chip(label: Text(observation.dataQuality)),
            ],
          ),
          if (observation.experiment != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withAlpha(90),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Text(observation.experiment!),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkillsetProfileCard extends StatelessWidget {
  const _SkillsetProfileCard({
    required this.skillset,
    required this.onRetry,
  });

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
            Text(
              'EXAMPLE SKILL PROFILE',
              style: Theme.of(context).textTheme.labelLarge,
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
            Text(
              'EXAMPLE SKILL PROFILE',
              style: Theme.of(context).textTheme.labelLarge,
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
                      final stackScore = constraints.maxWidth < 280 ||
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
