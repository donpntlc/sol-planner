/// Minimales Abbild eines Plan-Slots nur für aktuelle Aufgabe / Homescreen.
class ProbeBlock {
  ProbeBlock({
    required String rawTitle,
    required this.startMin,
    required this.endMin,
    required this.colorLabel,
    required this.completed,
    required this.accentArgb,
    this.allDay = false,
    this.overnightStartAfterEnd = false,
  }) : title = rawTitle.trim();

  /// Anzeitetitel — leer wenn unbekannt.
  final String title;
  final int startMin;
  final int endMin;
  final String colorLabel;
  final bool completed;
  /// Kategorie/Streifen für UI — ARGB wie in der Haupt-App (_stripeForBlock).
  final int accentArgb;
  final bool allDay;

  /// Wenn Start > Ende: über Mitternacht (nicht ganztags).
  final bool overnightStartAfterEnd;

  bool get isLinearSlot =>
      !allDay &&
      startMin < endMin &&
      !overnightStartAfterEnd;

  bool get isOvernightLinear =>
      !allDay &&
      overnightStartAfterEnd &&
      startMin != endMin;
}

/// Zustand für App-Widgets und natives Home/Lock Screen.
class CurrentTaskViewModel {
  const CurrentTaskViewModel.idle()
    : title = '',
      subtitle = '',
      rangeLabel = '',
      accentArgb = 0xFF64748B,
      remainingMinutes = null,
      completed = false,
      isIdle = true;

  const CurrentTaskViewModel.active({
    required this.title,
    required this.subtitle,
    required this.rangeLabel,
    required this.accentArgb,
    required this.remainingMinutes,
    this.completed = false,
  }) : isIdle = false;

  final String title;

  /// z. B. „still 23 min“ oder Kategoriezeile.
  final String subtitle;
  final String rangeLabel;

  /// ARGB Streifenfarbe
  final int accentArgb;
  final int? remainingMinutes;
  final bool completed;
  final bool isIdle;

  bool get isEmpty => title.isEmpty;

  CurrentTaskViewModel normalized() => CurrentTaskViewModel.active(
    title: title.isEmpty ? '(ohne Titel)' : title,
    subtitle: subtitle,
    rangeLabel: rangeLabel,
    accentArgb: accentArgb,
    remainingMinutes: remainingMinutes,
    completed: completed,
  );
}
