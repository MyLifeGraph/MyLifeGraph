import 'package:flutter/material.dart';

abstract interface class AuthCaptchaPlatform {
  Future<String> acquire(
    BuildContext context, {
    required Uri challengeUrl,
    required String siteKey,
    required String action,
    required String nonce,
  });
}
