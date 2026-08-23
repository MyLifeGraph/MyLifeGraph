import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/settings/application/account_export_share_file_io.dart';

void main() {
  test('mobile export source replaces stale cache and cleans its own file',
      () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'mylifegraph-export-test-',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final dedicatedRoot = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}'
      'mylifegraph_account_export_share',
    );
    await dedicatedRoot.create(recursive: true);
    final stale = File(
      '${dedicatedRoot.path}${Platform.pathSeparator}stale.json',
    );
    await stale.writeAsString('stale');

    final source = await createAccountExportShareFile(
      suggestedName: '../unsafe export.json',
      bytes: Uint8List.fromList([1, 2, 3]),
      temporaryDirectory: temporaryDirectory,
    );

    expect(await stale.exists(), isFalse);
    expect(source.file.path, startsWith(dedicatedRoot.path));
    expect(source.file.path, endsWith('.._unsafe_export.json'));
    expect(await File(source.file.path).readAsBytes(), [1, 2, 3]);

    await source.cleanup();

    expect(await source.directory.exists(), isFalse);
  });
}
