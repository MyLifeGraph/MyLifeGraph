import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import '../domain/app_update.dart';

const _repository = 'MyLifeGraph/MyLifeGraph';

/// Public GitHub only. This transport never receives application credentials.
class GitHubAppReleases {
  GitHubAppReleases({Future<Object?> Function(Uri)? read}) : _read = read;
  final Future<Object?> Function(Uri)? _read;

  Future<AppUpdate?> newest(InstalledAppVersion installed) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        responseType: ResponseType.plain,
        headers: {'Accept': 'application/vnd.github+json'},
      ),
    );
    final cancel = CancelToken();
    final timer = Timer(const Duration(seconds: 30), () => cancel.cancel());
    Future<Object?> read(Uri uri) async {
      if (_read != null) return _read(uri);
      final response = await dio.get<String>(
        uri.toString(),
        cancelToken: cancel,
      );
      final text = response.data ?? '';
      if (text.length > 2000000) {
        throw const FormatException('Release response too large');
      }
      return jsonDecode(text);
    }

    AppUpdate? newest;
    var compatible = false;
    try {
      // Paginate rather than relying on /latest, which excludes pilot releases.
      for (var page = 1; page <= 3; page++) {
        final releases = await read(
          Uri.https('api.github.com', '/repos/$_repository/releases', {
            'per_page': '100',
            'page': '$page',
          }),
        );
        if (releases is! List) throw const FormatException('Invalid releases');
        for (final release in releases) {
          if (release is! Map ||
              release['draft'] != false ||
              release['published_at'] is! String) {
            continue;
          }
          final tag = release['tag_name'];
          if (tag is! String ||
              !RegExp(
                r'^v\d+\.\d+\.\d+(?:-pilot\.\d+-rc\.\d+)?$',
              ).hasMatch(tag)) {
            continue;
          }
          final assets = release['assets'];
          if (assets is! List) continue;
          String? asset(String name) {
            final matches = assets
                .whereType<Map>()
                .where(
                  (item) =>
                      item['name'] == name &&
                      item['state'] == 'uploaded' &&
                      item['size'] is num &&
                      (item['size'] as num) > 0,
                )
                .toList();
            if (matches.length != 1) return null;
            final expected =
                'https://github.com/$_repository/releases/download/$tag/$name';
            return matches.single['browser_download_url'] == expected
                ? expected
                : null;
          }

          final metadataUrl = asset('release-metadata.json');
          final apkUrl = asset('MyLifeGraph-$tag.apk');
          if (metadataUrl == null ||
              apkUrl == null ||
              asset('SHA256SUMS') == null) {
            continue;
          }
          final metadata = await read(Uri.parse(metadataUrl));
          if (metadata is! Map ||
              metadata['schema_version'] != 'mylifegraph-android-artifact-v1' ||
              metadata['release_tag'] != tag ||
              metadata['build_name'] != tag.substring(1) ||
              metadata['signing_certificate_sha256'] != installed.certificate ||
              metadata['release_sha'] is! String ||
              !RegExp(
                r'^[0-9a-f]{40}$',
              ).hasMatch(metadata['release_sha'] as String)) {
            continue;
          }
          final code = int.tryParse('${metadata['build_number']}');
          if (code == null || code <= 0 || code > 2100000000) continue;
          compatible = true;
          if (code > installed.code && (newest == null || code > newest.code)) {
            newest = AppUpdate(
              name: tag.substring(1),
              code: code,
              url: Uri.parse(apkUrl),
            );
          }
        }
        if (releases.length < 100) break;
        if (page == 3) throw const FormatException('Release list incomplete');
      }
      if (!compatible) {
        throw const FormatException('No compatible release metadata');
      }
      return newest;
    } finally {
      timer.cancel();
      dio.close(force: true);
    }
  }
}
