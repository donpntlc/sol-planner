import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-Key (wird auch per Cloud-Sync übertragen).
const String kProjectRotationPrefKey = 'planner_project_rotation_v1';

/// Ein Projekt in der Rotation (z. B. Programmieren, Klavier, Portugiesisch).
class RotationProject {
  RotationProject({required this.id, required this.title});

  final String id;
  String title;

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  factory RotationProject.fromJson(Map<String, dynamic> j) => RotationProject(
    id: ((j['id'] as String?) ?? '').trim(),
    title: ((j['title'] as String?) ?? '').trim(),
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
  }) : items = items ?? [],
       assigned = assigned ?? {};

  final List<RotationProject> items;
  int nextIndex;

  /// `yyyy-mm-dd|blockId` → Projekt-ID (nur für abgehakte Sessions).
  final Map<String, String> assigned;

  bool get isEmpty => items.isEmpty;

  int get _safeNext =>
      items.isEmpty ? 0 : ((nextIndex % items.length) + items.length) % items.length;

  /// Projekt, das [offset] Sessions nach dem nächsten dran ist.
  RotationProject? upcoming([int offset = 0]) {
    if (items.isEmpty) return null;
    return items[(_safeNext + offset) % items.length];
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
    assigned[k] = items[_safeNext].id;
    nextIndex = (_safeNext + 1) % items.length;
    _trimAssigned();
  }

  /// Haken wieder entfernt → Zuordnung lösen; war es die letzte Rotation, zurückdrehen.
  void markUndone(DateTime day, String blockId) {
    final k = keyFor(day, blockId);
    final pid = assigned.remove(k);
    if (pid == null || items.isEmpty) return;
    final prev = (_safeNext - 1 + items.length) % items.length;
    if (items[prev].id == pid) nextIndex = prev;
  }

  void add(String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    items.add(RotationProject(id: _newId(), title: t));
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

  /// Alte Zuordnungen begrenzen (nur Historie für die Anzeige abgehakter Blöcke).
  void _trimAssigned() {
    const maxEntries = 400;
    if (assigned.length <= maxEntries) return;
    final keys = assigned.keys.toList()..sort();
    for (final k in keys.take(assigned.length - maxEntries)) {
      assigned.remove(k);
    }
  }

  Map<String, dynamic> toJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'nextIndex': nextIndex,
    'assigned': assigned,
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
    return ProjectRotation(
      items: items,
      nextIndex: (j['nextIndex'] as num?)?.toInt() ?? 0,
      assigned: assigned,
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

/// Erkennt Projekt-Session-Blöcke am Titel: „Projekt-Session“, „Projekt Session“,
/// „Projekt“, „Projekte“, „Project Session“ (Groß/Klein egal).
bool isProjectSessionTitle(String title) {
  final t = title.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-–]+'), ' ');
  return t == 'projekt' ||
      t == 'projekte' ||
      t == 'project' ||
      t == 'projects' ||
      t.startsWith('projekt session') ||
      t.startsWith('projekte session') ||
      t.startsWith('project session');
}
