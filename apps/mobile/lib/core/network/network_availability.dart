import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = Provider<Connectivity>((_) => Connectivity());

final networkAvailableProvider = StreamProvider<bool>((ref) async* {
  final connectivity = ref.watch(connectivityProvider);
  yield _hasNetwork(await connectivity.checkConnectivity());
  await for (final results in connectivity.onConnectivityChanged) {
    yield _hasNetwork(results);
  }
});

bool _hasNetwork(List<ConnectivityResult> results) {
  return results.isNotEmpty && !results.contains(ConnectivityResult.none);
}
