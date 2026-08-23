import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../domain/auth_captcha.dart';
import 'auth_captcha_platform.dart';
import 'auth_captcha_platform_contract.dart';

final authCaptchaChallengeProvider = Provider<AuthCaptchaChallenge>((ref) {
  return PlatformAuthCaptchaChallenge(
    config: ref.watch(appConfigProvider),
    platform: createAuthCaptchaPlatform(),
  );
});

abstract interface class AuthCaptchaChallenge {
  Future<String?> acquire(
    BuildContext context, {
    required AuthCaptchaAction action,
  });
}

class PlatformAuthCaptchaChallenge implements AuthCaptchaChallenge {
  PlatformAuthCaptchaChallenge({
    required AppConfig config,
    required AuthCaptchaPlatform platform,
    Random? random,
  })  : _config = config,
        _platform = platform,
        _random = random ?? Random.secure();

  final AppConfig _config;
  final AuthCaptchaPlatform _platform;
  final Random _random;

  @override
  Future<String?> acquire(
    BuildContext context, {
    required AuthCaptchaAction action,
  }) async {
    if (!_config.requiresAuthCaptcha) return null;
    _config.validateAuthProtectionConfiguration();
    final nonceBytes = List<int>.generate(24, (_) => _random.nextInt(256));
    final token = await _platform.acquire(
      context,
      challengeUrl: _config.turnstileChallengeUrl,
      siteKey: _config.turnstileSiteKey,
      action: action.wireValue,
      nonce: base64Url.encode(nonceBytes).replaceAll('=', ''),
    );
    return validateAuthCaptchaToken(
      requiredForEnvironment: true,
      token: token,
    );
  }
}
