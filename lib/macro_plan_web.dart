import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Öffnet die Dateiauswahl (window.solPickJsonFile in index.html) und liefert den Text.
/// Muss direkt im Tipp aufgerufen werden, sonst blockt das iPhone die Auswahl.
Future<String?> pickJsonFileText() async {
  try {
    final p = globalContext.callMethod<JSPromise<JSAny?>>(
      'solPickJsonFile'.toJS,
    );
    final r = await p.toDart;
    if (r == null) return null;
    return (r as JSString).toDart;
  } catch (_) {
    return null;
  }
}
