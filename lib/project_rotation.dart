import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-Key (wird auch per Cloud-Sync übertragen).
const String kProjectRotationPrefKey = 'planner_project_rotation_v1';

/// Ein Projekt in der Rotation (z. B. Programmieren, Klavier, Portugiesisch).
class RotationProject {
  RotationProject({
    required this.id,
    required this.title,
    List<String>? variants,
    this.variantNext = 0,
  }) : variants = variants ?? [];

  final String id;
  String title;

  /// Abwechselnde Varianten (A/B …), z. B. Sprache → Portugiesisch, Serbisch.
  final List<String> variants;

  /// Welche Variante als Nächstes dran ist.
  int variantNext;

  bool get hasVariants => variants.isNotEmpty;

  String variantAt(int offset) {
    if (variants.isEmpty) return '';
    final n = variants.length;
    return variants[(((variantNext + offset) % n) + n) % n];
  }

  /// „Sprache · Portugiesisch“ bzw. nur der Titel.
  String labelAt(int variantOffset) =>
      hasVariants ? '$title · ${variantAt(variantOffset)}' : title;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (variants.isNotEmpty) 'variants': variants,
    if (variants.isNotEmpty) 'variantNext': variantNext,
  };

  factory RotationProject.fromJson(Map<String, dynamic> j) => RotationProject(
    id: ((j['id'] as String?) ?? '').trim(),
    title: ((j['title'] as String?) ?? '').trim(),
    variants: [
      for (final v in (j['variants'] as List? ?? const []))
        if (v is String && v.trim().isNotEmpty) v.trim(),
    ],
    variantNext: (j['variantNext'] as num?)?.toInt() ?? 0,
  );
}

/// Projekt-Rotation für „Projekt-Session“-Blöcke: wie „Als Nächstes“ bei Trainings-Routinen.
///
/// - [nextIndex] zeigt auf das Projekt, das als Nächstes dran ist.
/// - Wird eine Projekt-Session abgehakt, bekommt sie das aktuelle Projekt fest zugeordnet
///   ([assigned]) und die Rotation rückt eins weiter. Nach dem letzten geht es von vorn los.
/// - Wird nicht abgehakt (Tag ausgelassen), bleibt dasselbe Projekt „als Nächstes“.
class ProjectRotation {
  ProjectRotation({
    List<RotationProject>? items,
    this.nextIndex = 0,
    Map<String, String>? assigned,
    Map<String, SessionNote>? notes,
    Map<String, String>? assignedVariant,
  }) : items = items ?? [],
       assigned = assigned ?? {},
       notes = notes ?? {},
       assignedVariant = assignedVariant ?? {};

  /// `yyyy-mm-dd|blockId` → Variante, die in dieser Session dran war.
  final Map<String, String> assignedVariant;

  final List<RotationProject> items;
  int nextIndex;

  /// `yyyy-mm-dd|blockId` → Projekt-ID (nur für abgehakte Sessions).
  final Map<String, String> assigned;

  /// `yyyy-mm-dd|blockId` → Notiz zur Session (auch für noch offene Sessions).
  final Map<String, SessionNote> notes;

  bool get isEmpty => items.isEmpty;

  int get _safeNext =>
      items.isEmpty ? 0 : ((nextIndex % items.length) + items.length) % items.length;

  /// Projekt, das [offset] Sessions nach dem nächsten dran ist.
  RotationProject? upcoming([int offset = 0]) {
    if (items.isEmpty) return null;
    return items[(_safeNext + offset) % items.length];
  }

  /// Anzeige für die Session [offset] Sessions nach der nächsten (mit Variante).
  String? upcomingLabel([int offset = 0]) {
    final p = upcoming(offset);
    if (p == null) return null;
    if (!p.hasVariants) return p.title;
    var before = 0;
    for (var i = 0; i < offset; i++) {
      if (items[(_safeNext + i) % items.length].id == p.id) before++;
    }
    return p.labelAt(before);
  }

  /// Anzeige für eine abgehakte Session.
  String? doneLabel(DateTime day, String blockId) {
    final k = keyFor(day, blockId);
    final pid = assigned[k];
    if (pid == null) return null;
    final p = byId(pid);
    if (p == null) return null;
    final v = assignedVariant[k];
    return v == null || v.isEmpty ? p.title : '${p.title} · $v';
  }

  /// Variante setzen: Text wie „Portugiesisch / Serbisch“ (leer = keine).
  void setVariants(String id, List<String> vs) {
    final p = byId(id);
    if (p == null) return;
    p.variants
      ..clear()
      ..addAll(vs.map((e) => e.trim()).where((e) => e.isNotEmpty));
    p.variantNext = 0;
  }

