import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presentation/answer preference only; never changes Capture field semantics.
final assistantLanguageProvider =
    ChangeNotifierProvider.family<AssistantLanguage, String>(
      (ref, scope) => AssistantLanguage(scope),
    );

class AssistantLanguage extends ChangeNotifier {
  AssistantLanguage(this.scope) {
    ready = _load();
  }
  final String scope;
  late final Future<void> ready;
  String value = 'en';
  bool loading = true;
  bool failed = false;
  bool _disposed = false;
  String get _key => 'assistant_language_v1:$scope';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getString(_key) == 'de' ? 'de' : 'en';
    } catch (_) {
      failed = true;
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<bool> toggle() async {
    if (loading) return false;
    loading = true;
    notifyListeners();
    try {
      final next = value == 'en' ? 'de' : 'en';
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_key, next)) return false;
      value = next;
      failed = false;
      return true;
    } catch (_) {
      return false;
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
