// Side effect when loaded (before [main] runs): web debug 3-refresh → local git push helper.
// Requires `scripts/dev_git_sync_server.ps1` in a second terminal. See that script for details.

import 'package:sol/dev_refresh_git_sync.dart' as dev_sync;

// ignore: unused_element, unused_field
final Object? _kDevSyncAuto = () {
  dev_sync.devRefreshGitSyncOnWebStartup();
  return null;
}();
