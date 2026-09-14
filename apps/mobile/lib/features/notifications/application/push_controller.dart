import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/client_uuid.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/platform/push_platform.dart';
import '../domain/entities/push_settings.dart';

class PushView {
  const PushView({
    this.cloud,
    this.busy = false,
    this.error,
    this.granted = false,
    this.configured = false,
  });
  final PushSettingsState? cloud;
  final bool busy;
  final String? error;
  final bool granted;
  final bool configured;
}

class PushController extends StateNotifier<PushView> {
  PushController(
    this.api,
    this.platform,
    this.token,
    this.owner,
    this.sessionId, {
    required this.android,
  }) : super(const PushView());
  final ApiClient api;
  final PushPlatform platform;
  final String Function() token;
  final String owner;
  final String sessionId;
  final bool android;
  String? _lastToken;
  Map<String, dynamic> _native = {};
  Map<String, String> get _headers => {'Authorization': 'Bearer ${token()}'};

  Future<void> refresh() => _run(() async {
    if (android) {
      _native = Map<String, dynamic>.from(
        await platform.call<Map>('bind', {
              'owner': owner,
              'session_id': sessionId,
            }) ??
            {},
      );
    }
    final cloud = PushSettingsState.parse(
      await api.getJson('/v1/push', headers: _headers),
    );
    if (!mounted) return;
    state = PushView(
      cloud: cloud,
      busy: true,
      granted: _native['granted'] == true,
      configured: _native['configured'] == true,
    );
    await _registerIfAllowed();
  });

  Future<void> save(Map<String, dynamic> draft, int expectedRevision) => _run(
    () async {
      if (draft['enabled'] == true) {
        if (!android || state.cloud?.available != true || !state.configured) {
          throw StateError('Not available');
        }
        final granted = await platform.call<bool>('requestPermission') == true;
        if (!granted) throw StateError('Android permission is off');
        _native['granted'] = true;
      }
      if (!mounted) return;
      if (android) await platform.call<void>('pause');
      await _command({
        'command': 'settings',
        'consent_version': pushConsentVersion,
        'expected_revision': expectedRevision,
        ...draft,
      });
      _lastToken = null;
      if (mounted) await _registerIfAllowed();
    },
  );

  Future<void> _registerIfAllowed() async {
    final cloud = state.cloud;
    if (!android || cloud == null) return;
    if (!cloud.enabled ||
        !cloud.available ||
        _native['granted'] != true ||
        _native['configured'] != true) {
      await platform.call<void>('pause');
      return;
    }
    final currentToken = await platform.call<String>('token');
    if (!mounted || currentToken == null) return;
    if (_lastToken != currentToken ||
        cloud.json['device_id'] != _native['device_id'] ||
        cloud.json['registration_id'] != _native['registration_id']) {
      await _command({
        'command': 'register',
        'device_id': _native['device_id'],
        'registration_id': _native['registration_id'],
        'token': currentToken,
      });
      if (!mounted) return;
      _lastToken = currentToken;
    }
    await platform.call<void>('activate', {
      'registration_id': _native['registration_id'],
    });
  }

  Future<void> _command(Map<String, dynamic> body) async {
    if (!mounted) return;
    final cloud = PushSettingsState.parse(
      await api.postJson(
        '/v1/push',
        headers: _headers,
        body: {
          'contract_version': pushContractVersion,
          'request_id': newClientUuid(),
          'expected_revision': state.cloud!.revision,
          ...body,
        },
      ),
    );
    if (mounted) {
      state = PushView(
        cloud: cloud,
        busy: true,
        granted: _native['granted'] == true,
        configured: _native['configured'] == true,
      );
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (!mounted || state.busy) return;
    state = PushView(
      cloud: state.cloud,
      busy: true,
      granted: state.granted,
      configured: state.configured,
    );
    try {
      await work();
      if (mounted) {
        state = PushView(
          cloud: state.cloud,
          granted: _native['granted'] == true,
          configured: _native['configured'] == true,
        );
      }
    } catch (_) {
      if (mounted) {
        state = PushView(
          cloud: state.cloud,
          granted: _native['granted'] == true,
          configured: _native['configured'] == true,
          error:
              'Push could not be confirmed. Check Android permissions, then reload.',
        );
      }
    }
  }
}