  RotationProject? byId(String id) {
    for (final p in items) {
      if (p.id == id) return p;
    }
    return null;
  }

  static String keyFor(DateTime day, String blockId) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}|$blockId';

  /// Session abgehakt → aktuelles Projekt zuordnen und weiterrotieren.
  void markDone(DateTime day, String blockId) {
    if (items.isEmpty) return;
    final k = keyFor(day, blockId);
    if (assigned.containsKey(k)) return;
    final cur = items[_safeNext];
    assigned[k] = cur.id;
    if (cur.hasVariants) {
      assignedVariant[k] = cur.variantAt(0);
      cur.variantNext = (cur.variantNext + 1) % cur.variants.length;
    }
    final n = notes[k];
    if (n != null) notes[k] = SessionNote(projectId: assigned[k]!, text: n.text);
    nextIndex = (_safeNext + 1) % items.length;
    _trimAssigned();
  }

  /// Haken wieder entfernt → Zuordnung lösen; war es die letzte Rotation, zurückdrehen.
  void markUndone(DateTime day, String blockId) {
    final k = keyFor(day, blockId);
    final pid = assigned.remove(k);
    final v = assignedVariant.remove(k);
    if (pid == null || items.isEmpty) return;
    final prev = (_safeNext - 1 + items.length) % items.length;
    if (items[prev].id == pid) {
      nextIndex = prev;
      final p = items[prev];
      if (p.hasVariants && v != null) {
        final i = p.variants.indexOf(v);
        if (i >= 0) p.variantNext = i;
      }
    }
  }

  /// „Klavier“ oder mit Varianten „Sprache: Portugiesisch / Serbisch“.
  void add(String title) {
    var t = title.trim();
    if (t.isEmpty) return;
    var vs = <String>[];
    final c = t.indexOf(':');
    if (c > 0) {
      vs = t.substring(c + 1).split(RegExp(r'[/|,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      t = t.substring(0, c).trim();
      if (vs.length < 2) vs = [];
    }
    if (t.isEmpty) return;
    items.add(RotationProject(id: _newId(), title: t, variants: vs));
  }

  void remove(String id) {
    final idx = items.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final cur = _safeNext;
    items.removeAt(idx);
    if (items.isEmpty) {
      nextIndex = 0;
    } else if (idx < cur) {
      nextIndex = cur - 1;
    } else {
      nextIndex = cur % items.length;
    }
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= items.length) return;
    final nextId = upcoming()?.id;
    if (newIndex > oldIndex) newIndex -= 1;
    final p = items.removeAt(oldIndex);
    items.insert(newIndex.clamp(0, items.length), p);
    if (nextId != null) {
      final i = items.indexWhere((x) => x.id == nextId);
      if (i >= 0) nextIndex = i;
    }
  }

  void setNext(String id) {
    final i = items.indexWhere((p) => p.id == id);
    if (i >= 0) nextIndex = i;
  }

  /// Notiz für eine Session setzen (leer = löschen).
  void setNote(DateTime day, String blockId, String projectId, String text) {
    final k = keyFor(day, blockId);
    final t = text.trim();
    if (t.isEmpty) {
      notes.remove(k);
    } else {
      notes[k] = SessionNote(projectId: projectId, text: t);
    }
  }

  String noteFor(DateTime day, String blockId) =>
      notes[keyFor(day, blockId)]?.text ?? '';

  static DateTime? _dayOfKey(String k) {
    final d = k.split('|').first;
    return DateTime.tryParse(d);
  }

  /// Letzter Tag, an dem [projectId] abgehakt wurde.
  DateTime? lastDone(String projectId) {
    DateTime? best;
    assigned.forEach((k, v) {
      if (v != projectId) return;
      final d = _dayOfKey(k);
      if (d != null && (best == null || d.isAfter(best!))) best = d;
    });
    return best;
  }

  /// Erledigte Sessions eines Projekts, neueste zuerst (mit Notiz).
  List<SessionEntry> history(String projectId) {
    final out = <SessionEntry>[];
    assigned.forEach((k, v) {
      if (v != projectId) return;
      final d = _dayOfKey(k);
      if (d == null) return;
      out.add(SessionEntry(day: d, key: k, note: notes[k]?.text ?? ''));
    });
    out.sort((a, b) {
      final c = b.day.compareTo(a.day);
      return c != 0 ? c : b.key.compareTo(a.key);
    });
    return out;
  }

  /// Alte Zuordnungen begrenzen (nur Historie für die Anzeige abgehakter Blöcke).
  void _trimAssigned() {
    const maxEntries = 3000;
    if (assigned.length <= maxEntries) return;
    final keys = assigned.keys.toList()..sort();
    for (final k in keys.take(assigned.length - maxEntries)) {
      assigned.remove(k);
      notes.remove(k);
      assignedVariant.remove(k);
    }
  }

  Map<String, dynamic> toJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'nextIndex': nextIndex,
    'assigned': assigned,
    'notes': notes.map((k, v) => MapEntry(k, v.toJson())),
    if (assignedVariant.isNotEmpty) 'av': assignedVariant,
  };

  factory ProjectRotation.fromJson(Map<String, dynamic> j) {
    final items = <RotationProject>[];
    final raw = j['items'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final p = RotationProject.fromJson(Map<String, dynamic>.from(e));
          if (p.id.isNotEmpty && p.title.isNotEmpty) items.add(p);
        }
      }
    }
    final assigned = <String, String>{};
    final rawA = j['assigned'];
    if (rawA is Map) {
      rawA.forEach((k, v) {
        if (k is String && v is String) assigned[k] = v;
      });
    }
    final notes = <String, SessionNote>{};
    final rawN = j['notes'];
    if (rawN is Map) {
      rawN.forEach((k, v) {
        if (k is String && v is Map) {
          final n = SessionNote.fromJson(Map<String, dynamic>.from(v));
          if (n.text.isNotEmpty) notes[k] = n;
        }
      });
    }
    final av = <String, String>{};
    final rawV = j['av'];
    if (rawV is Map) {
      rawV.forEach((k, v) {
        if (k is String && v is String) av[k] = v;
      });
    }
    return ProjectRotation(
      items: items,
      nextIndex: (j['nextIndex'] as num?)?.toInt() ?? 0,
      assigned: assigned,
      notes: notes,
      assignedVariant: av,
    );
  }

  static Future<ProjectRotation> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kProjectRotationPrefKey);
      if (raw == null || raw.isEmpty) return ProjectRotation();
      final d = jsonDecode(raw);
      if (d is Map) return ProjectRotation.fromJson(Map<String, dynamic>.from(d));
    } catch (_) {}
    return ProjectRotation();
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kProjectRotationPrefKey, jsonEncode(toJson()));
    } catch (_) {}
  }

  static String _newId() =>
      'p_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
}

