import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/phone_lock.dart';
import 'blocking_gateway.dart';

class PhoneLockGateway {
  const PhoneLockGateway({
    this.channel = const MethodChannel('com.mylifegraph.app/blocking_v2'),
  });
  final MethodChannel channel;
  Future<PhoneLockStatus> status() => _read('phoneLockStatus');
  Future<PhoneLockStatus> start(
    PhoneLockOptions options,
    String requestId, {
    DateTime? focusEndsAt,
  }) => _read(
    'phoneLockStart',
    options.arguments(requestId, focusEndsAt: focusEndsAt),
  );
  Future<void> control({bool scan = false}) =>
      channel.invokeMethod<void>('phoneLockControl', {'scan': scan});
  Future<void> phone() => channel.invokeMethod<void>('phoneLockPhone');
  Future<PhoneLockStatus> _read(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    final value = await channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    if (value == null ||
        value['contractVersion'] != blockingPlansContractVersion) {
      throw const FormatException('Update the Android app to use Phone lock.');
    }
    return PhoneLockStatus.fromMap(value);
  }
}

final phoneLockGatewayProvider = Provider<PhoneLockGateway>(
  (ref) => const PhoneLockGateway(),
);

String phoneLockError(Object error) => error is PlatformException
    ? error.message ?? 'Phone lock unavailable. Try again.'
    : 'Phone lock unavailable. Check permissions and try again.';
