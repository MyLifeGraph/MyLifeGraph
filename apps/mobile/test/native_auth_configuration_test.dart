import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/auth/data/auth_repository.dart';

void main() {
  test('Android release auth callbacks and networking are configured', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android.permission.INTERNET'),
    );
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android.intent.category.BROWSABLE'));
    expect(manifest, contains('android:scheme="com.mylifegraph.app"'));
    expect(manifest, contains('android:host="login-callback"'));
    expect(
      nativeAuthCallbackUrl,
      'com.mylifegraph.app://login-callback/',
    );
  });

  test('local Supabase accepts the native callback URL', () {
    final config = File('../../supabase/config.toml').readAsStringSync();
    expect(config, contains(nativeAuthCallbackUrl));
  });

  test('Android release never falls back to the debug signing key', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('Release signing is not configured'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
  });
}
