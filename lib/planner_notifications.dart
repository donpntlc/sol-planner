import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:sol/planner_reminder_prefs.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Kompakte Blockdaten für Erinnerungen — bewusst ohne [TimeBlock], damit es kein
/// Zirkelimport mit `main.dart` gibt.
class PlannerReminderSlice {
  const PlannerReminderSlice({
    required this.id,
    required this.title,
    required this.startMin,
    required this.endMin,
    required this.allDay,
    required this.shouldRemind,
    this.muteReminders = false,
  });

  final String id;
  final String title;
  final int startMin;
  /// Endminute am selben Kalendertag (wie [TimeBlock.endMin] bei linearen Slots).
  final int endMin;
  final bool allDay;

  /// Basis-Eignung (nicht erledigt, linear, kein Ganztag …).
  final bool shouldRemind;

  /// Pro Block: keine Erinnerungen.
  final bool muteReminders;

  bool get wantsReminders => shouldRemind && !muteReminders;
}

const int _kPlannerNotifIdBase = 8_600_000;
const int _kPlannerSnoozeIdBase = 8_730_000;

const String _channelGentle = 'planner_reminder_gentle';
const String _channelAlarmRad = 'planner_alarm_radical';
const String _channelAlarmCalm = 'planner_alarm_calm';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

bool _inited = false;
bool _tzReady = false;
bool _androidChannelsReady = false;
/// Serialisiert [rescheduleTodayReminders] — parallele Aufrufe können sonst kurz doppelte Slots planen.
bool _rescheduleRemindersBusy = false;

final List<int> _plannerSlotIds = [];
final List<int> _snoozeIds = [];

Future<void> _cancelPlannerSlotIds() async {
  for (final id in List<int>.from(_plannerSlotIds)) {
    await _plugin.cancel(id: id);
  }
  _plannerSlotIds.clear();
}

Future<void> _cancelAllSnoozeIds() async {
  for (final id in List<int>.from(_snoozeIds)) {
    await _plugin.cancel(id: id);
  }
  _snoozeIds.clear();
}

/// Vom [PlannerHome] gesetzt: Mitteilung angetippt / verworfen → Tagesplan neu berechnen.
void Function()? onPlannerReminderRescheduleRequested;

void attachPlannerReminderRescheduleCallback(void Function()? fn) {
  onPlannerReminderRescheduleRequested = fn;
}

final Set<String> _foregroundCueKeys = HashSet<String>();

Future<void> _ensureTz() async {
  if (_tzReady) return;
  try {
    tz_data.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    _tzReady = true;
  } catch (_) {}
}

Future<void> _ensurePlannerAndroidChannels(
  AndroidFlutterLocalNotificationsPlugin? android,
) async {
  if (android == null || _androidChannelsReady) return;
  try {
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelGentle,
        'Sanfte Erinnerungen',
        description: 'Zeit vor Blockstart oder Ende (Benachrichtigung + Ton)',
        importance: Importance.defaultImportance,
        enableVibration: true,
        playSound: true,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelAlarmRad,
        'Wecker — radikal',
        description: 'Auffällige Wecker-Mitteilungen (Kategorie „radikal“)',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelAlarmCalm,
        'Wecker — ruhig',
        description: 'Weicher wirkende Wecker-Mitteilungen (Kategorie „ruhig“)',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      ),
    );
    _androidChannelsReady = true;
  } catch (_) {}
}

Future<void> plannerNotificationsInit() async {
  if (kIsWeb) {
    _inited = true;
    return;
  }
  if (_inited) return;

  try {
    await _ensureTz();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Keine automatische Berechtigung bei initialize — sonst doppeltes iOS/OS-Alert
    // zusätzlich zu [requestPermissions] unten (2× Dialog beim App-Start).
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await _ensurePlannerAndroidChannels(android);
    await android?.requestNotificationsPermission();

    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final macosPlugin = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        await iosPlugin?.requestPermissions(alert: true, sound: true, badge: false);
        break;
      case TargetPlatform.macOS:
        await macosPlugin?.requestPermissions(alert: true, sound: true, badge: false);
        break;
      default:
        break;
    }
  } catch (_) {
  } finally {
    _inited = true;
  }
}

void _onNotificationResponse(NotificationResponse r) {
  final action = r.actionId;
  if (action != null && action.startsWith('planner_snooze_')) {
    final rawM = action.replaceFirst('planner_snooze_', '');
    final mins = int.tryParse(rawM) ?? 5;
    unawaited(_fireSnoozeAlarm(r.payload, mins));
    return;
  }
  // Standard-Tap oder „Ausstellen“: Planner neu berechnen
  onPlannerReminderRescheduleRequested?.call();
}

