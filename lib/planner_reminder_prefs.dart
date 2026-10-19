import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sol/cloud/sol_planner_sync_hook.dart';

const String _kPlannerReminderPrefsKey = 'planner_reminder_prefs_v1';

/// 1=Aus · 2=Benachrichtigung (Ton+Vibration) · 3=Wecker (starker Kanal).
enum PlannerReminderMode { off, notification, alarm }

/// Ob die sanfte Variante zusätzlich per OS geplant wird (nicht nur in der geöffneten App).
enum PlannerOsReminderSurface {
  lockScreenAndBanner,
  foregroundAppOnly,
}

enum PlannerAlarmToneCategory { radical, calm }

class PlannerReminderPrefs {
  const PlannerReminderPrefs({
    required this.mode,
    required this.gentleSurface,
    required this.gentleRemindBeforeStart,
    required this.beforeOffsetsMinutes,
    required this.remindSessionEnd,
    required this.alarmCategory,
    required this.alarmToneIndex,
    required this.snoozeChoicesMinutes,
    this.alarmRestrictBlocks = false,
    this.alarmEnabledBlockIds = const {},
  });

  factory PlannerReminderPrefs.defaults() => PlannerReminderPrefs(
    mode: PlannerReminderMode.notification,
    gentleSurface: PlannerOsReminderSurface.lockScreenAndBanner,
    gentleRemindBeforeStart: true,
    beforeOffsetsMinutes: const [5],
    remindSessionEnd: false,
    alarmCategory: PlannerAlarmToneCategory.calm,
    alarmToneIndex: 0,
    snoozeChoicesMinutes: const [5, 10, 15],
    alarmRestrictBlocks: false,
    alarmEnabledBlockIds: const {},
  );

  final PlannerReminderMode mode;

  /// Gilt nur für Modus „Benachrichtigung“ für **geplante OS-Mitteilungen**.
  /// Bei Sperrbildschirm+Bannertext: keine Doppel‑Haptics vom Ticker — die OS‑Benachrichtigung liefert die Wahrnehmbarkeit; Vibration/Klick beim Ticker bleiben für „nur wenn App geöffnet“ und für Web aktiv.
  final PlannerOsReminderSurface gentleSurface;

  /// „Vorher erinnern“ (Offsets in Min vor Blockstart, max 3).
  final bool gentleRemindBeforeStart;
  final List<int> beforeOffsetsMinutes;

  /// Zusätzlich zum Block-Ende erinnern (zählt in die Höchstzahl 3 mit ein).
  final bool remindSessionEnd;

  final PlannerAlarmToneCategory alarmCategory;
  /// 0…3 für vorgegebene Klänge/Kanäle (ohne eigene Mediendatei).
  final int alarmToneIndex;

  /// Minuten nach „Verschieben“ / Snooze beim Wecker (Android‑Aktionen).
  final List<int> snoozeChoicesMinutes;

  /// Wenn false: Wecker gilt für alle erinnerungsfähigen Blöcke (wie bisher).
  /// Wenn true: nur Blöcke mit Id in [alarmEnabledBlockIds].
  final bool alarmRestrictBlocks;

  /// Nur ausgewertet wenn [alarmRestrictBlocks] true.
  final Set<String> alarmEnabledBlockIds;

  bool alarmTargetsBlock(String blockId) =>
      !alarmRestrictBlocks || alarmEnabledBlockIds.contains(blockId);

  /// Normalisierte Offsets vor Start — max 3, wenn `remindSessionEnd` Platz braucht, gekürzt.
  List<int> normalizedBeforeOffsetsForCap() {
    final raw =
        List<int>.from(beforeOffsetsMinutes).map((x) => x.clamp(1, 720)).toSet().toList()..sort();
    var cap = 3;
    if (remindSessionEnd) cap = 2;
    if (gentleRemindBeforeStart && raw.length > cap) return raw.take(cap).toList();
    if (!gentleRemindBeforeStart) return const [];
    return raw.take(cap).toList();
  }

