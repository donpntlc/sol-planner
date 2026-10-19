import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:sol/block_session_segment.dart';

/// Laufende Session auf der Block-Karte: Fokus = verstrichene Zeit, Pause = Countdown.
class BlockSessionLiveStrip extends StatefulWidget {
  const BlockSessionLiveStrip({
    super.key,
    required this.segments,
    required this.segmentIndex,
    required this.phaseStartedAt,
    required this.onAdvance,
    required this.onReset,
    required this.activeForeground,
    this.inkWhenActive,
    this.softWhenActive,
    required this.stripeColor,
    required this.mutedColor,
  });

  final List<BlockSessionSegment> segments;
  final int segmentIndex;
  final DateTime phaseStartedAt;
  final VoidCallback onAdvance;
  final VoidCallback onReset;
  final bool activeForeground;
  /// Gesetzt bei hellem Aktiv‑Kartengrund: dunkle Typo/Glas statt weiß auf Pastell.
  final Color? inkWhenActive;
  final Color? softWhenActive;
  final Color stripeColor;
  final Color mutedColor;

  @override
  State<BlockSessionLiveStrip> createState() => _BlockSessionLiveStripState();
}

class _BlockSessionLiveStripState extends State<BlockSessionLiveStrip>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _hapticPauseEnded = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    })..start();
  }

  @override
  void didUpdateWidget(covariant BlockSessionLiveStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segmentIndex != widget.segmentIndex ||
        oldWidget.phaseStartedAt != widget.phaseStartedAt) {
      _hapticPauseEnded = false;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _fmtMmSs(int totalSecs) {
    final m = totalSecs ~/ 60;
    final s = totalSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final segs = widget.segments;
    final idx = widget.segmentIndex;
    final customLight = widget.activeForeground && widget.inkWhenActive != null;
    Color inkLive() => widget.inkWhenActive ?? Colors.white;
    Color softLive() =>
        widget.softWhenActive ?? Colors.white.withValues(alpha: 0.88);
    Color glassFill(double aWhite) =>
        customLight ? widget.stripeColor.withValues(alpha: 0.17) : Colors.white.withValues(alpha: aWhite);
    Color glassBorder(double aWhite) => customLight
        ? widget.stripeColor.withValues(alpha: 0.48)
        : Colors.white.withValues(alpha: aWhite);
    final titleStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: widget.activeForeground ? inkLive() : null,
        );
    final subStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: widget.activeForeground ? softLive() : widget.mutedColor,
        );

    if (idx >= segs.length) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color:
              widget.activeForeground ? glassFill(0.14) : widget.stripeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.activeForeground ? glassBorder(0.35) : widget.stripeColor.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.flag_rounded,
              size: 20,
              color: widget.activeForeground ? inkLive() : widget.stripeColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Session nach Plan beendet',
                style: titleStyle,
              ),
            ),
            IconButton(
              tooltip: 'Session neu starten',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: widget.onReset,
              icon: Icon(
                Icons.restart_alt_rounded,
                size: 22,
                color: widget.activeForeground ? inkLive() : widget.mutedColor,
              ),
            ),
          ],
        ),
      );
    }

    final seg = segs[idx];
    final elapsedSecs =
        DateTime.now().difference(widget.phaseStartedAt).inSeconds.clamp(0, 1 << 30);
    final segSecs = seg.durationMinutes * 60;

    final String phaseLabel = seg.isPause ? 'Pause' : 'Fokus';
    final bool pauseDone = seg.isPause && elapsedSecs >= segSecs;

    if (pauseDone && !_hapticPauseEnded) {
      _hapticPauseEnded = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) HapticFeedback.mediumImpact();
      });
    }

    final String clockLabel;
    if (seg.isPause) {
      final left = (segSecs - elapsedSecs).clamp(0, segSecs);
      clockLabel = _fmtMmSs(left);
    } else {
      clockLabel = _fmtMmSs(elapsedSecs);
    }

    final progress = seg.isPause
        ? (segSecs <= 0 ? 1.0 : (elapsedSecs / segSecs).clamp(0.0, 1.0))
        : (segSecs <= 0 ? 0.0 : (elapsedSecs / segSecs).clamp(0.0, 1.0));

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: widget.activeForeground ? glassFill(0.12) : widget.stripeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pauseDone
              ? Colors.orangeAccent.withValues(alpha: widget.activeForeground ? 0.95 : 0.75)
              : (widget.activeForeground ? glassBorder(0.38) : widget.stripeColor.withValues(alpha: 0.42)),
          width: pauseDone ? 1.8 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                seg.isPause ? Icons.local_cafe_rounded : Icons.timer_outlined,
                size: 20,
                color: widget.activeForeground ? inkLive() : widget.stripeColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$phaseLabel · Abschnitt ${idx + 1}/${segs.length}',
                      style: titleStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      seg.isPause
                          ? (pauseDone
                              ? 'Pause vorbei — „Weiter“ zum nächsten Abschnitt'
                              : 'Runterzählen (${seg.durationMinutes} Min geplant)')
                          : 'Stoppuhr (Arbeitsphase)',
                      style: subStyle?.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Text(
                clockLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: pauseDone
                          ? Colors.orangeAccent
                          : (widget.activeForeground ? inkLive() : widget.stripeColor),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: seg.isPause ? progress : null,
              minHeight: 5,
              backgroundColor: widget.activeForeground
                  ? glassFill(0.12)
                  : widget.mutedColor.withValues(alpha: 0.2),
              color: pauseDone
                  ? Colors.orangeAccent
                  : (widget.activeForeground
                      ? (customLight ? widget.stripeColor : inkLive())
                      : widget.stripeColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: idx >= segs.length ? null : widget.onAdvance,
                icon: Icon(
                  Icons.skip_next_rounded,
                  size: 20,
                  color: widget.activeForeground ? inkLive() : widget.stripeColor,
                ),
                label: Text(
                  idx >= segs.length - 1 ? 'Beenden' : 'Weiter',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: widget.activeForeground ? inkLive() : widget.stripeColor,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: widget.onReset,
                icon: Icon(
                  Icons.restart_alt_rounded,
                  size: 20,
                  color: widget.mutedColor,
                ),
                label: Text(
                  'Neu',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: widget.mutedColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
