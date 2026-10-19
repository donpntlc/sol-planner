/// Ein Abschnitt innerhalb eines festen Zeitblocks (z. B. Deep Work): Fokus oder Pause.
class BlockSessionSegment {
  BlockSessionSegment({
    required this.id,
    required this.durationMinutes,
    required this.isPause,
  });

  final String id;
  final int durationMinutes;
  final bool isPause;

  BlockSessionSegment copyWith({
    String? id,
    int? durationMinutes,
    bool? isPause,
  }) {
    return BlockSessionSegment(
      id: id ?? this.id,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isPause: isPause ?? this.isPause,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'minutes': durationMinutes,
        'pause': isPause,
      };

  factory BlockSessionSegment.fromJson(Map<String, dynamic> j) {
    return BlockSessionSegment(
      id: (j['id'] as String?)?.trim().isNotEmpty == true
          ? j['id'] as String
          : 'seg_${j.hashCode}',
      durationMinutes:
          ((j['minutes'] ?? j['durationMinutes']) as num?)?.toInt().clamp(1, 24 * 60) ??
              15,
      isPause: j['pause'] as bool? ?? false,
    );
  }
}

int sessionSegmentsTotalMinutes(List<BlockSessionSegment> list) =>
    list.fold<int>(0, (a, s) => a + s.durationMinutes);

/// Leere Liste = kein Session-Plan; sonst muss die Summe exakt der Blockdauer entsprechen.
bool sessionSegmentsValidForSpan(List<BlockSessionSegment> list, int spanMinutes) {
  if (list.isEmpty) return true;
  return sessionSegmentsTotalMinutes(list) == spanMinutes;
}
