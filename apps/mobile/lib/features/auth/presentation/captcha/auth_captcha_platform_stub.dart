import 'package:flutter/material.dart';

import '../../domain/auth_captcha.dart';
import 'auth_captcha_platform_contract.dart';

AuthCaptchaPlatform createAuthCaptchaPlatform() =>
    const _UnsupportedAuthCaptchaPlatform();

class _UnsupportedAuthCaptchaPlatform implements AuthCaptchaPlatform {
  const _UnsupportedAuthCaptchaPlatform();

  @override
  Future<String> acquire(
    BuildContext context, {
    required Uri challengeUrl,
    required String siteKey,
    required String action,
    required String nonce,
  }) {
    throw const AuthCaptchaException(
      'CAPTCHA is unavailable on this platform.',
    );
  }
}
