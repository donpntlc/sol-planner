// Termin als .ics (Kalenderdatei) mit Erinnerungen — damit iPhone/Android eine echte
// Mitteilung schicken, auch wenn die Web-App geschlossen ist.
export 'calendar_export_stub.dart'
    if (dart.library.js_interop) 'calendar_export_web.dart';

/// Baut eine .ics-Datei für einen Termin.
/// [remindDayBefore]: Erinnerung 24 h vorher. [remindMinutesBefore]: zusätzliche
/// Erinnerung kurz vorher (null = keine).
String buildIcs({
  required String uid,
  required String title,
  required DateTime start,
  required DateTime end,
  bool allDay = false,
  String notes = '',
  bool remindDayBefore = true,
  int? remindMinutesBefore = 15,
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  String utc(DateTime d) {
    final u = d.toUtc();
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  String date(DateTime d) => '${d.year}${two(d.month)}${two(d.day)}';
  String esc(String t) => t
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n');

  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//SOL Planner//DE',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:$uid@sol-planner',
    'DTSTAMP:${utc(DateTime.now())}',
    if (allDay) ...[
      'DTSTART;VALUE=DATE:${date(start)}',
      'DTEND;VALUE=DATE:${date(start.add(const Duration(days: 1)))}',
    ] else ...[
      'DTSTART:${utc(start)}',
      'DTEND:${utc(end)}',
    ],
    'SUMMARY:${esc(title)}',
    if (notes.trim().isNotEmpty) 'DESCRIPTION:${esc(notes.trim())}',
    if (remindDayBefore) ...[
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:${esc('Morgen: $title')}',
      'TRIGGER:-P1D',
      'END:VALARM',
    ],
    if (remindMinutesBefore != null && remindMinutesBefore > 0) ...[
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:${esc(title)}',
      'TRIGGER:-PT${remindMinutesBefore}M',
      'END:VALARM',
    ],
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${lines.join('\r\n')}\r\n';
}
