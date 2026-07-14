import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/account_settings.dart';
import 'account_export_share_file_stub.dart'
    if (dart.library.io) 'account_export_share_file_io.dart';

abstract interface class AccountExportSaver {
  Future<AccountExportSaveResult> save({
    required String suggestedName,
    required AccountExportEnvelope export,
    Rect? sharePositionOrigin,
  });
}

class PlatformAccountExportSaver implements AccountExportSaver {
  const PlatformAccountExportSaver();

  @override
  Future<AccountExportSaveResult> save({
    required String suggestedName,
    required AccountExportEnvelope export,
    Rect? sharePositionOrigin,
  }) async {
    final bytes = export.fileBytes;
    if (usesMobileAccountExportShareSheet(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      final source = await createAccountExportShareFile(
        suggestedName: suggestedName,
        bytes: bytes,
      );
      try {
        final result = await Share.shareXFiles(
          [source.file],
          subject: 'MyLifeGraph account export',
          sharePositionOrigin: sharePositionOrigin,
          fileNameOverrides: [suggestedName],
        );
        return result.status == ShareResultStatus.dismissed
            ? AccountExportSaveResult.shareDismissed
            : AccountExportSaveResult.shared;
      } finally {
        await source.cleanup();
      }
    }

    final file = XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: suggestedName,
    );
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (location == null) {
      return AccountExportSaveResult.cancelled;
    }
    await file.saveTo(location.path);
    return AccountExportSaveResult.saved;
  }
}

bool usesMobileAccountExportShareSheet({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return !isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
}