  PlannerReminderPrefs copyWith({
    PlannerReminderMode? mode,
    PlannerOsReminderSurface? gentleSurface,
    bool? gentleRemindBeforeStart,
    List<int>? beforeOffsetsMinutes,
    bool? remindSessionEnd,
    PlannerAlarmToneCategory? alarmCategory,
    int? alarmToneIndex,
    List<int>? snoozeChoicesMinutes,
    bool? alarmRestrictBlocks,
    Set<String>? alarmEnabledBlockIds,
  }) {
    return PlannerReminderPrefs(
      mode: mode ?? this.mode,
      gentleSurface: gentleSurface ?? this.gentleSurface,
      gentleRemindBeforeStart: gentleRemindBeforeStart ?? this.gentleRemindBeforeStart,
      beforeOffsetsMinutes: beforeOffsetsMinutes ?? List<int>.from(this.beforeOffsetsMinutes),
      remindSessionEnd: remindSessionEnd ?? this.remindSessionEnd,
      alarmCategory: alarmCategory ?? this.alarmCategory,
      alarmToneIndex: alarmToneIndex ?? this.alarmToneIndex,
      snoozeChoicesMinutes: snoozeChoicesMinutes ?? List<int>.from(this.snoozeChoicesMinutes),
      alarmRestrictBlocks: alarmRestrictBlocks ?? this.alarmRestrictBlocks,
      alarmEnabledBlockIds:
          alarmEnabledBlockIds != null ? Set<String>.from(alarmEnabledBlockIds) : Set<String>.from(this.alarmEnabledBlockIds),
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.index,
    'gentleSurface': gentleSurface.index,
    'gentleBefore': gentleRemindBeforeStart,
    'offsets': List<int>.from(beforeOffsetsMinutes),
    'end': remindSessionEnd,
    'alarmCat': alarmCategory.index,
    'alarmToneIx': alarmToneIndex,
    'snooze': List<int>.from(snoozeChoicesMinutes),
    'alarmRestrict': alarmRestrictBlocks,
    'alarmIds': alarmEnabledBlockIds.toList()..sort(),
  };

  factory PlannerReminderPrefs.fromJson(Map<String, dynamic> j) {
    PlannerReminderMode m(int v, PlannerReminderMode def) =>
        v >= 0 && v < PlannerReminderMode.values.length ? PlannerReminderMode.values[v] : def;
    PlannerOsReminderSurface s(int v, PlannerOsReminderSurface def) =>
        v >= 0 && v < PlannerOsReminderSurface.values.length
            ? PlannerOsReminderSurface.values[v]
            : def;
    PlannerAlarmToneCategory c(int v, PlannerAlarmToneCategory def) =>
        v >= 0 && v < PlannerAlarmToneCategory.values.length
            ? PlannerAlarmToneCategory.values[v]
            : def;

    final rawOff = j['offsets'];
    final offs = <int>[];
    if (rawOff is List) {
      for (final e in rawOff) {
        if (e is int) offs.add(e);
        if (e is num) offs.add(e.toInt());
      }
    }
    if (offs.isEmpty) offs.add(5);
    offs.sort();

    final rawAlarm = j['alarmIds'];
    final alarmIds = <String>{};
    if (rawAlarm is List) {
      for (final e in rawAlarm) {
        if (e is String && e.isNotEmpty) alarmIds.add(e);
      }
    }

    final rawSn = j['snooze'];
    final snooze = <int>[];
    if (rawSn is List) {
      for (final e in rawSn) {
        if (e is int) snooze.add(e.clamp(1, 180));
        if (e is num) snooze.add(e.toInt().clamp(1, 180));
      }
    }
    return PlannerReminderPrefs(
      mode: m((j['mode'] as num?)?.toInt() ?? -1, PlannerReminderPrefs.defaults().mode),
      gentleSurface:
          s((j['gentleSurface'] as num?)?.toInt() ?? -1, PlannerReminderPrefs.defaults().gentleSurface),
      gentleRemindBeforeStart: (j['gentleBefore'] as bool?) ?? true,
      beforeOffsetsMinutes: offs.take(3).toList(),
      remindSessionEnd: (j['end'] as bool?) ?? false,
      alarmCategory: c((j['alarmCat'] as num?)?.toInt() ?? -1, PlannerAlarmToneCategory.calm),
      alarmToneIndex: ((j['alarmToneIx'] as num?)?.toInt() ?? 0).clamp(0, 3),
      snoozeChoicesMinutes:
          snooze.isEmpty ? PlannerReminderPrefs.defaults().snoozeChoicesMinutes : snooze.take(6).toList(),
      alarmRestrictBlocks: (j['alarmRestrict'] as bool?) ?? false,
      alarmEnabledBlockIds: alarmIds,
    );
  }
}

Future<PlannerReminderPrefs> loadPlannerReminderPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPlannerReminderPrefsKey);
    if (raw == null || raw.isEmpty) return PlannerReminderPrefs.defaults();
    final m = jsonDecode(raw);
    if (m is Map<String, dynamic>) return PlannerReminderPrefs.fromJson(m);
  } catch (_) {}
  return PlannerReminderPrefs.defaults();
}

Future<void> savePlannerReminderPrefs(PlannerReminderPrefs p) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPlannerReminderPrefsKey, jsonEncode(p.toJson()));
  } catch (_) {}
  solNotifyPlannerDiskDataChanged();
}
