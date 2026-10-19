import 'package:flutter/material.dart';

import 'models.dart';

/// Optische Größe wie auf iOS‑Lockscreen / Home: von „eine Zeile“ bis volle Karte.
enum CurrentTaskVisualSize {
  /// Eine Zeile, klein — z. B. Lockscreen inline / kompakte Leiste
  compact,

  /// Standard: Titel + Subtitel
  medium,

  /// Groß: Titel, Subtitel, Zeitfenster-Badge
  expanded,
}

/// Zeigt den **aktuellen Plan-Slot** oder einen Leerzustand.
/// Daten kommen von [resolveCurrentPlannerTask].
class CurrentPlannerTaskCard extends StatelessWidget {
  const CurrentPlannerTaskCard({
    super.key,
    required this.vm,
    required this.size,
    this.onTap,
    this.padding,
  });

  final CurrentTaskViewModel vm;
  final CurrentTaskVisualSize size;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  Color _accent() => Color(vm.accentArgb).withValues(alpha: 1);

  Color _surfaceFill(BuildContext context, Color accent, bool idle) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.95);
    if (idle) return base;
    if (Theme.of(context).brightness == Brightness.dark) return base;
    // Hell: Stripe-Füllung an den Plan‑Karten anlehnen, damit keine weiße Typo auf Blechgrau liegt.
    return Color.alphaBlend(
      accent.withValues(alpha: 0.38),
      base,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.62);

    final idle = vm.isIdle;
    final accent = _accent();
    final borderColor = idle
        ? accent.withValues(alpha: 0.55)
        : accent.withValues(alpha: 0.92);
    final cardFill = _surfaceFill(context, accent, idle);

    EdgeInsets pad;
    switch (size) {
      case CurrentTaskVisualSize.compact:
        pad = const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
      case CurrentTaskVisualSize.medium:
        pad = const EdgeInsets.fromLTRB(14, 12, 14, 12);
      case CurrentTaskVisualSize.expanded:
        pad = const EdgeInsets.fromLTRB(16, 14, 16, 14);
    }

    return Material(
      color: cardFill,
      elevation: Theme.of(context).brightness == Brightness.dark ? 0 : 0.75,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: idle ? 1.0 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withValues(alpha: 0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: padding ?? pad,
          child: _body(context, accent, muted, idle),
        ),
      ),
    );
  }

  /// Aktiver Slot: Hellmodus dunkle Typo auf getöntem Grund; dunkel weiße Typo.
  (Color fg, Color fgSoft) _activeForeground(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    if (Theme.of(context).brightness != Brightness.light) {
      return (Colors.white, Colors.white.withValues(alpha: 0.92));
    }
    return (s.onSurface, s.onSurface.withValues(alpha: 0.74));
  }

  Widget _body(
    BuildContext context,
    Color accent,
    Color mutedText,
    bool idle,
  ) {
    final activePair = _activeForeground(context);

    if (size == CurrentTaskVisualSize.compact) {
      final line = idle
          ? 'Gerade kein Block'
          : '${vm.title}${vm.subtitle.isEmpty ? '' : ' · ${vm.subtitle}'}';
      return Row(
        children: [
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
              color:
                  idle ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.6) : accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.12,
                height: 1.2,
                color: idle ? null : activePair.$1,
              ),
            ),
          ),
        ],
      );
    }

    if (size == CurrentTaskVisualSize.medium) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stripe(accent, idle, 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  idle ? 'Aktueller Block' : vm.title,
                  maxLines: idle ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: idle ? null : activePair.$1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  idle ? 'Kein Slot in dieser Minute' : vm.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: idle ? mutedText : activePair.$2,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _stripe(accent, idle, 48),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                idle ? 'Aktueller Block' : vm.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                  color: idle ? null : activePair.$1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          idle ? 'Im Kalender ist für jetzt nichts geplant.' : vm.subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color:
                idle ? mutedText : activePair.$2,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (!idle && vm.rangeLabel.isNotEmpty) ...[
          const SizedBox(height: 10),
          Builder(
            builder: (ctx) {
              final light = Theme.of(ctx).brightness == Brightness.light;
              final badgeFill = accent.withValues(alpha: light ? 0.2 : 0.28);
              final badgeInk =
                  light ? Theme.of(ctx).colorScheme.onSurface : Colors.white;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.75)),
                ),
                child: Text(
                  vm.rangeLabel,
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: badgeInk,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _stripe(Color accent, bool idle, double h) {
    return Container(
      width: 5,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color:
            idle ? const Color(0xFF94A3B8).withValues(alpha: 0.55) : accent,
      ),
    );
  }
}
