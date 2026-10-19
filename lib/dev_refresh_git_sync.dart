// Conditional entry: no-op on mobile/desktop, web implementation only when dart:html is available.
import 'dev_refresh_git_sync_stub.dart'
    if (dart.library.html) 'dev_refresh_git_sync_web.dart' as _impl;

/// Debug-only: every 3rd full page load in the web app notifies the local dev server to push to GitHub.
void devRefreshGitSyncOnWebStartup() => _impl.devRefreshGitSyncOnWebStartup();
