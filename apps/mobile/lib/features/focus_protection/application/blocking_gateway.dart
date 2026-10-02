import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/blocking_plan.dart';

const blockingPlansContractVersion = 'blocking-plans-v2';

class BlockingSnapshot {
  BlockingSnapshot(Map map)
    : revision = map['revision'] as int,
      plans = (map['plans'] as List)
          .map((v) => BlockingPlan.fromMap(v as Map))
          .toList(),
      strict = Map<String, Object>.from(map['strict'] as Map),
      custom = Map<String, Object>.from(map['custom'] as Map),
      locked = map['locked'] as bool,
      remainingMs = map['remainingMs'] as int,
      unlockStarted = map['unlockStarted'] as bool? ?? false,
      releaseRemainingMs = map['releaseRemainingMs'] as int? ?? 0,
      websiteConsent = map['websiteConsent'] as bool,
      usageConsent = map['usageConsent'] as bool? ?? false,
      usageGranted = map['usageGranted'] as bool,
      nfcAvailable = map['nfcAvailable'] as bool,
      nfcEnrolled = map['nfcEnrolled'] as bool,
      wifiReady = map['wifiReady'] as bool,
      attemptsToday = map['attemptsToday'] as int,
      attemptsTotal = map['attemptsTotal'] as int;
  final int revision,
      remainingMs,
      attemptsToday,
      attemptsTotal,
      releaseRemainingMs;
  final List<BlockingPlan> plans;
  final Map<String, Object> strict, custom;
  final bool locked,
      websiteConsent,
      usageConsent,
      usageGranted,
      nfcAvailable,
      nfcEnrolled,
      wifiReady;
  final bool unlockStarted;
}

class BlockingGateway {
  const BlockingGateway({
    this.channel = const MethodChannel('com.mylifegraph.app/blocking_v2'),
  });
  final MethodChannel channel;
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    final value = await channel.invokeMapMethod<Object?, Object?>(name, args);
    if (value == null) {
      throw const FormatException('Blocking settings unavailable.');
    }
    if (value['contractVersion'] != blockingPlansContractVersion) {
      throw const FormatException(
        'Update the Android app to use blocking plans.',
      );
    }
    return BlockingSnapshot(value);
  }

  Future<void> open(String name) => channel.invokeMethod<void>(name);
  Future<List<Map>> catalog() async =>
      (await channel.invokeListMethod<Map>('catalog') ?? const []).toList();
  Future<Map> insights(int days) async =>
      await channel.invokeMapMethod<Object?, Object?>('insights', {
        'days': days,
      }) ??
      const {};
}

final blockingGatewayProvider = Provider<BlockingGateway>(
  (ref) => const BlockingGateway(),
);
