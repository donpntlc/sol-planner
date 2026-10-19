import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _kStorageKey = 'dev_git_sync_refresh_count';
const _kDefaultPort = 18765;
const _kSyncPath = 'git-sync';

void devRefreshGitSyncOnWebStartup() {
  if (!kDebugMode) return;

  final storage = html.window.localStorage;
  var n = int.tryParse(storage[_kStorageKey] ?? '0') ?? 0;
  n++;
  storage[_kStorageKey] = '$n';
  if (n % 3 != 0) return;

  final uri = Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _kDefaultPort,
    path: _kSyncPath,
  );

  http
      .post(
        uri,
        headers: const {'X-Dev-Git-Sync': '1', 'Content-Type': 'text/plain'},
      )
      .timeout(const Duration(seconds: 20))
      .then(
        (r) {
          debugPrint('Dev git sync: ${r.statusCode} ${r.body}');
        },
        onError: (Object e) {
          debugPrint(
            'Dev git sync skipped (start scripts/dev_git_sync_server.ps1): $e',
          );
        },
      );
}