int _momentNotifId(int year, int month, int day, int minuteOfDay, int tier, int kindSalt) {
  final h = Object.hash(year, month, day, minuteOfDay, tier, kindSalt);
  return _kPlannerNotifIdBase + (h.abs() % 899_983);
}

int _stableLegacyId(String blockId, DateTime day) =>
    _kPlannerNotifIdBase + (Object.hash(blockId, day.year, day.month, day.day) & 0xFFFF);

tz.TZDateTime _tzAtDayMinute(DateTime day, int minuteOfDay) {
  final h = minuteOfDay ~/ 60;
  final m = minuteOfDay % 60;
  return tz.TZDateTime(tz.local, day.year, day.month, day.day, h, m);
}

class _Moment {
  _Moment({
    required this.when,
    required this.slices,
    required this.isSessionEnd,
    this.leadMinutes,
  });

  final tz.TZDateTime when;
  final List<PlannerReminderSlice> slices;
  final bool isSessionEnd;
  final int? leadMinutes;
}

enum _MomentTier {
  gentleOs,
  alarmOs,
}

List<_Moment> _buildMoments(List<PlannerReminderSlice> slices, PlannerReminderPrefs prefs, DateTime day) {
  if (prefs.mode == PlannerReminderMode.off) return const [];

  final raw = prefs.normalizedBeforeOffsetsForCap();
  final offs = prefs.gentleRemindBeforeStart ? raw : const <int>[];

  /// Map Schlüssel: minute|tag mit tag b5 = vorher 5, e = Ende
  final acc = <String, List<PlannerReminderSlice>>{};

  void addMoment(int minute, String tag, PlannerReminderSlice s) {
    final k = '$minute|$tag';
    acc.putIfAbsent(k, () => []).add(s);
  }

  for (final s in slices) {
    if (!s.wantsReminders) continue;
    if (prefs.mode == PlannerReminderMode.alarm && !prefs.alarmTargetsBlock(s.id)) continue;

    for (final o in offs) {
      final gate = s.startMin - o;
      if (gate >= 0) {
        addMoment(gate, 'b$o', s);
      }
    }
    if (prefs.remindSessionEnd && s.startMin != s.endMin) {
      addMoment(s.endMin, 'end', s);
    }
  }

  final out = <_Moment>[];

  void finishEntry(String k, List<PlannerReminderSlice> parts) {
    final minute = int.parse(k.split('|').first);
    final tagPart = k.split('|')[1];

    tz.TZDateTime when;

    List<PlannerReminderSlice> uniq(List<PlannerReminderSlice> xs) {
      final seen = <String>{};
      final r = <PlannerReminderSlice>[];
      for (final e in xs) {
        if (seen.add(e.id)) r.add(e);
      }
      return r;
    }

    final u = uniq(parts);
    if (tagPart == 'end') {
      when = _tzAtDayMinute(day, minute);
      out.add(_Moment(when: when, slices: u, isSessionEnd: true));
    } else if (tagPart.startsWith('b')) {
      final lead = int.tryParse(tagPart.substring(1));
      when = _tzAtDayMinute(day, minute);
      out.add(_Moment(when: when, slices: u, isSessionEnd: false, leadMinutes: lead));
    }
  }

  for (final e in acc.entries) {
    finishEntry(e.key, e.value);
  }

  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}

