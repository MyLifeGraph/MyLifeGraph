import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/app_updates/application/app_updates.dart';
import 'package:my_life_graph/features/app_updates/data/github_app_releases.dart';
import 'package:my_life_graph/features/app_updates/data/installed_app_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

const installed = InstalledAppVersion('0.1.0-pilot.1-rc.9', 109, 'certificate');
const tag = 'v0.1.0-pilot.1-rc.10';

Map<String, Object?> release({String name = tag, bool draft = false}) => {
  'tag_name': name,
  'draft': draft,
  'prerelease': true,
  'published_at': '2026-09-26T10:00:00Z',
  'assets': [
    for (final asset in [
      'release-metadata.json',
      'MyLifeGraph-$name.apk',
      'SHA256SUMS',
    ])
      {
        'name': asset,
        'state': 'uploaded',
        'size': 100,
        'browser_download_url':
            'https://github.com/MyLifeGraph/MyLifeGraph/releases/download/$name/$asset',
      },
  ],
};

Map<String, Object?> metadata({String name = tag, int code = 110}) => {
  'schema_version': 'mylifegraph-android-artifact-v1',
  'release_tag': name,
  'build_name': name.substring(1),
  'build_number': '$code',
  'release_sha': 'a' * 40,
  'signing_certificate_sha256': 'certificate',
};

GitHubAppReleases source({
  List<Object?>? list,
  Object? data,
  void Function(Uri)? onRead,
}) => GitHubAppReleases(
  read: (uri) async {
    onRead?.call(uri);
    return uri.host == 'api.github.com'
        ? (list ?? [release()])
        : (data ?? metadata());
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pilot prereleases use numeric build number and official APK', () async {
    final result = await source().newest(installed);
    expect(result?.code, 110);
    expect(
      result?.url.toString(),
      'https://github.com/MyLifeGraph/MyLifeGraph/releases/download/$tag/MyLifeGraph-$tag.apk',
    );
  });

  for (final code in [108, 109]) {
    test('same/older version $code never offers downgrade', () async {
      expect(
        await source(data: metadata(code: code)).newest(installed),
        isNull,
      );
    });
  }

  test('highest build wins regardless of API order or tag name', () async {
    final older = 'v0.1.0-pilot.1-rc.11';
    final api = GitHubAppReleases(
      read: (uri) async => uri.host == 'api.github.com'
          ? [release(name: older), release()]
          : metadata(
              name: uri.path.contains(older) ? older : tag,
              code: uri.path.contains(older) ? 109 : 110,
            ),
    );
    expect((await api.newest(installed))?.code, 110);
  });

  test(
    'drafts and incomplete assets are ignored without metadata calls',
    () async {
      final incomplete = release()..['assets'] = [];
      final requests = <Uri>[];
      final result = await source(
        list: [release(draft: true), incomplete, release()],
        onRead: requests.add,
      ).newest(installed);
      expect(result?.code, 110);
      expect(requests.length, 2);
    },
  );

  for (final invalid in <String, Object?>{
    'schema_version': 'other',
    'release_tag': 'v9.0.0',
    'build_name': 'wrong',
    'signing_certificate_sha256': 'wrong',
    'release_sha': 'bad',
    'build_number': 'not-a-number',
  }.entries) {
    test('rejects invalid ${invalid.key} without claiming current', () async {
      final data = metadata()..[invalid.key] = invalid.value;
      expect(source(data: data).newest(installed), throwsFormatException);
    });
  }

  test('arbitrary external download URL is never followed', () async {
    final item = release();
    ((item['assets'] as List).first as Map)['browser_download_url'] =
        'https://example.org/metadata';
    final requests = <Uri>[];
    await expectLater(
      source(list: [item], onRead: requests.add).newest(installed),
      throwsFormatException,
    );
    expect(requests.length, 1);
  });

  test('missing and duplicate APK fail closed', () async {
    final item = release();
    (item['assets'] as List).add((item['assets'] as List)[1]);
    await expectLater(
      source(list: [item]).newest(installed),
      throwsFormatException,
    );
    await expectLater(
      source(list: []).newest(installed),
      throwsFormatException,
    );
  });

  test('pagination includes older pages and fails closed at bound', () async {
    final pages = <String>[];
    final api = GitHubAppReleases(
      read: (uri) async {
        if (uri.host != 'api.github.com') return metadata();
        pages.add(uri.queryParameters['page']!);
        return pages.length == 1
            ? List.filled(100, {'draft': true})
            : [release()];
      },
    );
    expect((await api.newest(installed))?.code, 110);
    expect(pages, ['1', '2']);
    final endless = GitHubAppReleases(
      read: (_) async => List.filled(100, {'draft': true}),
    );
    await expectLater(endless.newest(installed), throwsFormatException);
  });

  test('native installed identity is read, not inferred from tag', () async {
    const channel = MethodChannel('com.mylifegraph.app/updates');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {
            'applicationId': 'com.mylifegraph.app',
            'versionName': 'main-test',
            'versionCode': 123,
            'certificateSha256': 'certificate',
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect((await readInstalledAppVersion()).code, 123);
  });

  test('checks deduplicate, throttle resume, but allow manual retry', () async {
    var requests = 0;
    final pending = Completer<InstalledAppVersion>();
    var time = DateTime(2026, 9, 26);
    final controller = AppUpdatesController(
      supported: true,
      readInstalled: () => pending.future,
      now: () => time,
      releases: source(onRead: (_) => requests++),
    );
    addTearDown(controller.dispose);
    final first = controller.check();
    final second = controller.check();
    expect(identical(first, second), isTrue);
    pending.complete(installed);
    await first;
    expect(controller.state.check, UpdateCheck.available);
    expect(requests, 2);
    await controller.check();
    expect(requests, 2);
    await controller.check(manual: true);
    expect(requests, 4);
    time = time.add(const Duration(hours: 7));
    await controller.check();
    expect(requests, 6);
  });

  test('network failure remains failed and manual retry succeeds', () async {
    var fail = true;
    final api = GitHubAppReleases(
      read: (uri) async {
        if (fail) throw StateError('offline');
        return uri.host == 'api.github.com' ? [release()] : metadata();
      },
    );
    final controller = AppUpdatesController(
      supported: true,
      readInstalled: () async => installed,
      releases: api,
    );
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.state.check, UpdateCheck.failed);
    fail = false;
    await controller.check(manual: true);
    expect(controller.state.check, UpdateCheck.available);
  });

  test('notice is persisted per build across controller recreation', () async {
    AppUpdatesController make() => AppUpdatesController(
      supported: true,
      readInstalled: () async => installed,
      releases: source(),
    );
    final controller = make();
    final update = (await source().newest(installed))!;
    expect(await controller.claimNotice(update), isTrue);
    expect(await controller.claimNotice(update), isFalse);
    controller.dispose();
    final restarted = make();
    addTearDown(restarted.dispose);
    expect(await restarted.claimNotice(update), isFalse);
    expect(
      await restarted.claimNotice(
        AppUpdate(name: 'new', code: 111, url: update.url),
      ),
      isTrue,
    );
    expect(await restarted.claimNotice(update), isFalse);
  });

  test('unsupported platform makes no network/native calls', () async {
    final controller = AppUpdatesController(
      supported: false,
      readInstalled: () => throw StateError('must not read'),
      releases: GitHubAppReleases(
        read: (_) => throw StateError('must not call'),
      ),
    );
    addTearDown(controller.dispose);
    await controller.check(manual: true);
    expect(controller.state.check, UpdateCheck.idle);
  });
}
