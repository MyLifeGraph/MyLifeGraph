import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../domain/auth_captcha.dart';
import 'auth_captcha_platform_contract.dart';

AuthCaptchaPlatform createAuthCaptchaPlatform() =>
    const WebAuthCaptchaPlatform();

class WebAuthCaptchaPlatform implements AuthCaptchaPlatform {
  const WebAuthCaptchaPlatform();

  @override
  Future<String> acquire(
    BuildContext context, {
    required Uri challengeUrl,
    required String siteKey,
    required String action,
    required String nonce,
  }) async {
    if (web.window.location.origin != challengeUrl.origin) {
      throw const AuthCaptchaException(
        'The CAPTCHA page does not match this application origin.',
      );
    }
    final requestUri = challengeUrl.replace(
      queryParameters: {
        'sitekey': siteKey,
        'action': action,
        'nonce': nonce,
        'client': 'web',
      },
    );
    final popup = web.window.open(
      requestUri.toString(),
      'mylifegraph_turnstile',
      'popup=yes,width=460,height=620,resizable=yes,noopener=no',
    );
    if (popup == null) {
      throw const AuthCaptchaException(
        'The CAPTCHA window was blocked. Allow pop-ups and try again.',
      );
    }

    final completer = Completer<String>();
    Timer? closePoll;
    Timer? timeout;
    late final JSFunction listener;

    void finishError(String message) {
      if (!completer.isCompleted) {
        completer.completeError(AuthCaptchaException(message));
      }
    }

    listener = ((web.Event event) {
      final message = event as web.MessageEvent;
      if (message.origin != challengeUrl.origin) return;
      final raw = message.data?.dartify();
      if (raw is! String) return;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            decoded['kind'] != 'mylifegraph_turnstile' ||
            decoded['action'] != action ||
            decoded['nonce'] != nonce) {
          return;
        }
        final error = decoded['error'];
        if (error is String && error.isNotEmpty) {
          finishError('CAPTCHA verification failed. Try again.');
          return;
        }
        final token = validateAuthCaptchaToken(
          requiredForEnvironment: true,
          token: decoded['token'] is String ? decoded['token'] as String : null,
        );
        if (!completer.isCompleted) completer.complete(token!);
      } catch (_) {
        finishError('The verification response was invalid.');
      }
    }).toJS;

    web.window.addEventListener('message', listener);
    closePoll = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (popup.closed) {
        finishError('CAPTCHA verification was cancelled.');
      }
    });
    timeout = Timer(
      const Duration(minutes: 2),
      () => finishError('CAPTCHA verification timed out. Try again.'),
    );
    try {
      return await completer.future;
    } finally {
      closePoll.cancel();
      timeout.cancel();
      web.window.removeEventListener('message', listener);
      if (!popup.closed) popup.close();
    }
  }
}