_AndroidPair _androidDetails({
  required _MomentTier tier,
  required PlannerReminderPrefs prefs,
  required bool fullScreenAlarm,
}) {
  if (tier == _MomentTier.gentleOs) {
    return _AndroidPair(
      const AndroidNotificationDetails(
        _channelGentle,
        'Sanfte Erinnerungen',
        channelDescription:
            'Kurz vor Blockstart oder am Ende · passt zur Einstellung „Benachrichtigung“',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      const DarwinNotificationDetails(
        presentBanner: true,
        presentSound: true,
        presentAlert: true,
      ),
    );
  }

  final radical = prefs.alarmCategory == PlannerAlarmToneCategory.radical;
  final ch = radical ? _channelAlarmRad : _channelAlarmCalm;
  final importance = radical ? Importance.max : Importance.high;
  final actions = <AndroidNotificationAction>[
    const AndroidNotificationAction(
      'planner_dismiss',
      'Ausstellen',
      cancelNotification: true,
    ),
    for (final m in prefs.snoozeChoicesMinutes.take(3))
      AndroidNotificationAction(
        'planner_snooze_$m',
        '+$m Min',
        cancelNotification: true,
      ),
  ];

  return _AndroidPair(
    AndroidNotificationDetails(
      ch,
      radical ? 'Wecker · radikal' : 'Wecker · ruhig',
      channelDescription:
          '${radical ? 'Auffällig' : 'Sanfter'} Kanal (${toneLabelPlanner(prefs)})',
      importance: importance,
      priority: radical ? Priority.max : Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      fullScreenIntent: fullScreenAlarm && radical,
      timeoutAfter: prefs.alarmCategory == PlannerAlarmToneCategory.radical ? 120000 : 180000,
      actions: actions,
    ),
    DarwinNotificationDetails(
      presentBanner: true,
      presentSound: true,
      presentAlert: true,
      presentList: true,
      interruptionLevel: radical ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
    ),
  );
}

class _AndroidPair {
  const _AndroidPair(this.android, this.darwin);
  final AndroidNotificationDetails android;
  final DarwinNotificationDetails darwin;
}

/// Für die Einstellungs-UI: kurzer Tonname.
String toneLabelPlanner(PlannerReminderPrefs p) {
  const radical = ['Signalhorn', 'Dringend', 'Puls', 'Klarheit'];
  const calm = ['Sanft', 'Glocke', 'Welle', 'Leise'];
  final list = p.alarmCategory == PlannerAlarmToneCategory.radical ? radical : calm;
  final ix = p.alarmToneIndex.clamp(0, list.length - 1);
  return list[ix];
}

(String, String) _momentTitleBody(_Moment moment, PlannerReminderPrefs prefs) {
  final names = moment.slices.map((s) => s.title.trim().isEmpty ? 'Block' : s.title.trim()).join(', ');
  final first = moment.slices.isEmpty
      ? 'Block'
      : (moment.slices.first.title.trim().isEmpty ? 'Block' : moment.slices.first.title.trim());
  final shortNames = names.length > 120 ? '${names.substring(0, 120)}…' : names;

  if (moment.isSessionEnd) {
    return (
      moment.slices.length == 1 ? 'Ende: $first' : 'Ende von ${moment.slices.length} Blöcken',
      moment.slices.length == 1 ? '„$first“ ist zu Ende.' : shortNames,
    );
  }

  final lead = moment.leadMinutes ?? 5;
  return (
    moment.slices.length == 1 ? 'Gleich: $first' : 'Gleich: ${moment.slices.length} Blöcke',
    moment.slices.length == 1
        ? (lead > 0 ? 'Noch etwa $lead Min bis zum Start.' : 'Start bald.')
        : 'Noch etwa $lead Min — $shortNames',
  );
}

/// OS-Mitteilungen für heute nach [prefs] neu planen. Web: noop.
Future<void> rescheduleTodayReminders(
  List<PlannerReminderSlice> slices,
  DateTime now,
  PlannerReminderPrefs prefs,
) async {
  if (kIsWeb) return;
  if (_rescheduleRemindersBusy) return;
  _rescheduleRemindersBusy = true;
  try {
    if (!_inited) await plannerNotificationsInit();
    if (!_tzReady) return;

    await _cancelPlannerSlotIds();

    if (prefs.mode != PlannerReminderMode.alarm) {
      await _cancelAllSnoozeIds();
    }

    if (prefs.mode == PlannerReminderMode.off) {
      return;
    }

    final day = DateTime(now.year, now.month, now.day);
    final tzNow = tz.TZDateTime.now(tz.local);

    for (final s in slices) {
      await _plugin.cancel(id: _stableLegacyId(s.id, day));
    }

    final moments = _buildMoments(slices, prefs, day);

    Future<void> scheduleTier(_MomentTier tier, Future<bool> Function(_Moment m) predicate) async {
      for (final m in moments) {
        if (!m.when.isAfter(tzNow)) continue;
        final ok = await predicate(m);
        if (!ok) continue;

        final kindSalt = m.isSessionEnd ? 901 : (m.leadMinutes ?? 0);
        final id = _momentNotifId(day.year, day.month, day.day, m.when.hour * 60 + m.when.minute, tier.index, kindSalt);

        final (title, body) = _momentTitleBody(m, prefs);

        final useFs = prefs.mode == PlannerReminderMode.alarm && prefs.alarmCategory == PlannerAlarmToneCategory.radical;
        final pair = _androidDetails(tier: tier, prefs: prefs, fullScreenAlarm: useFs);

        final details = NotificationDetails(android: pair.android, iOS: pair.darwin, macOS: pair.darwin);

        final toneHint = prefs.mode == PlannerReminderMode.alarm ? toneLabelPlanner(prefs) : '';

        final payloadObj = <String, dynamic>{
          'v': 1,
          'al': prefs.mode == PlannerReminderMode.alarm,
          't': title,
          'b': body,
          'cat': prefs.alarmCategory.index,
          'tone': prefs.alarmToneIndex,
          'hint': toneHint,
        };

        _plannerSlotIds.add(id);
        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: m.when,
          notificationDetails: details,
          payload: jsonEncode(payloadObj),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          title: title,
          body: body.isNotEmpty ? body : (toneHint.isEmpty ? null : toneHint),
        );
      }
    }

    switch (prefs.mode) {
      case PlannerReminderMode.off:
        break;
      case PlannerReminderMode.notification:
        if (prefs.gentleSurface == PlannerOsReminderSurface.lockScreenAndBanner) {
          await scheduleTier(_MomentTier.gentleOs, (_) async => true);
        }
        break;
      case PlannerReminderMode.alarm:
        await scheduleTier(_MomentTier.alarmOs, (_) async => true);
        break;
    }
  } catch (_) {}
  finally {
    _rescheduleRemindersBusy = false;
  }
}

