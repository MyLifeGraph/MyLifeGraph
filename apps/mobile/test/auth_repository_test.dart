import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/auth/data/auth_repository.dart';

void main() {
  group('webOAuthRedirectTo', () {
    test('uses the Vercel production origin with a trailing slash', () {
      final redirectTo = webOAuthRedirectTo(
        Uri.parse('https://my-life-graph.vercel.app/#/auth'),
      );

      expect(redirectTo, 'https://my-life-graph.vercel.app/');
    });

    test('uses the current localhost origin with a trailing slash', () {
      final redirectTo = webOAuthRedirectTo(
        Uri.parse('http://127.0.0.1:7357/#/auth'),
      );

      expect(redirectTo, 'http://127.0.0.1:7357/');
    });
  });
}
