import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';

void main() {
  test('Coach surface defaults fail closed for production and release', () {
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'production',
        releaseMode: false,
      ),
      isFalse,
    );
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'development',
        releaseMode: true,
      ),
      isFalse,
    );
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'development',
        releaseMode: false,
      ),
      isTrue,
    );
  });

  test('development may opt in but production and release cannot', () {
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'development',
        releaseMode: false,
        explicitValue: 'true',
      ),
      isTrue,
    );
    for (final environment in ['production', ' PRODUCTION ']) {
      expect(
        resolveCoachSurfaceEnabled(
          environment: environment,
          releaseMode: false,
          explicitValue: 'true',
        ),
        isFalse,
      );
    }
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'development',
        releaseMode: true,
        explicitValue: 'true',
      ),
      isFalse,
    );
    for (final value in ['false', 'TRUE', '1', 'invalid']) {
      expect(
        resolveCoachSurfaceEnabled(
          environment: 'development',
          releaseMode: false,
          explicitValue: value,
        ),
        isFalse,
        reason: 'explicitValue=$value',
      );
    }
  });
}
