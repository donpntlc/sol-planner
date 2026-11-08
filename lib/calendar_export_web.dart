import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Ruft `window.solSaveIcs` aus index.html auf (Download bzw. Teilen-Menü).
String saveIcsFile(String fileName, String ics, {bool share = false}) {
  try {
    final r = globalContext.callMethod<JSAny?>(
      'solSaveIcs'.toJS,
      fileName.toJS,
      ics.toJS,
      share.toJS,
    );
    if (r == null) return 'ok';
    return (r as JSString).toDart;
  } catch (_) {
    return 'error';
  }
}
