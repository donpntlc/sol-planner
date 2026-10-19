import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Öffnet ein Sheet mit Drehscheibe (Uhrzeiger): Verschiebung in Minuten, Snap nach Modus.
Future<int?> showFlexShiftDialSheet(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _FlexShiftDialSheet(colorScheme: scheme),
    ),
  );
}

class _FlexShiftDialSheet extends StatefulWidget {
  const _FlexShiftDialSheet({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  State<_FlexShiftDialSheet> createState() => _FlexShiftDialSheetState();
}

class _FlexShiftDialSheetState extends State<_FlexShiftDialSheet> {
  static const int _maxAbsMin = 12 * 60;

  bool _hoursMode = false;
  int _deltaMinutes = 0;
  int _lastSnap = 0;

  int get _snapStep => _hoursMode ? 60 : 5;

  void _snapDeltaFromAngle(double thetaRad) {
    final raw = (thetaRad / math.pi) * _maxAbsMin;
    var next = (raw / _snapStep).round() * _snapStep;
    if (next > _maxAbsMin) next = _maxAbsMin;
    if (next < -_maxAbsMin) next = -_maxAbsMin;
    if (next != _deltaMinutes) {
      setState(() => _deltaMinutes = next);
      if (next != _lastSnap) {
        _lastSnap = next;
        HapticFeedback.selectionClick();
      }
    }
  }

  void _onTouch(Offset local, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final theta = math.atan2(local.dx - c.dx, -(local.dy - c.dy));
    _snapDeltaFromAngle(theta);
  }

  void _onHoursModeChanged(Set<bool> sel) {
    if (sel.isEmpty) return;
    final v = sel.first;
    setState(() {
      _hoursMode = v;
      final step = v ? 60 : 5;
      _deltaMinutes = (_deltaMinutes / step).round() * step;
      _deltaMinutes = _deltaMinutes.clamp(-_maxAbsMin, _maxAbsMin);
      _lastSnap = _deltaMinutes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.colorScheme;
    final body = Theme.of(context).textTheme.bodyMedium;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                'Um wie viel verschieben?',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Zeiger wie an einer Uhr drehen — gilt für alle gewählten Blöcke.',
                style: body?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Minuten'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Stunden'),
                  ),
                ],
                selected: {_hoursMode},
                onSelectionChanged: _onHoursModeChanged,
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  _formatDeltaLabel(_deltaMinutes),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: SizedBox(
                  height: 220,
                  width: 220,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = math.min(constraints.maxWidth, constraints.maxHeight);
                      final size = Size(side, side);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanDown: (d) => _onTouch(d.localPosition, size),
                        onPanUpdate: (d) => _onTouch(d.localPosition, size),
                        child: CustomPaint(
                          size: size,
                          painter: _ShiftDialPainter(
                            scheme: scheme,
                            handAngleRad: (_deltaMinutes / _maxAbsMin) * math.pi,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Links / gegen den Uhrzeiger = früher · rechts / im Uhrzeiger = später',
                textAlign: TextAlign.center,
                style: body?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _deltaMinutes == 0
                        ? null
                        : () => Navigator.pop(context, _deltaMinutes),
                    child: const Text('Anwenden'),
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

String _formatDeltaLabel(int m) {
  if (m == 0) return 'Keine Verschiebung';
  final neg = m < 0;
  final a = m.abs();
  final h = a ~/ 60;
  final min = a % 60;
  final buf = StringBuffer(neg ? '−' : '+');
  if (h > 0) {
    buf.write('$h Std.');
  }
  if (min > 0) {
    if (h > 0) buf.write(' ');
    buf.write('$min Min.');
  }
  return buf.toString().trim();
}

class _ShiftDialPainter extends CustomPainter {
  _ShiftDialPainter({
    required this.scheme,
    required this.handAngleRad,
  });

  final ColorScheme scheme;
  final double handAngleRad;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 8;

    final facePaint = Paint()
      ..color = scheme.surfaceContainerHighest.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, r, facePaint);

    final border = Paint()
      ..color = scheme.outline.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, r, border);

    final tickMajor = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final tickMinor = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.28)
      ..strokeWidth = 1;

    for (var i = 0; i < 12; i++) {
      final ang = (i / 12) * 2 * math.pi - math.pi / 2;
      final outer = Offset(c.dx + math.cos(ang) * r, c.dy + math.sin(ang) * r);
      final inner = Offset(
        c.dx + math.cos(ang) * (r - (i % 3 == 0 ? 14 : 8)),
        c.dy + math.sin(ang) * (r - (i % 3 == 0 ? 14 : 8)),
      );
      canvas.drawLine(inner, outer, i % 3 == 0 ? tickMajor : tickMinor);
    }

    final hub = Paint()..color = scheme.primary;
    canvas.drawCircle(c, 8, hub);

    final hx = math.sin(handAngleRad);
    final hy = -math.cos(handAngleRad);
    final tip = Offset(c.dx + hx * (r - 18), c.dy + hy * (r - 18));

    final handPaint = Paint()
      ..color = scheme.primary
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c, tip, handPaint);

    final dot = Paint()..color = scheme.onPrimary;
    canvas.drawCircle(tip, 5, dot);
  }

  @override
  bool shouldRepaint(covariant _ShiftDialPainter oldDelegate) =>
      oldDelegate.handAngleRad != handAngleRad || oldDelegate.scheme != scheme;
}
