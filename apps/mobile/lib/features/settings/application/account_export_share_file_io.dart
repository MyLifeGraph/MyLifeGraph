import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

class AccountExportShareFile {
  const AccountExportShareFile({required this.file, required this.directory});

  final XFile file;
  final Directory directory;

  Future<void> cleanup() async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Best effort: the dedicated root is cleared before the next export and
      // remains eligible for normal operating-system cache cleanup.
    }
  }
}

Future<AccountExportShareFile> createAccountExportShareFile({
  required String suggestedName,
  required Uint8List bytes,
  Directory? temporaryDirectory,
}) async {
  final cacheDirectory = temporaryDirectory ?? await getTemporaryDirectory();
  final separator = Platform.pathSeparator;
  final root = Directory(
    '${cacheDirectory.path}${separator}mylifegraph_account_export_share',
  );
  await _clearDedicatedRoot(root);
  final shareDirectory = Directory(
    '${root.path}$separator${DateTime.now().microsecondsSinceEpoch}',
  );
  await shareDirectory.create(recursive: true);
  final safeName = suggestedName.replaceAll(
    RegExp(r'[^A-Za-z0-9._-]'),
    '_',
  );
  final output = File('${shareDirectory.path}$separator$safeName');
  await output.writeAsBytes(bytes, flush: true);
  return AccountExportShareFile(
    file: XFile(output.path, mimeType: 'application/json'),
    directory: shareDirectory,
  );
}

Future<void> _clearDedicatedRoot(Directory root) async {
  try {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  } catch (_) {
    // Do not broaden deletion outside this dedicated cache directory. File
    // creation below still fails explicitly if the stale path blocks it.
  }
}
