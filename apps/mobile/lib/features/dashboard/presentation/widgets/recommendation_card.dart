import 'package:flutter/material.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../optimization/domain/entities/recommendation.dart';

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({required this.recommendation, super.key});

  final Recommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(context, recommendation.category);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_categoryIcon(recommendation.category), color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  recommendation.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            recommendation.reason,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: AppSurface(
              variant: AppSurfaceVariant.subtle,
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.lightbulbOutline,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suggested next step',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          recommendation.actionLabel,
                          style: Theme.of(context).textTheme.bodyMedium,
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

  IconData _categoryIcon(RecommendationCategory category) {
    return switch (category) {
      RecommendationCategory.focus => AppIcons.centerFocusStrong,
      RecommendationCategory.recovery => AppIcons.bedtimeOutlined,
      RecommendationCategory.nutrition => AppIcons.restaurantOutlined,
      RecommendationCategory.movement => AppIcons.directionsWalk,
      RecommendationCategory.planning => AppIcons.eventAvailableOutlined,
    };
  }

  Color _categoryColor(BuildContext context, RecommendationCategory category) {
    final tokens = context.visualTokens;
    return switch (category) {
      RecommendationCategory.focus => tokens.dataViolet,
      RecommendationCategory.recovery => tokens.dataBlue,
      RecommendationCategory.nutrition => tokens.dataCoral,
      RecommendationCategory.movement => tokens.dataBlue,
      RecommendationCategory.planning => tokens.brand,
    };
  }
}
