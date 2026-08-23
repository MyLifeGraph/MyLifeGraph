enum AuthCaptchaAction {
  signIn('signin'),
  signUp('signup'),
  passwordReset('password_reset'),
  signupResend('signup_resend');

  const AuthCaptchaAction(this.wireValue);

  final String wireValue;
}

class AuthCaptchaException implements Exception {
  const AuthCaptchaException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? validateAuthCaptchaToken({
  required bool requiredForEnvironment,
  String? token,
}) {
  if (!requiredForEnvironment && token == null) return null;
  if (token == null ||
      token.isEmpty ||
      token.length > 2048 ||
      token.trim() != token ||
      token.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw const AuthCaptchaException(
      'A fresh CAPTCHA verification is required for this request.',
    );
  }
  return token;
}
