import 'dart:convert';

import 'models.dart';

String _humanShort(int mins) {
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  if (m <= 0) return '${h}h';
  return '${h}h $m min';
}

int? _remainingMinutesIfActiveLinear(ProbeBlock block, int nowMin) {
  if (block.completed) return null;
  if (block.allDay || !block.isLinearSlot) return null;
  if (nowMin >= block.startMin && nowMin < block.endMin) {
    return block.endMin - nowMin;
  }
  return null;
}

int? _remainingOvernightBeforeMidnight(
  ProbeBlock block,
  int nowMin,
) {
  if (block.completed) return null;
  if (!block.isOvernightLinear) return null;
  if (nowMin >= block.startMin) {
    return (1440 - nowMin) + block.endMin;
  }
  if (nowMin < block.endMin) {
    return block.endMin - nowMin;
  }
  return null;
}

/// Liste ist die **bereits chronologisch sortierte** Tagessicht (wie _getBlocksForDay).
/// [today] Datum des Tages, den `blocks` darstellt; [now] echte lokale Zeit.
CurrentTaskViewModel resolveCurrentPlannerTask({
  required List<ProbeBlock> blocks,
  required DateTime todayCalendarDay,
  required DateTime now,
}) {
  if (blocks.isEmpty) {
    return const CurrentTaskViewModel.idle();
  }
  final isToday =
      todayCalendarDay.year == now.year &&
      todayCalendarDay.month == now.month &&
      todayCalendarDay.day == now.day;
  if (!isToday) {
    return const CurrentTaskViewModel.idle();
  }

  final nowMin = now.hour * 60 + now.minute;

  for (final b in blocks) {
    if (b.completed) continue;
    if (b.isLinearSlot) {
      final remLin = _remainingMinutesIfActiveLinear(b, nowMin);
      if (remLin != null) {
        final sub =
            '${b.colorLabel} · noch ${_humanShort(remLin)}';
        return CurrentTaskViewModel.active(
          title: b.title,
          subtitle: sub,
          rangeLabel:
              '${_fmtHm(b.startMin)}–${_fmtHm(b.endMin)}',
          accentArgb: b.accentArgb,
          remainingMinutes: remLin,
        );
      }
    }
  }
  for (final b in blocks) {
    if (b.completed) continue;
    if (b.isOvernightLinear) {
      final remOv = _remainingOvernightBeforeMidnight(b, nowMin);
      if (remOv != null) {
        final sub =
            '${b.colorLabel} · noch ${_humanShort(remOv)}';
        return CurrentTaskViewModel.active(
          title: b.title,
          subtitle: sub,
          rangeLabel:
              '${_fmtHm(b.startMin)}→${_fmtHm(b.endMin)}(+1)',
          accentArgb: b.accentArgb,
          remainingMinutes: remOv,
        );
      }
    }
  }
  ProbeBlock? nextLin;
  for (final b in blocks) {
    if (b.completed || !b.isLinearSlot) continue;
    if (b.startMin > nowMin) {
      if (nextLin == null || b.startMin < nextLin.startMin) {
        nextLin = b;
      }
    }
  }
  if (nextLin != null) {
    final m = nextLin.startMin - nowMin;
    return CurrentTaskViewModel.active(
      title: nextLin.title.isEmpty ? '(ohne Titel)' : nextLin.title,
      subtitle: '${nextLin.colorLabel} · Beginn in ${_humanShort(m)}',
      rangeLabel:
          '${_fmtHm(nextLin.startMin)}–${_fmtHm(nextLin.endMin)}',
      accentArgb: nextLin.accentArgb,
      remainingMinutes: null,
      completed: false,
    );
  }
  for (final b in blocks) {
    if (b.completed) continue;
    if (b.allDay) {
      return CurrentTaskViewModel.active(
        title: b.title.isEmpty ? '(ohne Titel)' : b.title,
        subtitle: 'Ganztägig',
        rangeLabel: 'Ganztag',
        accentArgb: b.accentArgb,
        remainingMinutes: null,
        completed: false,
      );
    }
  }

  return const CurrentTaskViewModel.idle();
}

String _fmtHm(int minute) {
  final h = (minute ~/ 60) % 24;
  final m = minute % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Erzeugung ohne Abhängigkeit von [TimeBlock] (Felder kopieren).
ProbeBlock probeFromPlannerBlock({
  required String title,
  required int startMin,
  required int endMin,
  required String colorLabel,
  required bool completed,
  required int accentArgb,
  required bool allDay,
}) =>
    ProbeBlock(
      rawTitle: title,
      startMin: startMin,
      endMin: endMin,
      colorLabel: colorLabel,
      completed: completed,
      accentArgb: accentArgb,
      allDay: allDay,
      overnightStartAfterEnd: !allDay && startMin > endMin && startMin != endMin,
    );

String jsonPayloadForBridge(CurrentTaskViewModel vm) =>
    jsonEncode({
      'idle': vm.isIdle,
      'title': vm.isIdle ? '' : vm.title,
      'subtitle': vm.isIdle ? '' : vm.subtitle,
      'range': vm.isIdle ? '' : vm.rangeLabel,
      'accent': vm.accentArgb,
      'remain': vm.isIdle ? null : vm.remainingMinutes,
    });