/// Notiz zu einer einzelnen Projekt-Session.
class SessionNote {
  const SessionNote({required this.projectId, required this.text});

  final String projectId;
  final String text;

  Map<String, dynamic> toJson() => {'p': projectId, 't': text};

  factory SessionNote.fromJson(Map<String, dynamic> j) => SessionNote(
    projectId: ((j['p'] as String?) ?? '').trim(),
    text: ((j['t'] as String?) ?? '').trim(),
  );
}

/// Eintrag im Verlauf eines Projekts.
class SessionEntry {
  const SessionEntry({required this.day, required this.key, required this.note});

  final DateTime day;
  final String key;
  final String note;
}

/// „Heute“, „Gestern“, „vor 3 Tagen“, „Noch nie“ — wie bei Trainings-Routinen.
String lastDoneLabel(DateTime? day, {DateTime? now}) {
  if (day == null) return 'Noch nie';
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(day.year, day.month, day.day);
  final diff = today.difference(d).inDays;
  if (diff <= 0) return 'Heute';
  if (diff == 1) return 'Gestern';
  if (diff < 7) return 'vor $diff Tagen';
  if (diff < 14) return 'vor 1 Woche';
  if (diff < 60) return 'vor ${diff ~/ 7} Wochen';
  final m = diff ~/ 30;
  return m < 12 ? 'vor $m Monaten' : 'vor über 1 Jahr';
}

/// Erkennt Projekt-Session-Blöcke am Titel: „Projekt-Session“, „Projekt Session“,
/// „Projekt“, „Projekte“, „Project Session“ (Groß/Klein egal).
bool isProjectSessionTitle(String title) {
  final t = title.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-–]+'), ' ');
  return t == 'projekt' ||
      t.startsWith('projekt circle') ||
      t.startsWith('project circle') ||
      t == 'circle' ||
      t.startsWith('circle block') ||
      t.startsWith('cyrcle') ||
      t.startsWith('work circle') ||
      t.startsWith('work cyrcle') ||
      t == 'projekte' ||
      t == 'project' ||
      t == 'projects' ||
      t.startsWith('projekt session') ||
      t.startsWith('projekte session') ||
      t.startsWith('project session');
}
