import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.arrow_forward, size: 18, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  recommendation.actionLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(RecommendationCategory category) {
    return switch (category) {
      RecommendationCategory.focus => Icons.center_focus_strong,
      RecommendationCategory.recovery => Icons.bedtime_outlined,
      RecommendationCategory.nutrition => Icons.restaurant_outlined,
      RecommendationCategory.movement => Icons.directions_walk,
      RecommendationCategory.planning => Icons.event_available_outlined,
    };
  }

  Color _categoryColor(BuildContext context, RecommendationCategory category) {
    return switch (category) {
      RecommendationCategory.focus => Theme.of(context).colorScheme.primary,
      RecommendationCategory.recovery => const Color(0xFF8EA7FF),
      RecommendationCategory.nutrition => const Color(0xFFFFC857),
      RecommendationCategory.movement => const Color(0xFFFF8F70),
      RecommendationCategory.planning => const Color(0xFFB7F07A),
    };
  }
}
