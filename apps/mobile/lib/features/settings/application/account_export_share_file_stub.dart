import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class AccountExportShareFile {
  const AccountExportShareFile(this.file);

  final XFile file;

  Future<void> cleanup() async {}
}

Future<AccountExportShareFile> createAccountExportShareFile({
  required String suggestedName,
  required Uint8List bytes,
}) async {
  return AccountExportShareFile(
    XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: suggestedName,
    ),
  );
}
