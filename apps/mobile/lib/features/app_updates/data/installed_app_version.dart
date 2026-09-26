import 'package:flutter/services.dart';
import '../domain/app_update.dart';

const _channel = MethodChannel('com.mylifegraph.app/updates');

Future<InstalledAppVersion> readInstalledAppVersion() async {
  final value = await _channel.invokeMapMethod<String, dynamic>(
    'installedVersion',
  );
  if (value == null ||
      value['applicationId'] != 'com.mylifegraph.app' ||
      value['versionName'] is! String ||
      value['versionCode'] is! int ||
      value['certificateSha256'] is! String) {
    throw const FormatException('Installed version unavailable');
  }
  return InstalledAppVersion(
    value['versionName'] as String,
    value['versionCode'] as int,
    value['certificateSha256'] as String,
  );
}
