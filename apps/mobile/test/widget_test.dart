import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_life_graph/app.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders authentication gate first', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: 'test',
              supabaseUrl: '',
              supabaseAnonKey: '',
              aiServiceBaseUrl: 'http://localhost:8000',
              useMockData: true,
            ),
          ),
        ],
        child: const PersonalOptimizationApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Build your day-aware coach'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
