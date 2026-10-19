import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sol/planner_notifications.dart' show PlannerReminderSlice, toneLabelPlanner;
import 'package:sol/planner_reminder_prefs.dart';

Future<PlannerReminderPrefs?> showPlannerReminderPrefsSheet(
  BuildContext context, {
  required PlannerReminderPrefs initial,
  List<PlannerReminderSlice> todayReminderSlices = const [],
}) {
  return showModalBottomSheet<PlannerReminderPrefs>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PlannerReminderPrefsSheet(
      initial: initial,
      todayReminderSlices: todayReminderSlices,
    ),
  );
}

class _PlannerReminderPrefsSheet extends StatefulWidget {
  const _PlannerReminderPrefsSheet({
    required this.initial,
    required this.todayReminderSlices,
  });

  final PlannerReminderPrefs initial;
  final List<PlannerReminderSlice> todayReminderSlices;

  @override
  State<_PlannerReminderPrefsSheet> createState() =>
      _PlannerReminderPrefsSheetState();
}

class _PlannerReminderPrefsSheetState extends State<_PlannerReminderPrefsSheet> {
  late TextEditingController ctrl1;
  late TextEditingController ctrl2;
  late TextEditingController ctrl3;
  late TextEditingController sz1;
  late TextEditingController sz2;
  late TextEditingController sz3;
  late PlannerReminderPrefs working;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    ctrl1 = TextEditingController(
      text: _offsetAt(initial.beforeOffsetsMinutes, 0),
    );
    ctrl2 = TextEditingController(
      text: _offsetAt(initial.beforeOffsetsMinutes, 1),
    );
    ctrl3 = TextEditingController(
      text: _offsetAt(initial.beforeOffsetsMinutes, 2),
    );
    sz1 = TextEditingController(
      text:
          '${initial.snoozeChoicesMinutes.isEmpty ? 5 : initial.snoozeChoicesMinutes[0]}',
    );
    sz2 = TextEditingController(
      text:
          initial.snoozeChoicesMinutes.length > 1 ? '${initial.snoozeChoicesMinutes[1]}' : '10',
    );
    sz3 = TextEditingController(
      text:
          initial.snoozeChoicesMinutes.length > 2 ? '${initial.snoozeChoicesMinutes[2]}' : '15',
    );
    working = initial;
  }

  @override
  void dispose() {
    ctrl1.dispose();
    ctrl2.dispose();
    ctrl3.dispose();
    sz1.dispose();
    sz2.dispose();
    sz3.dispose();
    super.dispose();
  }

  List<int> parseOffsetsList() {
    final out = <int>[];
    for (final c in [ctrl1, ctrl2, ctrl3]) {
      final v = int.tryParse(c.text.trim());
      if (v != null && v >= 1 && v <= 720) out.add(v);
    }
    out.sort();
    return out.map((x) => x).toSet().toList()..sort();
  }

  List<int> parseSnooze() {
    final out = <int>[];
    for (final c in [sz1, sz2, sz3]) {
      final v = int.tryParse(c.text.trim());
      if (v != null && v >= 1 && v <= 180) out.add(v);
    }
    if (out.length < 3) {
      for (final d in const [5, 10, 15]) {
        if (out.length >= 3) break;
        if (!out.contains(d)) out.add(d);
      }
    }
    out.sort();
    return out.take(3).toList();
  }

  PlannerReminderPrefs buildResult() {
    var offs = parseOffsetsList();
    final wantBefore = working.mode != PlannerReminderMode.off &&
        working.gentleRemindBeforeStart;
    if (wantBefore && offs.isEmpty) {
      offs = List<int>.from(PlannerReminderPrefs.defaults().beforeOffsetsMinutes);
    }
    return working.copyWith(
      beforeOffsetsMinutes: offs,
      snoozeChoicesMinutes: parseSnooze(),
    );
  }

  void setMode(PlannerReminderMode m) {
    setState(() => working = working.copyWith(mode: m));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;

    Widget sectionLabel(String s) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            s,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: Material(
            color: scheme.surface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.notifications_active_outlined, color: scheme.onSurface),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Erinnerungen & Wecker',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Drei Stufen: aus · sanfte Meldungen · Wecker zum Abstellen oder Verschieben.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.72),
                        ),
                  ),
                  const SizedBox(height: 16),
                  sectionLabel('Erinnerungsart'),
                  SegmentedButton<PlannerReminderMode>(
                    segments: const [
                      ButtonSegment(
                        value: PlannerReminderMode.off,
                        label: Text('Aus'),
                        icon: Icon(Icons.notifications_off_outlined),
                      ),
                      ButtonSegment(
                        value: PlannerReminderMode.notification,
                        label: Text('Mitteilung'),
                        icon: Icon(Icons.vibration),
                      ),
                      ButtonSegment(
                        value: PlannerReminderMode.alarm,
                        label: Text('Wecker'),
                        icon: Icon(Icons.alarm),
                      ),
                    ],
                    selected: {working.mode},
                    emptySelectionAllowed: false,
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      setMode(s.first);
                    },
                  ),
                  if (working.mode == PlannerReminderMode.notification) ...[
                    const SizedBox(height: 18),
                    sectionLabel('Mitteilungen am Gerät'),
                    Text(
                      'Ton und Vibration in der geöffneten App gibt es immer. '
                      'Zusätzlich kann das Betriebssystem Hinweise auf dem Sperrbildschirm planen oder nur kurz beim Gebrauch ohne Sperrbildschirm-Anzeige.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.75),
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 12),
                    ...(() {
                      Widget surfaceTile(
                        PlannerOsReminderSurface val,
                        String title,
                        String subtitle,
                      ) {
                        final sel = working.gentleSurface == val;
                        return InkWell(
                          onTap: () => setState(
                            () => working = working.copyWith(gentleSurface: val),
                          ),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: sel ? scheme.primary : scheme.outlineVariant,
                                width: sel ? 2 : 1,
                              ),
                              color: sel
                                  ? scheme.primary.withValues(alpha: 0.06)
                                  : Colors.transparent,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      sel
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      size: 20,
                                      color: sel ? scheme.primary : scheme.outline,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.78),
                                        height: 1.35,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return [
                        surfaceTile(
                          PlannerOsReminderSurface.lockScreenAndBanner,
                          'Sperrbildschirm & Banner',
                          'Klassische Hinweise — auch wenn die App geschlossen ist.',
                        ),
                        const SizedBox(height: 10),
                        surfaceTile(
                          PlannerOsReminderSurface.foregroundAppOnly,
                          'Nur bei geöffneter SOL-App',
                          'Keine geplanten OS-Hinweise; Vibration und Ton erfolgen weiter in der geöffneten App.',
                        ),
                      ];
                    })(),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auch vor dem Block erinnern'),
                      subtitle: const Text(
                        'Wenn aus, gilt nur noch „Erinnerung am Ende“ (sofern unten aktiv). Max. drei Zeitpunkte insgesamt.',
                      ),
                      value: working.gentleRemindBeforeStart,
                      onChanged: (v) => setState(() {
                        working = working.copyWith(gentleRemindBeforeStart: v);
                      }),
                    ),
                    if (working.gentleRemindBeforeStart) ...[
                      const SizedBox(height: 6),
                      sectionLabel(
                        working.remindSessionEnd
                            ? 'Minuten vor Start (bis zu zwei Werte)'
                            : 'Minuten vor Start (bis zu drei Werte)',
                      ),
                      Row(
                        children: [
                          for (final c in [ctrl1, ctrl2, ctrl3]) ...[
                            Expanded(
                              child: TextField(
                                controller: c,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Min',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auch beim Block-Ende melden'),
                      subtitle: working.remindSessionEnd
                          ? Text(
                              'Ein Zeitpunkt geht vom Kontingent (max. drei) ab — '
                              'eventuell weniger „vor Start“ möglich.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurface.withValues(alpha: 0.72),
                                  ),
                            )
                          : null,
                      value: working.remindSessionEnd,
                      onChanged: (v) =>
                          setState(() => working = working.copyWith(remindSessionEnd: v)),
                    ),
                  ],
                  if (working.mode == PlannerReminderMode.alarm) ...[
                    const SizedBox(height: 18),
                    sectionLabel('Ton-Kategorie'),
                    SegmentedButton<PlannerAlarmToneCategory>(
                      segments: const [
                        ButtonSegment(
                          value: PlannerAlarmToneCategory.radical,
                          label: Text('Radikal'),
                        ),
                        ButtonSegment(
                          value: PlannerAlarmToneCategory.calm,
                          label: Text('Ruhig'),
                        ),
                      ],
                      selected: {working.alarmCategory},
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        setState(
                          () => working = working.copyWith(alarmCategory: s.first),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Voreinstellung: ${toneLabelPlanner(working)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Slider(
                      value: working.alarmToneIndex.clamp(0, 3).toDouble(),
                      max: 3,
                      divisions: 3,
                      label: toneLabelPlanner(working),
                      onChanged: (x) => setState(() => working = working.copyWith(
                            alarmToneIndex: x.round().clamp(0, 3),
                          )),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auch vor Blockstart wecken'),
                      value: working.gentleRemindBeforeStart,
                      onChanged: (v) => setState(
                        () => working = working.copyWith(gentleRemindBeforeStart: v),
                      ),
                    ),
                    if (working.gentleRemindBeforeStart) ...[
                      const SizedBox(height: 4),
                      sectionLabel(
                        working.remindSessionEnd
                            ? 'Minuten vor Start (bis zu zwei)'
                            : 'Minuten vor Start (bis zu drei)',
                      ),
                      Row(
                        children: [
                          for (final c in [ctrl1, ctrl2, ctrl3]) ...[
                            Expanded(
                              child: TextField(
                                controller: c,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Min',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auch beim Block-Ende'),
                      value: working.remindSessionEnd,
                      onChanged: (v) =>
                          setState(() => working = working.copyWith(remindSessionEnd: v)),
                    ),
                    Builder(
                      builder: (ctx) {
                        final pickSlices =
                            widget.todayReminderSlices.where((s) => s.wantsReminders).toList();
                        if (pickSlices.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              'Heute keine weckbaren Blöcke (erledigt, stumm oder nicht linear).',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurface.withValues(alpha: 0.72),
                                  ),
                            ),
                          );
                        }
                        final eligibleIds = pickSlices.map((s) => s.id).toSet();
                        bool rowChecked(String id) =>
                            !working.alarmRestrictBlocks ||
                            working.alarmEnabledBlockIds.contains(id);
                        void toggleRow(String id, bool selected) {
                          setState(() {
                            var restrict = working.alarmRestrictBlocks;
                            var ids = Set<String>.from(working.alarmEnabledBlockIds);
                            if (!restrict) {
                              ids = Set<String>.from(eligibleIds);
                              restrict = true;
                            }
                            if (selected) {
                              ids.add(id);
                            } else {
                              ids.remove(id);
                            }
                            if (ids.length >= eligibleIds.length) {
                              working = working.copyWith(
                                alarmRestrictBlocks: false,
                                alarmEnabledBlockIds: {},
                              );
                            } else {
                              working = working.copyWith(
                                alarmRestrictBlocks: true,
                                alarmEnabledBlockIds: ids,
                              );
                            }
                          });
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 14),
                            sectionLabel('Wecker für Blöcke'),
                            Text(
                              'Antippen: nur markierte Blöcke lösen den Wecker aus.',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurface.withValues(alpha: 0.72),
                                  ),
                            ),
                            const SizedBox(height: 6),
                            ...pickSlices.map((s) {
                              final title =
                                  s.title.trim().isEmpty ? 'Block' : s.title.trim();
                              return CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(title),
                                subtitle: Text(_formatMinRange(s.startMin, s.endMin)),
                                value: rowChecked(s.id),
                                onChanged: (v) {
                                  if (v == null) return;
                                  toggleRow(s.id, v);
                                },
                              );
                            }),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    sectionLabel('Nach „+ Min“ beim Wecker (drei Buttons)'),
                    Row(
                      children: [
                        for (final c in [sz1, sz2, sz3]) ...[
                          Expanded(
                            child: TextField(
                              controller: c,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: '+ Min',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, buildResult()),
                    child: const Text('Speichern'),
                  ),
                  SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _offsetAt(List<int> offs, int i) =>
    i < offs.length && offs.isNotEmpty ? '${offs[i]}' : (i == 0 ? '5' : '');

String _formatMinRange(int start, int end) {
  String hm(int m) {
    final h = m ~/ 60;
    final mi = m % 60;
    return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
  }

  return '${hm(start)}–${hm(end)}';
}
