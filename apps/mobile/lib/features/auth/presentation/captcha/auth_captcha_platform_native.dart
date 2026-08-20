import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../../core/constants/app_radii.dart';
import '../../domain/auth_captcha.dart';
import 'auth_captcha_platform_contract.dart';

AuthCaptchaPlatform createAuthCaptchaPlatform() =>
    const NativeAuthCaptchaPlatform();

class NativeAuthCaptchaPlatform implements AuthCaptchaPlatform {
  const NativeAuthCaptchaPlatform();

  @override
  Future<String> acquire(
    BuildContext context, {
    required Uri challengeUrl,
    required String siteKey,
    required String action,
    required String nonce,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TurnstileWebViewDialog(
        challengeUrl: challengeUrl,
        siteKey: siteKey,
        action: action,
        nonce: nonce,
      ),
    );
    if (result == null) {
      throw const AuthCaptchaException('CAPTCHA verification was cancelled.');
    }
    return result;
  }
}

class _TurnstileWebViewDialog extends StatefulWidget {
  const _TurnstileWebViewDialog({
    required this.challengeUrl,
    required this.siteKey,
    required this.action,
    required this.nonce,
  });

  final Uri challengeUrl;
  final String siteKey;
  final String action;
  final String nonce;

  @override
  State<_TurnstileWebViewDialog> createState() =>
      _TurnstileWebViewDialogState();
}

class _TurnstileWebViewDialogState extends State<_TurnstileWebViewDialog> {
  late final WebViewController _controller;
  Timer? _timeout;
  String? _error;
  bool _completed = false;

  Uri get _requestUri => widget.challengeUrl.replace(
        queryParameters: {
          'sitekey': widget.siteKey,
          'action': widget.action,
          'nonce': widget.nonce,
          'client': 'native',
        },
      );

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final target = Uri.tryParse(request.url);
            return target == _requestUri
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != false) {
              _fail('The verification page could not be loaded.');
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'TurnstileToken',
        onMessageReceived: (message) => _handleMessage(message.message),
      );
    unawaited(_configureCookiesAndLoad());
    _timeout = Timer(
      const Duration(minutes: 2),
      () => _fail('CAPTCHA verification timed out. Try again.'),
    );
  }

  Future<void> _configureCookiesAndLoad() async {
    try {
      final platformController = _controller.platform;
      if (platformController is AndroidWebViewController) {
        final platformCookies = WebViewCookieManager().platform;
        if (platformCookies is! AndroidWebViewCookieManager) {
          throw StateError('Android WebView cookie manager is unavailable.');
        }
        await platformCookies.setAcceptThirdPartyCookies(
          platformController,
          true,
        );
      }
      if (mounted) await _controller.loadRequest(_requestUri);
    } catch (_) {
      _fail('The verification page could not be initialized.');
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _handleMessage(String raw) {
    if (_completed) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['kind'] != 'mylifegraph_turnstile' ||
          decoded['action'] != widget.action ||
          decoded['nonce'] != widget.nonce) {
        _fail('The verification response was invalid.');
        return;
      }
      final error = decoded['error'];
      if (error is String && error.isNotEmpty) {
        _fail('CAPTCHA verification failed. Try again.');
        return;
      }
      final token = decoded['token'];
      final checked = validateAuthCaptchaToken(
        requiredForEnvironment: true,
        token: token is String ? token : null,
      );
      _completed = true;
      _timeout?.cancel();
      Navigator.of(context).pop(checked);
    } catch (_) {
      _fail('The verification response was invalid.');
    }
  }

  void _fail(String message) {
    if (!mounted || _completed) return;
    setState(() => _error = message);
  }

  void _retry() {
    setState(() => _error = null);
    _timeout?.cancel();
    _timeout = Timer(
      const Duration(minutes: 2),
      () => _fail('CAPTCHA verification timed out. Try again.'),
    );
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Human verification'),
      content: SizedBox(
        width: 420,
        height: 390,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Complete the short security check to continue.',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: WebViewWidget(controller: _controller),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_error != null)
          FilledButton(onPressed: _retry, child: const Text('Try again')),
      ],
    );
  }
}
