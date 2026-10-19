import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

double _read(String name) {
  try {
    final v = globalContext.getProperty<JSAny?>(name.toJS);
    if (v == null) return 0;
    return (v as JSNumber).toDartDouble;
  } catch (_) {
    return 0;
  }
}

/// Werte setzt index.html (`solSafeTop` usw., aus CSS `env(safe-area-inset-*)`).
EdgeInsets webSafeAreaInsets() => EdgeInsets.fromLTRB(
  _read('solSafeLeft'),
  _read('solSafeTop'),
  _read('solSafeRight'),
  _read('solSafeBottom'),
);