Future<bool> _fireSnoozeAlarm(String? payloadRaw, int minutes) async {
  if (kIsWeb || !_tzReady || minutes <= 0) return false;

  var p = PlannerReminderPrefs.defaults();
  try {
    if (payloadRaw != null && payloadRaw.startsWith('{')) {
      final m = jsonDecode(payloadRaw) as Map<String, dynamic>?;
      if (m != null) {
        final ci = (m['cat'] as num?)?.toInt();
        if (ci != null &&
            ci >= 0 &&
            ci < PlannerAlarmToneCategory.values.length) {
          p = p.copyWith(alarmCategory: PlannerAlarmToneCategory.values[ci]);
        }
        p = p.copyWith(
          alarmToneIndex: ((m['tone'] as num?)?.toInt() ?? p.alarmToneIndex).clamp(0, 3),
        );
      }
    }
  } catch (_) {}

  try {
    final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));

    String title = 'Erinnerung';
    String body = 'Verschoben (+$minutes Min).';
    String payloadStr = '{}';
    if (payloadRaw != null && payloadRaw.startsWith('{')) {
      payloadStr = payloadRaw;
      final map = jsonDecode(payloadRaw) as Map<String, dynamic>;
      title = (map['t'] as String?)?.trim().isNotEmpty == true ? map['t'] as String : title;
      body = (map['b'] as String?) ?? body;
    }

    final useFs = p.alarmCategory == PlannerAlarmToneCategory.radical;
    final pair = _androidDetails(tier: _MomentTier.alarmOs, prefs: p, fullScreenAlarm: useFs);
    final details = NotificationDetails(android: pair.android, iOS: pair.darwin, macOS: pair.darwin);
    final id = _kPlannerSnoozeIdBase + (DateTime.now().millisecondsSinceEpoch % 899_983);
    _snoozeIds.add(id);
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: details,
      payload: payloadStr,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      title: title,
      body: body.isEmpty ? '+$minutes Min' : body,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Vordergrund/Web: Vibrations-/Kurz-Ton wenn ein Erinnerungs-Zeitfenster aktiv ist (Modus 2 und 3).
void tickWebOrForegroundReminders(
  List<PlannerReminderSlice> slices,
  DateTime now,
  PlannerReminderPrefs prefs,
) {
  if (prefs.mode == PlannerReminderMode.off) return;
  if (slices.isEmpty) return;

  final dayKey = '${now.year}-${now.month}-${now.day}';

  final moments = _buildMoments(slices, prefs, DateTime(now.year, now.month, now.day));

  final secOfDay = now.hour * 3600 + now.minute * 60 + now.second;

  void fireCue(String gateKey, {bool strongAlarm = false}) {
    if (_foregroundCueKeys.contains(gateKey)) return;
    _foregroundCueKeys.add(gateKey);
    unawaited(strongAlarm ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact());
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  for (final m in moments) {
    final targetMinTotal = m.when.hour * 60 + m.when.minute;
    final leadSecs = targetMinTotal * 60;
    if (secOfDay < leadSecs || secOfDay >= leadSecs + 75) continue;

    final tierKey = prefs.mode == PlannerReminderMode.alarm ? 'a' : 'n';
    final kindKey = m.isSessionEnd ? 'e' : 'b${m.leadMinutes ?? 0}';
    final gateKey = '$dayKey|$targetMinTotal|$kindKey|$tierKey';

    if (prefs.mode == PlannerReminderMode.notification) {
      // OS-Mitteilung (Banner) reicht für native Geräte; sonst zweiter Hinweis (Ticker: Ton+Haptik) wie eine 2. Nachricht.
      if (prefs.gentleSurface == PlannerOsReminderSurface.foregroundAppOnly ||
          kIsWeb) {
        fireCue(gateKey);
      }
      continue;
    }

    // Modus 3: zusätzlich stärkerer Impuls am Gerät (App offen)
    fireCue(gateKey, strongAlarm: true);
  }
}

void clearWebFiredForTests() {
  _foregroundCueKeys.clear();
}
