export 'auth_captcha_platform_stub.dart'
    if (dart.library.js_interop) 'auth_captcha_platform_web.dart'
    if (dart.library.io) 'auth_captcha_platform_native.dart';
