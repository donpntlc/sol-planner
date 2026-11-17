// Timer & gemessene Zeiten (Done-Liste) für den SOL Planer.
//
// Ein laufender Timer gehört zu einem Block (Titel + Block-Art). Jede gemessene
// Strecke wird als [TimeLog] gespeichert – pro erledigter Aufgabe ein Eintrag,
// beim Stoppen der Rest. Daraus entstehen „Heute“ und „Woche“.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sol/main.dart' show PlanningPaletteX;

const String kTimeLogsPrefKey = 'planner_time_logs_v1';
const String kRunningTimerPrefKey = 'planner_timer_running_v1';

String timerDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String fmtClock(int secs) {
  final s = secs < 0 ? -secs : secs;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final ss = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final sss = ss.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$sss' : '$mm:$sss';
}

String fmtDur(int secs) {
  final m = (secs / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h h' : '$h h ${r.toString().padLeft(2, '0')}';
}

class TimeLog {
  TimeLog({
    required this.id,
    required this.day,
    required this.title,
    required this.kind,
    this.task,
    required this.startMs,
    required this.secs,
    this.manual = false,
  });

  final String id;
  final String day;
  final String title;
  final String kind;
  final String? task;
  final int startMs;
  final int secs;
  final bool manual;

  Map<String, dynamic> toJson() => {
    'id': id,
    'd': day,
    't': title,
    'k': kind,
    if (task != null) 'task': task,
    's': startMs,
    'sec': secs,
    if (manual) 'm': true,
  };

  static TimeLog? fromJson(Map<String, dynamic> j) {
    try {
      return TimeLog(
        id: j['id'] as String,
        day: j['d'] as String,
        title: (j['t'] as String?) ?? '',
        kind: (j['k'] as String?) ?? '',
        task: j['task'] as String?,
        startMs: (j['s'] as num).toInt(),
        secs: (j['sec'] as num).toInt(),
        manual: j['m'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

class RunningTimer {
  RunningTimer({
    required this.title,
    required this.kind,
    required this.startMs,
    this.runStartMs,
    this.bankedSecs = 0,
    this.segStartSecs = 0,
    this.targetSecs,
  });

  final String title;
  final String kind;
  final int startMs;

  /// null = pausiert.
  int? runStartMs;

  /// Gelaufene Sekunden vor dem aktuellen Lauf (Pausen zählen nicht).
  int bankedSecs;

  /// Stand, ab dem der aktuelle Abschnitt (Aufgabe) zählt.
  int segStartSecs;
  int? targetSecs;

  bool get paused => runStartMs == null;

  int elapsedSecs([DateTime? now]) {
    final n = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final run = runStartMs == null ? 0 : ((n - runStartMs!) ~/ 1000);
    return bankedSecs + (run < 0 ? 0 : run);
  }

  Map<String, dynamic> toJson() => {
    't': title,
    'k': kind,
    's': startMs,
    if (runStartMs != null) 'r': runStartMs,
    'b': bankedSecs,
    'seg': segStartSecs,
    if (targetSecs != null) 'target': targetSecs,
  };

  static RunningTimer? fromJson(Map<String, dynamic> j) {
    try {
      return RunningTimer(
        title: j['t'] as String,
        kind: (j['k'] as String?) ?? '',
        startMs: (j['s'] as num).toInt(),
        runStartMs: (j['r'] as num?)?.toInt(),
        bankedSecs: (j['b'] as num?)?.toInt() ?? 0,
        segStartSecs: (j['seg'] as num?)?.toInt() ?? 0,
        targetSecs: (j['target'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

class TimerStore extends ChangeNotifier {
  final List<TimeLog> logs = [];
  RunningTimer? running;
  var _idSeq = 0;

  String _newId() =>
      'tl_${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kTimeLogsPrefKey);
      logs.clear();
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              final l = TimeLog.fromJson(Map<String, dynamic>.from(e));
              if (l != null) logs.add(l);
            }
          }
        }
      }
      final r = prefs.getString(kRunningTimerPrefKey);
      running = null;
      if (r != null && r.isNotEmpty) {
        final m = jsonDecode(r);
        if (m is Map) running = RunningTimer.fromJson(Map<String, dynamic>.from(m));
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Ältere als ~1 Jahr verwerfen, damit der Speicher klein bleibt.
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 370))
          .millisecondsSinceEpoch;
      logs.removeWhere((l) => l.startMs < cutoff);
      await prefs.setString(
        kTimeLogsPrefKey,
        jsonEncode([for (final l in logs) l.toJson()]),
      );
      if (running == null) {
        await prefs.remove(kRunningTimerPrefKey);
      } else {
        await prefs.setString(kRunningTimerPrefKey, jsonEncode(running!.toJson()));
      }
    } catch (_) {}
  }

  void start({required String title, required String kind, int? targetSecs}) {
    if (running != null) _logSegment(null);
    final now = DateTime.now().millisecondsSinceEpoch;
    running = RunningTimer(
      title: title,
      kind: kind,
      startMs: now,
      runStartMs: now,
      targetSecs: targetSecs,
    );
    notifyListeners();
    unawaited(_save());
  }

  void pause() {
    final r = running;
    if (r == null || r.paused) return;
    r.bankedSecs = r.elapsedSecs();
    r.runStartMs = null;
    notifyListeners();
    unawaited(_save());
  }

  void resume() {
    final r = running;
    if (r == null || !r.paused) return;
    r.runStartMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    unawaited(_save());
  }

  void setTarget(int? secs) {
    running?.targetSecs = secs;
    notifyListeners();
    unawaited(_save());
  }

  void _logSegment(String? task) {
    final r = running;
    if (r == null) return;
    final el = r.elapsedSecs();
    final seg = el - r.segStartSecs;
    if (seg >= 30) {
      final startMs = DateTime.now().millisecondsSinceEpoch - seg * 1000;
      logs.add(
        TimeLog(
          id: _newId(),
          day: timerDayKey(DateTime.fromMillisecondsSinceEpoch(r.startMs)),
          title: r.title,
          kind: r.kind,
          task: task,
          startMs: startMs,
          secs: seg,
        ),
      );
    }
    r.segStartSecs = el;
  }

  /// Aufgabe erledigt: Zeit seit der letzten Aufgabe als eigener Eintrag.
  void completeTask(String task) {
    if (running == null) return;
    _logSegment(task);
    notifyListeners();
    unawaited(_save());
  }

  /// Stoppen & speichern. Gibt die gesamte gemessene Zeit zurück.
  int stop({String? task}) {
    final r = running;
    if (r == null) return 0;
    final total = r.elapsedSecs();
    _logSegment(task);
    running = null;
    notifyListeners();
    unawaited(_save());
    return total;
  }

  void discard() {
    running = null;
    notifyListeners();
    unawaited(_save());
  }

  void addManual({
    required DateTime day,
    required String title,
    required String kind,
    required int minutes,
    String? task,
  }) {
    final start = DateTime(day.year, day.month, day.day, 12);
    logs.add(
      TimeLog(
        id: _newId(),
        day: timerDayKey(day),
        title: title,
        kind: kind,
        task: task,
        startMs: start.millisecondsSinceEpoch,
        secs: minutes * 60,
        manual: true,
      ),
    );
    notifyListeners();
    unawaited(_save());
  }

  void remove(String id) {
    logs.removeWhere((l) => l.id == id);
    notifyListeners();
    unawaited(_save());
  }

  List<TimeLog> forDay(DateTime d) {
    final k = timerDayKey(d);
    return logs.where((l) => l.day == k).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
  }

  int secsForDay(DateTime d) =>
      forDay(d).fold(0, (s, l) => s + l.secs);
}

/// Schwebende Leiste, solange ein Timer läuft.
class RunningTimerPill extends StatefulWidget {
  const RunningTimerPill({super.key, required this.store, required this.onTap});

  final TimerStore store;
  final VoidCallback onTap;

  @override
  State<RunningTimerPill> createState() => _RunningTimerPillState();
}

class _RunningTimerPillState extends State<RunningTimerPill> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.store.running != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.store.running;
    if (r == null) return const SizedBox.shrink();
    final p = context.palette;
    final el = r.elapsedSecs();
    final over = r.targetSecs != null && el >= r.targetSecs!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: p.accent.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                r.paused ? Icons.pause_circle_filled_rounded : Icons.timer_rounded,
                color: r.paused ? p.muted : p.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                fmtClock(el),
                style: TextStyle(
                  color: over ? p.accent : p.text,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                icon: Icon(
                  r.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: p.text,
                  size: 22,
                ),
                onPressed: () =>
                    r.paused ? widget.store.resume() : widget.store.pause(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vollbild: nur der Block, die eine aktuelle Aufgabe und die Zeit.
class FocusTimerScreen extends StatefulWidget {
  const FocusTimerScreen({
    super.key,
    required this.store,
    required this.openTasks,
    required this.onTaskDone,
    this.onStopped,
  });

  final TimerStore store;

  /// Offene Aufgaben der Block-Art (erste = aktuelle).
  final List<String> Function() openTasks;
  final Future<void> Function(String task) onTaskDone;
  final void Function(int totalSecs)? onStopped;

  @override
  State<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends State<FocusTimerScreen> {
  Timer? _tick;
  bool _alerted = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final r = widget.store.running;
      if (r != null &&
          r.targetSecs != null &&
          !_alerted &&
          r.elapsedSecs() >= r.targetSecs!) {
        _alerted = true;
        HapticFeedback.heavyImpact();
      }
      setState(() {});
    });
  }

  void _onStore() {
    if (!mounted) return;
    if (widget.store.running == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = widget.store.running;
    if (r == null) return Scaffold(backgroundColor: p.bg);
    final el = r.elapsedSecs();
    final target = r.targetSecs;
    final left = target == null ? null : target - el;
    final frac = target == null || target <= 0
        ? null
        : (el / target).clamp(0.0, 1.0).toDouble();
    final tasks = widget.openTasks();
    final current = tasks.isEmpty ? null : tasks.first;
    final segSecs = el - r.segStartSecs;

    Widget targetChip(String label, int? secs) {
      final sel = target == secs;
      return ChoiceChip(
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        onSelected: (_) {
          _alerted = secs != null && el >= secs;
          widget.store.setTarget(secs);
        },
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Minimieren',
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.muted, size: 30),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Timer verwerfen?'),
                          content: const Text(
                            'Die Zeit seit dem letzten Speichern wird nicht gezählt.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Abbrechen'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Verwerfen'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) widget.store.discard();
                    },
                    child: Text('Verwerfen', style: TextStyle(color: p.muted)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                r.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 250,
                  height: 250,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: frac ?? 0,
                          strokeWidth: 6,
                          backgroundColor: p.hairline,
                          color: p.accent,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            fmtClock(el),
                            style: TextStyle(
                              color: r.paused ? p.muted : p.text,
                              fontSize: 54,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (left != null)
                            Text(
                              left > 0 ? 'noch ${fmtClock(left)}' : 'Zeit um · +${fmtClock(-left)}',
                              style: TextStyle(
                                color: left > 0 ? p.muted : p.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (r.paused)
                            Text('Pausiert', style: TextStyle(color: p.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  targetChip('Offen', null),
                  targetChip('15', 15 * 60),
                  targetChip('25', 25 * 60),
                  targetChip('45', 45 * 60),
                  targetChip('60', 60 * 60),
                  targetChip('90', 90 * 60),
                ],
              ),
              const Spacer(),
              if (current != null) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'JETZT · ${fmtClock(segSecs)}',
                              style: TextStyle(
                                color: p.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              current,
                              style: TextStyle(
                                color: p.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (tasks.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'danach noch ${tasks.length - 1}',
                                  style: TextStyle(color: p.muted, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          widget.store.completeTask(current);
                          await widget.onTaskDone(current);
                          HapticFeedback.lightImpact();
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Erledigt'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        side: BorderSide(color: p.hairline),
                      ),
                      onPressed: () =>
                          r.paused ? widget.store.resume() : widget.store.pause(),
                      icon: Icon(
                        r.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: p.text,
                      ),
                      label: Text(
                        r.paused ? 'Weiter' : 'Pause',
                        style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: p.accent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        final total = widget.store.stop();
                        widget.onStopped?.call(total);
                      },
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text(
                        'Stopp & speichern',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Done-Liste: was heute / diese Woche gemessen wurde.
class TimeLogSheet extends StatefulWidget {
  const TimeLogSheet({
    super.key,
    required this.store,
    required this.colorForKind,
    required this.kindOf,
    required this.blockTitlesToday,
  });

  final TimerStore store;
  final Color Function(String kind) colorForKind;
  final String Function(String title) kindOf;
  final List<String> blockTitlesToday;

  @override
  State<TimeLogSheet> createState() => _TimeLogSheetState();
}

class _TimeLogSheetState extends State<TimeLogSheet> {
  var _week = false;
  DateTime _day = DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_on);
  }

  void _on() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(_on);
    super.dispose();
  }

  static const _wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  Future<void> _addManual() async {
    final titleCtrl = TextEditingController(
      text: widget.blockTitlesToday.isEmpty ? '' : widget.blockTitlesToday.first,
    );
    final minCtrl = TextEditingController(text: '30');
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Zeit nachtragen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: titleCtrl.text),
              optionsBuilder: (v) => widget.blockTitlesToday.where(
                (t) => t.toLowerCase().contains(v.text.toLowerCase()),
              ),
              onSelected: (s) => titleCtrl.text = s,
              fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                ctrl.addListener(() => titleCtrl.text = ctrl.text);
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'Wofür (Block)'),
                );
              },
            ),
            TextField(
              controller: minCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minuten'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    final t = titleCtrl.text.trim();
    final m = int.tryParse(minCtrl.text.trim()) ?? 0;
    if (res == true && t.isNotEmpty && m > 0) {
      widget.store.addManual(
        day: _day,
        title: t,
        kind: widget.kindOf(t),
        minutes: m,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final today = DateTime(_day.year, _day.month, _day.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = _week
        ? [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))]
        : [today];
    final logs = [for (final d in days) ...widget.store.forDay(d)];
    final total = logs.fold<int>(0, (s, l) => s + l.secs);

    // Summen pro Block-Art.
    final byKind = <String, ({String label, int secs})>{};
    for (final l in logs) {
      final k = l.kind.isEmpty ? l.title.toLowerCase() : l.kind;
      final cur = byKind[k];
      byKind[k] = (
        label: cur?.label ?? l.title,
        secs: (cur?.secs ?? 0) + l.secs,
      );
    }
    final kinds = byKind.entries.toList()
      ..sort((a, b) => b.value.secs.compareTo(a.value.secs));
    final maxK = kinds.isEmpty ? 1 : kinds.first.value.secs;

    final now = DateTime.now();
    final isToday = today == DateTime(now.year, now.month, now.day);
    final dayLabel = isToday
        ? 'Heute'
        : '${_wd[today.weekday - 1]}, ${today.day}.${today.month}.';
    final weekLabel =
        'Woche ${monday.day}.${monday.month}. – ${monday.add(const Duration(days: 6)).day}.${monday.add(const Duration(days: 6)).month}.';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Material(
        color: p.surface,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Gemessene Zeiten',
                        style: TextStyle(
                          color: p.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zeit nachtragen',
                      onPressed: _addManual,
                      icon: Icon(Icons.add_circle_outline_rounded, color: p.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('Tag')),
                        ButtonSegment(value: true, label: Text('Woche')),
                      ],
                      selected: {_week},
                      onSelectionChanged: (s) => setState(() => _week = s.first),
                    ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.chevron_left_rounded, color: p.text),
                      onPressed: () => setState(
                        () => _day = _day.subtract(Duration(days: _week ? 7 : 1)),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.chevron_right_rounded, color: p.text),
                      onPressed: () => setState(
                        () => _day = _day.add(Duration(days: _week ? 7 : 1)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _week ? weekLabel : dayLabel,
                  style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  total == 0 ? 'Noch nichts gemessen' : fmtDur(total),
                  style: TextStyle(
                    color: p.text,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (_week && total > 0) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 74,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Builder(
                              builder: (_) {
                                final s = widget.store.secsForDay(days[i]);
                                final mx = days
                                    .map(widget.store.secsForDay)
                                    .fold<int>(1, (a, b) => b > a ? b : a);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        height: 4 + 46 * s / mx,
                                        decoration: BoxDecoration(
                                          color: s == 0
                                              ? p.hairline
                                              : p.accent.withValues(alpha: 0.85),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _wd[i],
                                        style: TextStyle(color: p.muted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (kinds.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final e in kinds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.value.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                fmtDur(e.value.secs),
                                style: TextStyle(
                                  color: p.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: e.value.secs / maxK,
                              minHeight: 6,
                              backgroundColor: p.hairline,
                              color: widget.colorForKind(e.key),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (!_week && logs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'DONE-LISTE',
                    style: TextStyle(
                      color: p.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final l in logs)
                    Dismissible(
                      key: ValueKey(l.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: Colors.red.withValues(alpha: 0.25),
                        child: const Icon(Icons.delete_outline_rounded),
                      ),
                      onDismissed: (_) => widget.store.remove(l.id),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          Icons.check_circle_rounded,
                          color: widget.colorForKind(l.kind),
                        ),
                        title: Text(
                          l.task ?? l.title,
                          style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          l.manual
                              ? 'nachgetragen'
                              : '${_hm(l.startMs)}${l.task != null ? ' · ${l.title}' : ''}',
                          style: TextStyle(color: p.muted),
                        ),
                        trailing: Text(
                          fmtDur(l.secs),
                          style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Nach links wischen zum Löschen.',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _hm(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
