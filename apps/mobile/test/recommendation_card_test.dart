import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/dashboard/presentation/widgets/recommendation_card.dart';
import 'package:my_life_graph/features/optimization/domain/entities/recommendation.dart';

void main() {
  testWidgets('renders a recommendation as information, not a fake action',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecommendationCard(
            recommendation: Recommendation(
              id: 'recommendation-1',
              title: 'Protect one focus block',
              reason: 'Your open priority still has time today.',
              actionLabel: 'Schedule a 25-minute block',
              category: RecommendationCategory.focus,
              confidence: 0.7,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Suggested next step'), findsOneWidget);
    expect(find.text('Schedule a 25-minute block'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}
