import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/widgets/hosted_environment_banner.dart';

void main() {
  testWidgets('staging identity is persistent and pilot stays unlabelled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HostedEnvironmentBanner(
            environment: 'staging',
            child: Text('Product'),
          ),
        ),
      ),
    );
    expect(find.text('Staging · Test data'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HostedEnvironmentBanner(
            environment: 'pilot',
            child: Text('Product'),
          ),
        ),
      ),
    );
    expect(find.text('Staging · Test data'), findsNothing);
  });
}
