import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random, min, max, sqrt;
import 'dart:ui' show FontFeature, PlatformDispatcher;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sol/flex_shift_dial_sheet.dart';
import 'package:sol/block_session_segment.dart';
import 'package:sol/planner_notifications.dart';
import 'package:sol/planner_reminder_prefs.dart';
import 'package:sol/project_rotation.dart';
import 'package:sol/web_safe_area.dart';
import 'package:sol/reminder_prefs_sheet.dart';
import 'package:sol/widgets/block_session_live_strip.dart';
import 'package:sol/widgets/current_task/current_task_package.dart';

import 'package:sol/cloud/sol_cloud_config.dart';
import 'package:sol/cloud/sol_cloud_sync_sheet.dart';
import 'package:sol/cloud/sol_planner_cloud_sync.dart';
import 'package:sol/cloud/sol_planner_sync_hook.dart';

/// Gesamtskalierung der Oberfläche (1.0 = normal, 0.88 = etwas rausgezoomt).
const double _kAppUiScale = 0.88;

const _kColorPickerDragScale =
    0.48; // <1: gleiche Fingerbewegung → kleinere Farbänderung (feinere Bedienung).
const _kHuePickerDragScale = 0.52;

/// Fixiert den Startpunkt eines Drags im Farbwahl-Sheet (über [StatefulBuilder]-Rebuilds hinweg).
class _ColorSheetDragAnchors {
  bool svPressed = false;
  Offset svOrigin = Offset.zero;
  double satAnchor = 0;
  double valAnchor = 0;

  bool huePressed = false;
  double hueYAnchor = 0;
  double hueAnchorDegrees = 0;
}

/// Überall elastisches Überrollen wie auf iOS, statt abruptem „Wand-Stopp“.
class _BouncyScrollBehavior extends MaterialScrollBehavior {
  const _BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
    return true;
  };
  // Auf Web: keine dynamischen Font-Downloads → weniger Main-Thread-Freezes.
  GoogleFonts.config.allowRuntimeFetching = !kIsWeb;
  await SolPlannerCloudCoordinator.initIfConfigured();
  _applySystemChrome(AppPalette.dark);
  String? plannerDaysJson;
  try {
    final prefs = await SharedPreferences.getInstance();
    plannerDaysJson = prefs.getString(_kPlannerCachedDaysPrefKey);
  } catch (_) {}
  runApp(DayPlannerApp(initialPlannerDaysJson: plannerDaysJson));
}

void _applySystemChrome(AppPalette p) {
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: p.bg,
      systemNavigationBarIconBrightness: p.isDark
          ? Brightness.light
          : Brightness.dark,
    ),
  );
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.hairline,
    required this.text,
    required this.muted,
    required this.hintBg,
    required this.accent,
    required this.weekSelected,
    required this.weekUnsel,
    required this.chipBg,
    required this.chipSelected,
    required this.tonalButtonBg,
    required this.stripeFillAlpha,
  });

  final bool isDark;
  final Color bg;
  final Color surface;
  final Color hairline;
  final Color text;
  final Color muted;
  final Color hintBg;
  final Color accent;
  final Color weekSelected;
  final Color weekUnsel;
  final Color chipBg;
  final Color chipSelected;
  final Color tonalButtonBg;
  final double stripeFillAlpha;

  /// Leichte Schatten nur außerhalb Web (Canvas-Blur ist auf Web teuer).
  List<BoxShadow>? get cardShadows {
    if (kIsWeb) return null;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.07),
        blurRadius: isDark ? 10 : 16,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static const AppPalette light = AppPalette(
    isDark: false,
    bg: Color(0xFFF3F4F6),
    surface: Color(0xFFFCFCFD),
    hairline: Color(0xFFE2E5EB),
    text: Color(0xFF111318),
    muted: Color(0xFF6B7280),
    hintBg: Color(0xFFEDF0F4),
    accent: Color(0xFF3F4654),
    weekSelected: Color(0xFF2A2F3A),
    weekUnsel: Color(0xFFE5E8ED),
    chipBg: Color(0xFFE8EBF0),
    chipSelected: Color(0xFFD6DAE2),
    tonalButtonBg: Color(0xFFE8EBF0),
    stripeFillAlpha: 0.06,
  );

  /// „Dezentes“ Dark-UI: tiefes Schwarz, warme Neutrals, gedämpfter Amber (analog Tracking-Look).
  static const AppPalette dark = AppPalette(
    isDark: true,
    bg: Color(0xFF121212),
    surface: Color(0xFF1C1C1C),
    hairline: Color(0xFF3A3430),
    text: Color(0xFFF5F3F0),
    muted: Color(0xFFA8A29E),
    hintBg: Color(0xFF1A1A1A),
    accent: Color(0xFFC4A574),
    weekSelected: Color(0xFFEDE4DB),
    weekUnsel: Color(0xFF2A2420),
    chipBg: Color(0xFF262220),
    chipSelected: Color(0xFF3A322C),
    tonalButtonBg: Color(0xFF262220),
    stripeFillAlpha: 0.06,
  );

  @override
  AppPalette copyWith({
    bool? isDark,
    Color? bg,
    Color? surface,
    Color? hairline,
    Color? text,
    Color? muted,
    Color? hintBg,
    Color? accent,
    Color? weekSelected,
    Color? weekUnsel,
    Color? chipBg,
    Color? chipSelected,
    Color? tonalButtonBg,
    double? stripeFillAlpha,
  }) {
    return AppPalette(
      isDark: isDark ?? this.isDark,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      hairline: hairline ?? this.hairline,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      hintBg: hintBg ?? this.hintBg,
      accent: accent ?? this.accent,
      weekSelected: weekSelected ?? this.weekSelected,
      weekUnsel: weekUnsel ?? this.weekUnsel,
      chipBg: chipBg ?? this.chipBg,
      chipSelected: chipSelected ?? this.chipSelected,
      tonalButtonBg: tonalButtonBg ?? this.tonalButtonBg,
      stripeFillAlpha: stripeFillAlpha ?? this.stripeFillAlpha,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return t < 0.5 ? this : other;
  }
}

extension PlanningPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

ThemeData _buildPlannerTheme(AppPalette p, Brightness b) {
  final base = ThemeData(brightness: b, useMaterial3: true);
  final TextTheme textTheme;
  if (kIsWeb) {
    // System-TextTheme — kein Nunito-Fetch, schnellere erste Interaktionen.
    textTheme = base.textTheme.apply(bodyColor: p.text, displayColor: p.text);
  } else {
    textTheme = GoogleFonts.nunitoSansTextTheme(
      base.textTheme,
    ).apply(bodyColor: p.text, displayColor: p.text);
  }
  // Teure M3-Splashes auf Web sparen viel compositing.
  final noWebRipple = kIsWeb
      ? ButtonStyle(
          overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        )
      : null;
  final filledBase = FilledButton.styleFrom(
    backgroundColor: p.accent,
    foregroundColor: p.isDark
        ? const Color(0xFF0B0C0F)
        : const Color(0xFFF8F9FB),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    splashColor: kIsWeb ? Colors.transparent : null,
    highlightColor: kIsWeb ? Colors.transparent : null,
    hoverColor: kIsWeb ? Colors.transparent : null,
    splashFactory: kIsWeb ? NoSplash.splashFactory : null,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    extensions: <ThemeExtension<dynamic>>[p],
    textTheme: textTheme,
    iconButtonTheme: IconButtonThemeData(style: noWebRipple),
    textButtonTheme: TextButtonThemeData(style: noWebRipple),
    outlinedButtonTheme: OutlinedButtonThemeData(style: noWebRipple),
    filledButtonTheme: FilledButtonThemeData(
      style: kIsWeb ? filledBase.merge(noWebRipple!) : filledBase,
    ),
    colorScheme: ColorScheme(
      brightness: b,
      primary: p.accent,
      onPrimary: p.isDark ? const Color(0xFF0B0C0F) : const Color(0xFFF8F9FB),
      secondary: p.hairline,
      onSecondary: p.text,
      error: const Color(0xFFB00020),
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.chipBg,
      selectedColor: p.chipSelected,
      labelStyle: TextStyle(color: p.text, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerColor: p.hairline,
  );
}

class DayPlannerApp extends StatefulWidget {
  const DayPlannerApp({super.key, this.initialPlannerDaysJson});

  /// Aus SharedPreferences in [main] geladen, damit der erste Frame nicht schon das Preset einträgt.
  final String? initialPlannerDaysJson;

  @override
  State<DayPlannerApp> createState() => _DayPlannerAppState();
}

class _DayPlannerAppState extends State<DayPlannerApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: const _BouncyScrollBehavior(),
      debugShowCheckedModeBanner: false,
      title: 'SOL - Planer',
      theme: _buildPlannerTheme(AppPalette.light, Brightness.light),
      darkTheme: _buildPlannerTheme(AppPalette.dark, Brightness.dark),
      themeMode: _themeMode,
      builder: (context, child) {
        // Große Systemschrift (iOS „Textgröße“) nicht übernehmen und die ganze
        // Oberfläche leicht verkleinern (wie „rauszoomen“), damit mehr aufs Handy passt.
        final mq = MediaQuery.of(context);
        const uiScale = _kAppUiScale;
        final logical = mq.size / uiScale;
        // Im Browser kennt Flutter die iPhone-Ränder nicht → aus index.html übernehmen.
        final sys = kIsWeb ? webSafeAreaInsets() : EdgeInsets.zero;
        EdgeInsets withSys(EdgeInsets e) => EdgeInsets.fromLTRB(
          max(e.left, sys.left),
          max(e.top, sys.top),
          max(e.right, sys.right),
          max(e.bottom, sys.bottom),
        );
        final inner = MediaQuery(
          data: mq.copyWith(
            size: logical,
            padding: withSys(mq.padding) / uiScale,
            viewPadding: withSys(mq.viewPadding) / uiScale,
            viewInsets: mq.viewInsets / uiScale,
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.0,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
        if (uiScale == 1.0 || mq.size.isEmpty) return inner;
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: logical.width,
            height: logical.height,
            child: inner,
          ),
        );
      },
      home: PlannerHome(
        initialPlannerDaysJson: widget.initialPlannerDaysJson,
        onToggleAppearance: () {
          setState(() {
            _themeMode = _themeMode == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
            _applySystemChrome(
              _themeMode == ThemeMode.dark ? AppPalette.dark : AppPalette.light,
            );
          });
        },
      ),
    );
  }
}

class PlannerHome extends StatefulWidget {
  const PlannerHome({
    super.key,
    required this.onToggleAppearance,
    this.initialPlannerDaysJson,
  });

  /// Roh-JSON aus dem gleichen Speicher wie [_kPlannerCachedDaysPrefKey] (siehe [main]).
  final String? initialPlannerDaysJson;

  final VoidCallback onToggleAppearance;

  @override
  State<PlannerHome> createState() => _PlannerHomeState();
}

enum PlannerPresetType {
  hustle,
  hustle530,
  monk,
  alltag,
  wochenende,
  urlaub,
  dayOff,
}

enum BlockRecurrence { none, daily, weekly, monthly }

class DeepWorkTodoItem {
  DeepWorkTodoItem({required this.id, required this.title, this.done = false});

  final String id;
  String title;
  bool done;

  DeepWorkTodoItem copyWith({String? id, String? title, bool? done}) {
    return DeepWorkTodoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      done: done ?? this.done,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'done': done,
  };

  factory DeepWorkTodoItem.fromJson(Map<String, dynamic> j) {
    return DeepWorkTodoItem(
      id: ((j['id'] as String?) ?? '').trim(),
      title: ((j['title'] as String?) ?? '').trim(),
      done: (j['done'] as bool?) ?? false,
    );
  }
}

class BlockSubtask {
  BlockSubtask({required this.id, required this.title, this.done = false});

  final String id;
  String title;
  bool done;

  BlockSubtask copyWith({String? id, String? title, bool? done}) {
    return BlockSubtask(
      id: id ?? this.id,
      title: title ?? this.title,
      done: done ?? this.done,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'done': done,
  };

  factory BlockSubtask.fromJson(Map<String, dynamic> j) {
    return BlockSubtask(
      id: (j['id'] as String?)?.trim().isNotEmpty == true
          ? j['id'] as String
          : 's_${j.hashCode}',
      title: (j['title'] as String?) ?? '',
      done: j['done'] as bool? ?? false,
    );
  }
}

class _ClockLane {
  const _ClockLane.block(this.block)
    : startMin = 0,
      endMin = 0,
      isGap = false;

  const _ClockLane.gap(this.startMin, this.endMin)
    : block = null,
      isGap = true;

  final TimeBlock? block;
  final int startMin;
  final int endMin;
  final bool isGap;

  int get laneStart => block?.startMin ?? startMin;

  int get laneEnd => block != null
      ? (block!.allDay ? 1440 : block!.endMin)
      : endMin;

  int get gapSpan {
    if (startMin < endMin) return endMin - startMin;
    return 0;
  }
}

class TimeBlock {
  TimeBlock({
    required this.id,
    required this.title,
    required this.startMin,
    required this.endMin,
    required this.emoji,
    required this.colorLabel,
    this.pinned = false,
    this.notes = '',
    this.allDay = false,
    this.recurrence = BlockRecurrence.none,
    List<BlockSubtask>? subtasks,
    this.completed = false,
    this.recurrenceWeekdayMask = 0,
    this.recurrenceMonthDay = 1,
    this.customIconCodePoint,
    this.customStripeHex,
    this.muteReminders = false,
    List<BlockSessionSegment>? sessionSegments,
  }) : subtasks = List<BlockSubtask>.from(subtasks ?? const []),
       sessionSegments =
           List<BlockSessionSegment>.from(sessionSegments ?? const []);

  final String id;
  String title;
  int startMin;
  int endMin;
  String emoji;
  String colorLabel;
  bool pinned;
  String notes;
  bool allDay;
  BlockRecurrence recurrence;

  /// Bits 0..6 = Mo..So; 0 bei wöchentlich = alle Tage.
  int recurrenceWeekdayMask;

  /// 1–28 (sichere Monats-Intervalle).
  int recurrenceMonthDay;

  /// Eigene Material-Icon-Codepoint → [IconData] statt Kategorie-Icon.
  int? customIconCodePoint;

  /// Optional: ARGB-Hex (`_colorToHexArgb`); gesetzt → Rand/Schein statt Kategoriefarbe.
  String? customStripeHex;
  List<BlockSubtask> subtasks;
  bool completed;

  /// Optional: geplante Fokus-/Pause-Abschnitte (Summe = Blockdauer bei linearem Slot).
  List<BlockSessionSegment> sessionSegments;

  /// Pro Block: keine App-/OS-Erinnerungen (globale Erinnerungen bleiben sonst aktiv).
  bool muteReminders;

  /// Gleicher Kalendertag [0,1440): Start vor Ende.
  bool get isLinearSlot => !allDay && startMin < endMin;

  /// Über Mitternacht (nicht Ganztags): Start nach Ende am Folgetag.
  bool get isOvernightSlot => !allDay && startMin > endMin;

  /// Minuten zwischen Start und Ende (Ganztags = 1440; Übernacht korrekt).
  int get spanMinutes {
    if (allDay) return 1440;
    if (startMin < endMin) return endMin - startMin;
    if (startMin > endMin) return (1440 - startMin) + endMin;
    return 0;
  }

  /// Alias für bestehende Aufrufe (`duration`).
  int get duration => spanMinutes;

  TimeBlock copyWith({
    String? id,
    String? title,
    int? startMin,
    int? endMin,
    String? emoji,
    String? colorLabel,
    bool? pinned,
    String? notes,
    bool? allDay,
    BlockRecurrence? recurrence,
    List<BlockSubtask>? subtasks,
    List<BlockSessionSegment>? sessionSegments,
    bool? completed,
    int? recurrenceWeekdayMask,
    int? recurrenceMonthDay,
    int? customIconCodePoint,
    String? customStripeHex,
    bool clearCustomStripe = false,
    bool? muteReminders,
  }) {
    return TimeBlock(
      id: id ?? this.id,
      title: title ?? this.title,
      startMin: startMin ?? this.startMin,
      endMin: endMin ?? this.endMin,
      emoji: emoji ?? this.emoji,
      colorLabel: colorLabel ?? this.colorLabel,
      pinned: pinned ?? this.pinned,
      notes: notes ?? this.notes,
      allDay: allDay ?? this.allDay,
      recurrence: recurrence ?? this.recurrence,
      recurrenceWeekdayMask:
          recurrenceWeekdayMask ?? this.recurrenceWeekdayMask,
      recurrenceMonthDay: recurrenceMonthDay ?? this.recurrenceMonthDay,
      customIconCodePoint: customIconCodePoint ?? this.customIconCodePoint,
      customStripeHex: clearCustomStripe
          ? null
          : (customStripeHex ?? this.customStripeHex),
      subtasks: subtasks != null
          ? List<BlockSubtask>.from(subtasks.map((s) => s.copyWith()))
          : List<BlockSubtask>.from(this.subtasks.map((s) => s.copyWith())),
      sessionSegments: sessionSegments != null
          ? List<BlockSessionSegment>.from(
              sessionSegments.map((s) => s.copyWith()),
            )
          : List<BlockSessionSegment>.from(
              this.sessionSegments.map((s) => s.copyWith()),
            ),
      completed: completed ?? this.completed,
      muteReminders: muteReminders ?? this.muteReminders,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startMin': startMin,
    'endMin': endMin,
    'emoji': emoji,
    'colorLabel': colorLabel,
    'pinned': pinned,
    'notes': notes,
    'allDay': allDay,
    'recurrence': recurrence.name,
    'recurrenceWeekdayMask': recurrenceWeekdayMask,
    'recurrenceMonthDay': recurrenceMonthDay,
    'customIconCodePoint': customIconCodePoint,
    'customStripeHex': customStripeHex,
    'subtasks': subtasks.map((s) => s.toJson()).toList(),
    'sessionSegments': sessionSegments.map((s) => s.toJson()).toList(),
    'completed': completed,
    'muteReminders': muteReminders,
  };

  factory TimeBlock.fromJson(Map<String, dynamic> j) {
    BlockRecurrence rec = BlockRecurrence.none;
    final rs = j['recurrence'];
    if (rs is String) {
      for (final v in BlockRecurrence.values) {
        if (v.name == rs) {
          rec = v;
          break;
        }
      }
    }
    final subs = <BlockSubtask>[];
    final rawSubs = j['subtasks'];
    if (rawSubs is List) {
      for (final item in rawSubs) {
        if (item is Map<String, dynamic>) {
          subs.add(BlockSubtask.fromJson(item));
        } else if (item is Map) {
          subs.add(BlockSubtask.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final segs = <BlockSessionSegment>[];
    final rawSeg = j['sessionSegments'];
    if (rawSeg is List) {
      for (final item in rawSeg) {
        if (item is Map<String, dynamic>) {
          segs.add(BlockSessionSegment.fromJson(item));
        } else if (item is Map) {
          segs.add(BlockSessionSegment.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return TimeBlock(
      id: (j['id'] as String?)?.trim().isNotEmpty == true
          ? j['id'] as String
          : 'b_restore',
      title: (j['title'] as String?) ?? '',
      startMin: (j['startMin'] as num?)?.toInt() ?? 0,
      endMin: (j['endMin'] as num?)?.toInt() ?? 60,
      emoji: (j['emoji'] as String?) ?? '',
      colorLabel: (j['colorLabel'] as String?)?.trim().isNotEmpty == true
          ? j['colorLabel'] as String
          : 'Routine',
      pinned: j['pinned'] as bool? ?? false,
      notes: (j['notes'] as String?) ?? '',
      allDay: j['allDay'] as bool? ?? false,
      recurrence: rec,
      subtasks: subs,
      completed: j['completed'] as bool? ?? false,
      recurrenceWeekdayMask:
          (j['recurrenceWeekdayMask'] as num?)?.toInt() ?? 0,
      recurrenceMonthDay: (j['recurrenceMonthDay'] as num?)?.toInt() ?? 1,
      customIconCodePoint: (j['customIconCodePoint'] as num?)?.toInt(),
      customStripeHex: j['customStripeHex'] as String?,
      muteReminders: j['muteReminders'] as bool? ?? false,
      sessionSegments: segs,
    );
  }
}

class PresetWindow {
  PresetWindow({
    required this.from,
    this.to,
    required this.presetKey,
    this.weekdayMask = 0,
  });

  final DateTime from;

  /// `null` = Open End (kein Endedatum).
  final DateTime? to;

  /// `PlannerPresetType.name` (z. B. `hustle`) oder `u:<id>` für eigene Preset-Tage.
  final String presetKey;

  /// 0 = jeder Wochentag im Zeitraum; sonst Mo=Bit0 … So=Bit6.
  final int weekdayMask;

  bool get isOpenEnd => to == null;

  bool contains(DateTime d) {
    final day = _onlyDay(d);
    if (day.isBefore(_onlyDay(from))) return false;
    final until = to;
    if (until == null) return true;
    return !day.isAfter(_onlyDay(until));
  }

  bool matchesWeekday(DateTime d) {
    if (weekdayMask == 0) return true;
    final i = d.weekday - 1;
    return (weekdayMask & (1 << i)) != 0;
  }
}

// ─── Mahlzeit-Darstellung (nur für unten gelistete Kategorien) ────────────────
/// Gemeinsamer Ton für Rahmen und Fläche — **nur diese beiden Hex-Werte** nach Geschmack ändern.
/// Dezent halten: Umrandung etwas kräftiger als die helle Fläche (Alphas darunter steuerbar).
const Color _kMealAccentPrimary = Color(0xFF4A6B52); // Mahlzeit — dezentes Grün
const Color _kMealAccentSoft = Color(0xFF556F5C);

/// Alpha-Stufen — kleiner = subtiler.
abstract final class MealBlockTheme {
  static const Color outline = _kMealAccentPrimary;
  /// Etwas heller als [outline], nur für BoxShadow — sonst verschwindet der Glow auf dunklem Theme.
  static const Color shadowGlow = Color(0xFF6CAD7E);
  static const Color fillBase = _kMealAccentSoft;

  /// Große Karte (Timeline rechts)
  static const double cardFillAlpha = 0.07;
  static const double cardFillSelectedAlpha = 0.12;
  static const double borderAlpha = 0.34;
  static const double borderSelectedAlpha = 0.52;

  /// Kleine Icon-Kachel an der Achse
  static const double pillFillAlpha = 0.09;
  static const double pillBorderAlpha = 0.42;
}

/// Kategorien mit [MealBlockTheme] (Rahmen/Fläche) — derzeit nur **Mahlzeit** (grün).
const Set<String> kMealStyleCategories = {'Mahlzeit'};

bool _categoryUsesMealVisual(String colorLabel) =>
    kMealStyleCategories.contains(colorLabel);

/// Vier **Preset-Kategorien** (im Farb-Dialog pro Nutzer anpassbar):
/// **Mahlzeit** (grün), **Fokus** (gold — was zu tun ist), **Routine** (hell — Alltag im Plan),
/// **Wichtig** (rot — besonders beachten / prüfen).
const Map<String, Color> kDefaultCategoryColors = {
  'Mahlzeit': _kMealAccentPrimary,
  'Fokus': Color(0xFFC4A574),
  'Routine': Color(0xFFADA8A2),
  'Wichtig': Color(0xFF9A4E4E),
};

/// Reihenfolge der eingebauten vier Kategorien (für UI & Migration).
const List<String> kCanonicalDefaultCategoryOrder = [
  'Mahlzeit',
  'Fokus',
  'Routine',
  'Wichtig',
];

/// Eine Zeile im Vorlagen-Raster eines Modus (Titel, Zeiten, Kategorie/Farbbereich, Notizen).
class PresetTaskLine {
  PresetTaskLine({
    required this.title,
    required this.startMin,
    required this.endMin,
    required this.colorLabel,
    this.notes = '',
  });

  final String title;
  final int startMin;
  final int endMin;
  final String colorLabel;
  final String notes;

  PresetTaskLine copy() => PresetTaskLine(
    title: title,
    startMin: startMin,
    endMin: endMin,
    colorLabel: colorLabel,
    notes: notes,
  );

  PresetTaskLine copyWith({
    String? title,
    int? startMin,
    int? endMin,
    String? colorLabel,
    String? notes,
  }) {
    return PresetTaskLine(
      title: title ?? this.title,
      startMin: startMin ?? this.startMin,
      endMin: endMin ?? this.endMin,
      colorLabel: colorLabel ?? this.colorLabel,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'startMin': startMin,
    'endMin': endMin,
    'colorLabel': colorLabel,
    'notes': notes,
  };

  factory PresetTaskLine.fromJson(Map<String, dynamic> j) {
    var rawCat = (j['colorLabel'] as String?)?.trim() ?? '';
    if (rawCat.isEmpty) rawCat = 'Routine';
    if (rawCat == 'Lesen') rawCat = 'Wichtig';
    return PresetTaskLine(
      title: ((j['title'] as String?) ?? '').trim(),
      startMin: ((j['startMin'] as num?)?.toInt().clamp(0, 1440)) ?? 0,
      endMin: ((j['endMin'] as num?)?.toInt().clamp(0, 1440)) ?? 60,
      colorLabel: rawCat,
      notes: (j['notes'] as String?) ?? '',
    );
  }
}

/// Nutzerdefinierter Preset-Tag (eigenes Raster, Name frei wählbar).
class UserPresetDay {
  UserPresetDay({required this.id, required this.name, required this.lines});

  final String id;
  final String name;
  final List<PresetTaskLine> lines;

  UserPresetDay copyWith({
    String? id,
    String? name,
    List<PresetTaskLine>? lines,
  }) {
    return UserPresetDay(
      id: id ?? this.id,
      name: name ?? this.name,
      lines: lines != null
          ? List<PresetTaskLine>.from(lines.map((e) => e.copy()))
          : List<PresetTaskLine>.from(this.lines.map((e) => e.copy())),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lines': lines.map((x) => x.toJson()).toList(),
  };

  factory UserPresetDay.fromJson(Map<String, dynamic> j) {
    final id = ((j['id'] as String?) ?? '').trim();
    final rawLines = j['lines'];
    final lines = <PresetTaskLine>[];
    if (rawLines is List) {
      for (final item in rawLines) {
        if (item is Map<String, dynamic>)
          lines.add(PresetTaskLine.fromJson(item));
      }
    }
    return UserPresetDay(
      id: id.isEmpty ? _newUserPresetDayIdStatic() : id,
      name: ((j['name'] as String?) ?? 'Preset').trim().isEmpty
          ? 'Preset'
          : ((j['name'] as String?) ?? '').trim(),
      lines: lines,
    );
  }
}

String _newUserPresetDayIdStatic() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

const String _kCategoryColorsPrefKey = 'planner_category_colors_v2';
const String _kCategoryCatalogPrefKey = 'planner_category_catalog_v1';

const String _kPresetTaskTemplatesPrefKey = 'planner_preset_task_templates_v1';

const String _kUserPresetDaysPrefKey = 'planner_user_preset_days_v1';

const String _kFreeformDayNotesPrefKey = 'planner_day_freeform_notes_v1';
/// Geänderte Tagespläne (Blöcke + Preset-Zuordnung), damit Flex/Reihenfolge erhalten bleibt.
const String _kPlannerCachedDaysPrefKey = 'planner_cached_days_v1';
const String _kCustomStripeSwatchesPrefKey =
    'planner_custom_stripe_swatches_v1';
const String _kCustomCategorySwatchesPrefKey =
    'planner_custom_category_swatches_v1';
const String _kSubtaskQuickPresetsPrefKey = 'planner_subtask_quick_presets_v1';
const String _kBuiltinPresetDisplayNamesPrefKey =
    'planner_builtin_preset_display_names_v1';

const String _kFirstLaunchWelcomeShownPrefKey =
    'planner_first_launch_welcome_shown_v1';
const String _kDeepWorkTodoEnabledPrefKey = 'planner_deep_work_todo_enabled_v1';
const String _kDeepWorkTodoItemsPrefKey = 'planner_deep_work_todo_items_v1';
const String _kShowFreeTimeLanesPrefKey = 'planner_show_free_time_lanes_v1';
const String _kActivePresetPrefKey = 'planner_active_preset_key_v1';

/// Standard-Vorlagen für die Checklisten-Schnellauswahl im Block-Dialog.
const List<String> kDefaultSubtaskQuickPresets = [
  'Lesen',
  'Scrollen',
  'Sprache lernen',
  'Instrument spielen',
  'Schreiben / Zeichnen',
  'Sport / Bewegung',
];

bool _presetLinesEqual(List<PresetTaskLine> a, List<PresetTaskLine> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].title != b[i].title ||
        a[i].startMin != b[i].startMin ||
        a[i].endMin != b[i].endMin ||
        a[i].colorLabel != b[i].colorLabel ||
        a[i].notes.trim() != b[i].notes.trim()) {
      return false;
    }
  }
  return true;
}

/// Tagesstart einer Vorlage: Ende des Übernacht-Blocks (Schlaf), sonst frühester Start.
int presetDayStartMinute(List<PresetTaskLine> lines) {
  if (lines.isEmpty) return 0;
  for (final l in lines) {
    final end = l.endMin % 1440;
    if (l.startMin > end && end > 0) return end;
  }
  var minStart = 1440;
  for (final l in lines) {
    if (l.startMin < minStart) minStart = l.startMin;
  }
  return minStart == 1440 ? 0 : minStart;
}

/// Verschiebt alle Zeilen um [delta] Minuten (Dauer bleibt, Mitternacht wird umgebrochen).
List<PresetTaskLine> shiftPresetLines(List<PresetTaskLine> lines, int delta) {
  int wrap(int m) => ((m % 1440) + 1440) % 1440;
  return lines.map((l) {
    final dur = l.startMin < l.endMin
        ? l.endMin - l.startMin
        : (1440 - l.startMin) + l.endMin;
    final s = wrap(l.startMin + delta);
    var e = wrap(s + dur);
    if (e == 0) e = 1440;
    return l.copyWith(startMin: s, endMin: e);
  }).toList();
}

/// Variant von [PlannerPresetType.hustle]: Wecken 05:30, späterer Abend, Schlaffenster bis 05:30.
List<PresetTaskLine> builtinHustle530Lines() => [
      PresetTaskLine(
        title: 'Morgen Routine',
        startMin: 330,
        endMin: 390,
        colorLabel: 'Routine',
      ),
      PresetTaskLine(
        title: 'Deep Work',
        startMin: 390,
        endMin: 540,
        colorLabel: 'Fokus',
      ),
      PresetTaskLine(
        title: 'Pre-Workout + Get Ready for Gym',
        startMin: 540,
        endMin: 555,
        colorLabel: 'Routine',
      ),
      PresetTaskLine(
        title: "Let's Go GYM.",
        startMin: 555,
        endMin: 585,
        colorLabel: 'Routine',
      ),
      PresetTaskLine(
        title: 'Gym | Steps + Calisthenics Skill',
        startMin: 585,
        endMin: 735,
        colorLabel: 'Fokus',
      ),
      PresetTaskLine(
        title: "Let's Go Home.",
        startMin: 735,
        endMin: 780,
        colorLabel: 'Routine',
      ),
      PresetTaskLine(
        title: 'Shower + Post-Workout',
        startMin: 780,
        endMin: 825,
        colorLabel: 'Mahlzeit',
      ),
      PresetTaskLine(
        title: 'Bibel',
        startMin: 825,
        endMin: 885,
        colorLabel: 'Wichtig',
      ),
      PresetTaskLine(
        title: 'Trading | Cash Open',
        startMin: 885,
        endMin: 1080,
        colorLabel: 'Fokus',
      ),
      PresetTaskLine(
        title: 'Main Meal',
        startMin: 1080,
        endMin: 1140,
        colorLabel: 'Mahlzeit',
      ),
      PresetTaskLine(
        title: 'Deep Work 2',
        startMin: 1140,
        endMin: 1250,
        colorLabel: 'Fokus',
      ),
      PresetTaskLine(
        title: 'Creative Time',
        startMin: 1250,
        endMin: 1340,
        colorLabel: 'Fokus',
      ),
      PresetTaskLine(
        title: 'Evening Meal',
        startMin: 1340,
        endMin: 1360,
        colorLabel: 'Mahlzeit',
      ),
      PresetTaskLine(
        title: 'Abendroutine',
        startMin: 1360,
        endMin: 1395,
        colorLabel: 'Routine',
      ),
      PresetTaskLine(
        title: 'Go to bed',
        startMin: 1395,
        endMin: 330,
        colorLabel: 'Routine',
      ),
    ];

/// Vorlagen wie zuvor in `_buildPresetBlocks`; Überschreibungen kommen aus SharedPreferences.
List<PresetTaskLine> builtinPresetLinesFor(PlannerPresetType preset) {
  switch (preset) {
    case PlannerPresetType.hustle:
      // Tagesraster aus Nutzer-Export; Kategorien: Fokus=Gold, Mahlzeit=grüne Blöcke, …
      return [
        PresetTaskLine(
          title: 'Morgen Routine',
          startMin: 240,
          endMin: 300,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Deep Work',
          startMin: 300,
          endMin: 465,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Pre-Workout + Get Ready for Gym',
          startMin: 465,
          endMin: 485,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Lets go GYM',
          startMin: 485,
          endMin: 510,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Gym | Steps',
          startMin: 510,
          endMin: 660,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Lets Go Home',
          startMin: 660,
          endMin: 705,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Shower + Post-Workout',
          startMin: 705,
          endMin: 750,
          colorLabel: 'Mahlzeit',
        ),
        PresetTaskLine(
          title: 'Bible Study',
          startMin: 750,
          endMin: 810,
          colorLabel: 'Wichtig',
        ),
        PresetTaskLine(
          title: 'Deep Work 2',
          startMin: 810,
          endMin: 885,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Trading | Cash Open',
          startMin: 885,
          endMin: 1080,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Main Meal',
          startMin: 1080,
          endMin: 1140,
          colorLabel: 'Mahlzeit',
        ),
        PresetTaskLine(
          title: 'Creative Time',
          startMin: 1140,
          endMin: 1230,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Evening Meal',
          startMin: 1230,
          endMin: 1245,
          colorLabel: 'Mahlzeit',
        ),
        PresetTaskLine(
          title: 'Abendroutine',
          startMin: 1245,
          endMin: 1275,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Go to bed',
          startMin: 1275,
          endMin: 240,
          colorLabel: 'Routine',
        ),
      ];
    case PlannerPresetType.hustle530:
      return builtinHustle530Lines();
    case PlannerPresetType.monk:
      return [
        PresetTaskLine(
          title: 'Go to bed',
          startMin: 0,
          endMin: 390,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Morning · ruhig & fokussiert',
          startMin: 390,
          endMin: 450,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Deep Work #1',
          startMin: 450,
          endMin: 630,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Spaziergang · leicht',
          startMin: 630,
          endMin: 690,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Learning / Lesen (tief)',
          startMin: 690,
          endMin: 810,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Mittag · Pause & leicht',
          startMin: 810,
          endMin: 870,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Deep Work #2',
          startMin: 870,
          endMin: 1050,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Kitchen · minimal',
          startMin: 1050,
          endMin: 1110,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Monk · Lernen / Projekte',
          startMin: 1110,
          endMin: 1230,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Abendessen',
          startMin: 1230,
          endMin: 1290,
          colorLabel: 'Mahlzeit',
        ),
        PresetTaskLine(
          title: 'Lesen · Creative leicht',
          startMin: 1290,
          endMin: 1380,
          colorLabel: 'Wichtig',
        ),
        PresetTaskLine(
          title: 'Abendroutine · Stille',
          startMin: 1380,
          endMin: 1440,
          colorLabel: 'Routine',
        ),
      ];
    case PlannerPresetType.wochenende:
      return [
        PresetTaskLine(
          title: 'Go to bed',
          startMin: 0,
          endMin: 390,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Slow Morning',
          startMin: 390,
          endMin: 480,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Deep Work · freiwillig',
          startMin: 480,
          endMin: 630,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Get Ready + Pre-Workout',
          startMin: 630,
          endMin: 675,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Lets go GYM',
          startMin: 675,
          endMin: 690,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Gym / Steps',
          startMin: 690,
          endMin: 780,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Back Home',
          startMin: 780,
          endMin: 810,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Shower + Post Workout',
          startMin: 810,
          endMin: 855,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Deep Work 2 · freiwillig',
          startMin: 870,
          endMin: 1020,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Kitchen Prep + Track',
          startMin: 1020,
          endMin: 1080,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Freizeit · offen',
          startMin: 1080,
          endMin: 1230,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Abendessen',
          startMin: 1230,
          endMin: 1290,
          colorLabel: 'Mahlzeit',
        ),
        PresetTaskLine(
          title: 'Creative Time',
          startMin: 1290,
          endMin: 1380,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Abendroutine',
          startMin: 1380,
          endMin: 1440,
          colorLabel: 'Routine',
        ),
      ];
    case PlannerPresetType.urlaub:
      return [
        PresetTaskLine(
          title: 'Morgen Routine + Pre-Workout',
          startMin: 285,
          endMin: 375,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Get Ready for Gym',
          startMin: 375,
          endMin: 390,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: "Let's Go GYM.",
          startMin: 390,
          endMin: 420,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Gym | Steps + Calisthenics Skill (Deep Work)',
          startMin: 420,
          endMin: 510,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Cardio + Sauna and Shower',
          startMin: 510,
          endMin: 600,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Marktanalyse',
          startMin: 900,
          endMin: 930,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Mental vorbereiten und entspannen',
          startMin: 930,
          endMin: 960,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Trading | Cash Open',
          startMin: 960,
          endMin: 1080,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Go to bed',
          startMin: 1305,
          endMin: 285,
          colorLabel: 'Routine',
        ),
      ];
    case PlannerPresetType.alltag:
      return [
        PresetTaskLine(
          title: 'Morgen Routine + Pre-Workout',
          startMin: 285,
          endMin: 375,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Get Ready for Gym',
          startMin: 375,
          endMin: 390,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: "Let's Go GYM.",
          startMin: 390,
          endMin: 420,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Gym | Steps + Calisthenics Skill (Deep Work)',
          startMin: 420,
          endMin: 510,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Cardio + Sauna and Shower',
          startMin: 510,
          endMin: 600,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: "Let's Go Home.",
          startMin: 600,
          endMin: 630,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Post-Workout + Whatsapp und Anti Prog. Bearbeiten',
          startMin: 630,
          endMin: 690,
          colorLabel: 'Mahlzeit',
        ),
        PresetTaskLine(
          title: 'Bible Study 45min',
          startMin: 690,
          endMin: 750,
          colorLabel: 'Wichtig',
        ),
        PresetTaskLine(
          title: 'Deep Work 1',
          startMin: 750,
          endMin: 870,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Tee trinken und entspannen',
          startMin: 870,
          endMin: 900,
          colorLabel: 'Mahlzeit',
        ),
        PresetTaskLine(
          title: 'Marktanalyse',
          startMin: 900,
          endMin: 930,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Mental vorbereiten und entspannen',
          startMin: 930,
          endMin: 960,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Trading | Cash Open',
          startMin: 960,
          endMin: 1080,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Go to bed',
          startMin: 1305,
          endMin: 285,
          colorLabel: 'Routine',
        ),
      ];
    case PlannerPresetType.dayOff:
      return [
        PresetTaskLine(
          title: 'Morgen Routine + Pre-Workout',
          startMin: 285,
          endMin: 375,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Get Ready for Gym',
          startMin: 375,
          endMin: 390,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: "Let's Go GYM.",
          startMin: 390,
          endMin: 420,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Gym | Steps + Calisthenics Skill (Deep Work)',
          startMin: 420,
          endMin: 510,
          colorLabel: 'Fokus',
        ),
        PresetTaskLine(
          title: 'Cardio + Sauna and Shower',
          startMin: 510,
          endMin: 600,
          colorLabel: 'Routine',
        ),
        PresetTaskLine(
          title: 'Go to bed',
          startMin: 1305,
          endMin: 285,
          colorLabel: 'Routine',
        ),
      ];
  }
}

/// Preset-Farben inkl. Grün / Gold / Hell / Rot + neutrale Töne.
const List<Color> kCategoryColorSwatches = [
  Color(0xFF3D5A44),
  Color(0xFF4A6B52),
  Color(0xFF556F5C),
  Color(0xFF5A7A62),
  Color(0xFFC4A574),
  Color(0xFFB8956A),
  Color(0xFF9A7B52),
  Color(0xFF8A6A48),
  Color(0xFFADA8A2),
  Color(0xFFC4C1BC),
  Color(0xFF9C9690),
  Color(0xFF8A8580),
  Color(0xFF9A4E4E),
  Color(0xFF8B4444),
  Color(0xFF7A3D3D),
  Color(0xFFAA6A5A),
  Color(0xFF2A2420),
  Color(0xFF3A322C),
  Color(0xFF4A4038),
  Color(0xFF5A5048),
  Color(0xFF5A5650),
  Color(0xFF6A7583),
  Color(0xFF6B7280),
  Color(0xFF4A5560),
];

IconData _categoryIcon(String label) {
  switch (label) {
    case 'Mahlzeit':
      return Icons.restaurant_outlined;
    case 'Fokus':
      return Icons.task_alt_outlined;
    case 'Routine':
      return Icons.calendar_view_day_outlined;
    case 'Wichtig':
      return Icons.flag_outlined;
    default:
      return Icons.label_outline;
  }
}

final Map<String, String> kColorMeaning = {
  'Mahlzeit': 'Essen & Mahlzeiten — standardmäßig grün',
  'Fokus': 'Was zu tun ist, Arbeit, eingetragene Aufgaben — standardmäßig gold',
  'Routine': 'Struktur im Tag (Schlaf, Sport, Pausen …) — standardmäßig hell',
  'Wichtig':
      'Hebt hervor, was du noch besonders prüfen willst — standardmäßig rot',
};

String _colorToHexArgb(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0');

/// Nur RGB mit `#` (kein Alpha) — für die Farbwahl-Eingabe.
String _colorToRgbHex6(Color c) {
  final rgb = c.toARGB32() & 0x00ffffff;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

Color? _tryParseColorHexLoose(String raw) {
  var h = raw.trim().replaceAll('#', '');
  if (h.length == 6) h = 'ff$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(v);
}

Color _colorFromHexString(String raw) {
  var h = raw.trim().replaceAll('#', '');
  if (h.length == 6) h = 'ff$h';
  if (h.length != 8) return const Color(0xFF6B7280);
  return Color(int.parse(h, radix: 16));
}

bool _isBuiltinCategorySwatchColor(Color c) {
  final v = c.toARGB32();
  return kCategoryColorSwatches.any((x) => x.toARGB32() == v);
}

/// Gruppierte Material-Symbole für den Planer (Apps/Arbeit/Sport usw.).
final List<MapEntry<String, List<IconData>>> kPlannerIconCatalog = [
  MapEntry('Arbeit & Fokus', [
    Icons.work_outline,
    Icons.business_center_outlined,
    Icons.laptop_mac,
    Icons.task_alt_outlined,
    Icons.timer_outlined,
    Icons.event_note_outlined,
    Icons.article_outlined,
    Icons.edit_document,
    Icons.developer_mode_outlined,
  ]),
  MapEntry('Kommunikation', [
    Icons.mail_outline,
    Icons.chat_bubble_outline,
    Icons.phone_in_talk_outlined,
    Icons.videocam_outlined,
    Icons.forum_outlined,
    Icons.groups_outlined,
    Icons.handshake_outlined,
    Icons.record_voice_over_outlined,
  ]),
  MapEntry('Finanzen & Zahlen', [
    Icons.account_balance_outlined,
    Icons.attach_money,
    Icons.currency_exchange,
    Icons.insert_chart_outlined,
    Icons.calculate_outlined,
    Icons.receipt_long_outlined,
    Icons.savings_outlined,
    Icons.shopping_cart_outlined,
  ]),
  MapEntry('Sport & Bewegung', [
    Icons.fitness_center_outlined,
    Icons.directions_run_outlined,
    Icons.directions_bike_outlined,
    Icons.pool_outlined,
    Icons.sports_tennis_outlined,
    Icons.hiking_outlined,
    Icons.self_improvement_outlined,
    Icons.sports_gymnastics_outlined,
  ]),
  MapEntry('Körper & Gesundheit', [
    Icons.local_hospital_outlined,
    Icons.medical_services_outlined,
    Icons.monitor_heart_outlined,
    Icons.bloodtype_outlined,
    Icons.healing_outlined,
    Icons.restaurant_outlined,
    Icons.water_drop_outlined,
    Icons.bedtime_outlined,
  ]),
  MapEntry('Alltag & Haushalt', [
    Icons.home_outlined,
    Icons.cleaning_services_outlined,
    Icons.local_grocery_store_outlined,
    Icons.child_friendly_outlined,
    Icons.pets_outlined,
    Icons.directions_car_outlined,
    Icons.train_outlined,
    Icons.place_outlined,
  ]),
  MapEntry('Kreativ & Medien', [
    Icons.palette_outlined,
    Icons.music_note_outlined,
    Icons.movie_outlined,
    Icons.photo_camera_outlined,
    Icons.brush_outlined,
    Icons.auto_stories_outlined,
    Icons.podcasts_outlined,
    Icons.smart_display_outlined,
  ]),
  MapEntry('Lernen & Wachstum', [
    Icons.school_outlined,
    Icons.menu_book_outlined,
    Icons.science_outlined,
    Icons.psychology_outlined,
    Icons.translate,
    Icons.computer_outlined,
    Icons.web_outlined,
    Icons.code,
  ]),
  MapEntry('Soziales & Freizeit', [
    Icons.coffee_outlined,
    Icons.restaurant_menu,
    Icons.nightlife,
    Icons.flight_outlined,
    Icons.festival,
    Icons.spa_outlined,
    Icons.park_outlined,
    Icons.cake_outlined,
  ]),
  MapEntry('Produktivität & Digital', [
    Icons.cloud_outlined,
    Icons.storage_outlined,
    Icons.security,
    Icons.bug_report_outlined,
    Icons.construction_outlined,
    Icons.wifi,
    Icons.bolt,
    Icons.qr_code_2,
  ]),
  MapEntry('Allgemein', [
    Icons.star_outline,
    Icons.favorite_outline,
    Icons.flag_outlined,
    Icons.label_outline,
    Icons.info_outlined,
    Icons.check_circle_outline,
    Icons.warning_amber_outlined,
    Icons.notifications_none_outlined,
  ]),
];

IconData _materialIcon(int codePoint) =>
    IconData(codePoint, fontFamily: 'MaterialIcons');

IconData _resolveBlockIcon(TimeBlock b) {
  final c = b.customIconCodePoint;
  if (c != null) return _materialIcon(c);
  return _categoryIcon(b.colorLabel);
}

IconData _draftBlockIcon(String colorLabel, int? customCodePoint) {
  if (customCodePoint != null) return _materialIcon(customCodePoint);
  return _categoryIcon(colorLabel);
}

String _weekdayShortMaskLabel(int mask) {
  if (mask == 0) return 'Mo–So';
  const names = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  final parts = <String>[];
  for (var i = 0; i < 7; i++) {
    if ((mask & (1 << i)) != 0) parts.add(names[i]);
  }
  return parts.isEmpty ? '—' : parts.join(', ');
}

/// Für Timeline-Zeile unter dem Titel.
String _blockRecurrenceSummary(TimeBlock b) {
  switch (b.recurrence) {
    case BlockRecurrence.none:
      return 'Einmalig';
    case BlockRecurrence.daily:
      return 'Täglich';
    case BlockRecurrence.weekly:
      return 'Wöchentlich · ${_weekdayShortMaskLabel(b.recurrenceWeekdayMask)}';
    case BlockRecurrence.monthly:
      return 'Monatlich · Tag ${b.recurrenceMonthDay.clamp(1, 28)}';
  }
}

String _draftRecurrenceSummary({
  required BlockRecurrence recurrence,
  required int weekdayMask,
  required int monthDay,
}) {
  switch (recurrence) {
    case BlockRecurrence.none:
      return 'Einmalig';
    case BlockRecurrence.daily:
      return 'Täglich';
    case BlockRecurrence.weekly:
      return 'Wöchentlich · ${_weekdayShortMaskLabel(weekdayMask)}';
    case BlockRecurrence.monthly:
      return 'Monatlich · Tag ${monthDay.clamp(1, 28)}';
  }
}

bool _weekdayMatchesPreset(DateTime d, int mask) {
  if (mask == 0) return true;
  final i = d.weekday - 1;
  return (mask & (1 << i)) != 0;
}

/// Titel wie „Freizeit · offen“ / „Freizeit . offen“: bewusst leere Freizeit — stark abgegraut, ohne Farb‑Glow.
bool _isFreizeitOffenPlaceholderTitle(String raw) {
  var s = raw.toLowerCase().trim();
  s = s.replaceAll('·', ' ').replaceAll('•', ' ').replaceAll('∙', ' ');
  s = s.replaceAll(RegExp(r'[.]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s.contains('freizeit') && s.contains('offen');
}

Iterable<(int, int)> _linearSegments(TimeBlock b) sync* {
  if (b.allDay) {
    yield (0, 1440);
    return;
  }
  if (b.startMin < b.endMin) {
    yield (b.startMin, b.endMin);
    return;
  }
  if (b.startMin > b.endMin) {
    yield (b.startMin, 1440);
    yield (0, b.endMin);
  }
}

bool _blocksOverlap(TimeBlock a, TimeBlock b) {
  for (final sa in _linearSegments(a)) {
    for (final sb in _linearSegments(b)) {
      if (sa.$1 < sb.$2 && sb.$1 < sa.$2) return true;
    }
  }
  return false;
}

const int _kMaxUndoSteps = 30;

/// Pro Tag: welches Preset dem Plan zugrunde liegt, oder angepasster **Individuell**‑Modus.
const String _kIndividualDayPresetKey = '__individual__';
const String _kCreatePresetMenuValue = '__create_preset__';
const String _kHauptplanMenuValue = '__hauptplan__';

class _PlannerUndoSnapshot {
  const _PlannerUndoSnapshot({
    required this.days,
    required this.backlog,
    required this.selectedBlockIds,
    required this.expandedBlockIds,
    required this.presetWindows,
    required this.activePresetKey,
    required this.selectedDate,
  });

  final Map<DateTime, List<TimeBlock>> days;
  final List<TimeBlock> backlog;
  final Set<String> selectedBlockIds;
  final Set<String> expandedBlockIds;
  final List<PresetWindow> presetWindows;
  final String activePresetKey;
  final DateTime selectedDate;
}

/// Fortschritt einer geplanten Fokus/Pause-Session innerhalb eines Blocks (nur RAM).
class _SessionLiveProgress {
  _SessionLiveProgress(this.segmentIndex, this.phaseStartedAt);

  int segmentIndex;
  DateTime phaseStartedAt;
}

class _PlannerHomeState extends State<PlannerHome> with WidgetsBindingObserver {
  DateTime _selectedDate = _onlyDay(DateTime.now());
  String _activePresetKey = PlannerPresetType.hustle.name;
  final Map<DateTime, List<TimeBlock>> _days = {};
  final List<TimeBlock> _backlog = [];
  final List<PresetWindow> _presetWindows = [];
  final Set<String> _selectedBlockIds = {};
  bool _flexMode = false;
  /// Während Flex-Ziehens: zusammenhängender Chunk — Liste zeigt Geister, der Proxy den ganzen Stapel.
  ({int start, int end})? _flexReorderGhostRange;
  final Set<String> _expandedBlockIds = {};
  final Map<String, _SessionLiveProgress> _sessionLiveByKey = {};
  int _idCounter = 0;

  /// Laufende Kategoriefarben (inkl. Nutzeranpassung, s. SharedPreferences).
  Map<String, Color> _categoryColors = Map<String, Color>.from(
    kDefaultCategoryColors,
  );
  List<String> _categoryOrder = List<String>.from(
    kCanonicalDefaultCategoryOrder,
  );
  final List<Color> _customStripeSwatches = [];
  final List<Color> _customCategorySwatches = [];

  /// Nutzerdefinierte Preset-Raster (pro [PlannerPresetType]); fehlender Eintrag = eingebaute Vorlage.
  final Map<PlannerPresetType, List<PresetTaskLine>> _presetTaskOverrides = {};

  /// Eigene Preset-Tage (Name + Raster-Zeilen), persistent.
  final List<UserPresetDay> _userPresetDays = [];

  /// Eigene Anzeigenamen für eingebaute Presets (leer = Standard).
  final Map<PlannerPresetType, String> _builtinPresetDisplayOverrides = {};

  /// Pro Kalendertag: Preset‑Schlüssel (`hustle`, `u:id`, …) oder [_kIndividualDayPresetKey].
  final Map<DateTime, String> _dayPlanPresetKind = {};

  /// Schnellvorlagen für Block-Unteraufgaben (global, persistent).
  List<String> _subtaskQuickPresets = List<String>.from(
    kDefaultSubtaskQuickPresets,
  );

  final List<_PlannerUndoSnapshot> _undoStack = [];

  /// Freitext pro Kalendertag (unabhängig von den Blöcken).
  final Map<DateTime, String> _freeformNotesByDay = {};
  final TextEditingController _freeformCtrl = TextEditingController();
  Timer? _freeformSaveDebounce;
  Timer? _dayPlansSaveDebounce;
  Timer? _reminderTicker;

  /// Löst einmal pro Minute [setState] aus, damit „noch …“ in Block-Karten aktuell bleibt.
  Timer? _minutePulseTimer;

  PlannerReminderPrefs _reminderPrefs = PlannerReminderPrefs.defaults();

  bool _deepWorkTodoEnabled = true;
  final List<DeepWorkTodoItem> _deepWorkTodos = [];

  /// Projekt-Rotation für „Projekt-Session“-Blöcke.
  ProjectRotation _projectRotation = ProjectRotation();

  /// Raster-Ansicht (Zeitraster) statt Liste.
  bool _dayGridView = true;
  final ScrollController _gridScroll = ScrollController();
  DateTime? _gridScrolledForDay;
  bool _showFreeTimeLanes = true;

  Map<DateTime, List<TimeBlock>> _deepCopyDays() {
    final m = <DateTime, List<TimeBlock>>{};
    for (final e in _days.entries) {
      m[e.key] = e.value.map((b) => b.copyWith()).toList();
    }
    return m;
  }

  void _recordUndoSnapshot({bool markSelectedDayAsIndividual = true}) {
    if (markSelectedDayAsIndividual) {
      _dayPlanPresetKind[_onlyDay(_selectedDate)] = _kIndividualDayPresetKey;
    }
    _undoStack.add(
      _PlannerUndoSnapshot(
        days: _deepCopyDays(),
        backlog: _backlog.map((b) => b.copyWith()).toList(),
        selectedBlockIds: Set<String>.from(_selectedBlockIds),
        expandedBlockIds: Set<String>.from(_expandedBlockIds),
        presetWindows: List<PresetWindow>.from(_presetWindows),
        activePresetKey: _activePresetKey,
        selectedDate: _selectedDate,
      ),
    );
    if (_undoStack.length > _kMaxUndoSteps) {
      _undoStack.removeAt(0);
    }
  }

  void _undoLastChange({bool showSnack = true}) {
    if (_undoStack.isEmpty) return;
    final snap = _undoStack.removeLast();
    setState(() {
      _days
        ..clear()
        ..addAll(
          snap.days.map(
            (k, v) => MapEntry(k, v.map((b) => b.copyWith()).toList()),
          ),
        );
      _backlog
        ..clear()
        ..addAll(snap.backlog.map((b) => b.copyWith()));
      _selectedBlockIds
        ..clear()
        ..addAll(snap.selectedBlockIds);
      _expandedBlockIds
        ..clear()
        ..addAll(snap.expandedBlockIds);
      _presetWindows
        ..clear()
        ..addAll(snap.presetWindows);
      _activePresetKey = snap.activePresetKey;
      _selectedDate = snap.selectedDate;
    });
    _schedulePersistDayPlans();
    _loadFreeformForCurrentDay();
    if (!mounted || !showSnack) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Letzter Schritt zurückgenommen.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Kurzes Feedback mit [SnackBar]-Aktion – macht denselben Rückgang wie das Undo-Symbol oben (ein Schritt aus dem Undo-Stapel).
  void _offerUndoSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () {
            if (_undoStack.isEmpty) return;
            _undoLastChange(showSnack: false);
          },
        ),
      ),
    );
  }

  Color _stripeColor(String label) =>
      _categoryColors[label] ?? const Color(0xFF6B7280);

  Color _stripeForBlock(TimeBlock b) {
    final h = b.customStripeHex?.trim();
    if (h != null && h.isNotEmpty) {
      return _colorFromHexString(h);
    }
    return _stripeColor(b.colorLabel);
  }

  bool _useMealVisualFor(TimeBlock b) {
    final h = b.customStripeHex?.trim();
    if (h != null && h.isNotEmpty) return false;
    return _categoryUsesMealVisual(b.colorLabel);
  }

  bool _draftUseMealVisual(String colorLabel, String? customStripeHex) {
    final h = customStripeHex?.trim();
    if (h != null && h.isNotEmpty) return false;
    return _categoryUsesMealVisual(colorLabel);
  }

  bool _isBuiltinStripeSwatch(Color c) => _isBuiltinCategorySwatchColor(c);

  List<Color> _allCategoryPresetSwatches() {
    final out = <Color>[...kCategoryColorSwatches];
    for (final c in _customCategorySwatches) {
      if (!out.any((x) => x.toARGB32() == c.toARGB32())) out.add(c);
    }
    return out;
  }

  List<Color> _allStripeSwatches() {
    final out = <Color>[...kCategoryColorSwatches];
    for (final c in _customStripeSwatches) {
      final exists = out.any((x) => x.toARGB32() == c.toARGB32());
      if (!exists) out.add(c);
    }
    return out;
  }

  Future<void> _saveCustomStripeSwatches() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _customStripeSwatches.map(_colorToHexArgb).toList();
    await prefs.setString(_kCustomStripeSwatchesPrefKey, jsonEncode(encoded));
    solNotifyPlannerDiskDataChanged();
  }

  Future<void> _loadCustomStripeSwatches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCustomStripeSwatchesPrefKey);
      if (raw == null || raw.isEmpty) return;
      final arr = jsonDecode(raw);
      if (arr is! List) return;
      final loaded = <Color>[];
      for (final v in arr) {
        if (v is! String) continue;
        final c = _colorFromHexString(v);
        final exists = loaded.any((x) => x.toARGB32() == c.toARGB32());
        if (!exists && !_isBuiltinStripeSwatch(c)) loaded.add(c);
      }
      if (!mounted) return;
      setState(() {
        _customStripeSwatches
          ..clear()
          ..addAll(loaded);
      });
    } catch (_) {}
  }

  Future<void> _saveCustomCategorySwatches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCustomCategorySwatchesPrefKey,
        jsonEncode(_customCategorySwatches.map(_colorToHexArgb).toList()),
      );
      solNotifyPlannerDiskDataChanged();
    } catch (_) {}
  }

  Future<void> _loadCustomCategorySwatches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCustomCategorySwatchesPrefKey);
      if (raw == null || raw.isEmpty) return;
      final arr = jsonDecode(raw);
      if (arr is! List) return;
      final loaded = <Color>[];
      for (final v in arr) {
        if (v is! String) continue;
        final c = _colorFromHexString(v);
        if (!_isBuiltinCategorySwatchColor(c) &&
            !loaded.any((x) => x.toARGB32() == c.toARGB32())) {
          loaded.add(c);
        }
      }
      if (!mounted) return;
      setState(() {
        _customCategorySwatches
          ..clear()
          ..addAll(loaded);
      });
    } catch (_) {}
  }

  Future<Color?> _pickStripeColorFromFullPalette(Color initial) =>
      _pickCustomColorSheet(initial);

  /// Farbfläche (S/V) + vertikaler Regenbogen (Farbton) + Hex-Eingabe.
  Future<Color?> _pickCustomColorSheet(Color initial) async {
    final initHsv = HSVColor.fromColor(initial);
    var hue = initHsv.hue;
    var saturation = initHsv.saturation;
    var value = initHsv.value;

    Color compose() => HSVColor.fromAHSV(
      1.0,
      hue % 360,
      saturation.clamp(0.0, 1.0),
      value.clamp(0.0, 1.0),
    ).toColor();

    final hexCtrl = TextEditingController(text: _colorToRgbHex6(compose()));

    final sheetDrag = _ColorSheetDragAnchors();

    final result = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final p = sheetCtx.palette;
        final padBottom = MediaQuery.of(sheetCtx).viewInsets.bottom;
        final mh = MediaQuery.of(sheetCtx).size.height * 0.78;

        return Padding(
          padding: EdgeInsets.only(bottom: padBottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: StatefulBuilder(
                builder: (ctx, setSheet) {
                  Color pureHue() =>
                      HSVColor.fromAHSV(1.0, hue % 360, 1.0, 1.0).toColor();

                  void syncHexFromWheel() {
                    hexCtrl.text = _colorToRgbHex6(compose());
                  }

                  bool applyHexDraft() {
                    final parsed = _tryParseColorHexLoose(hexCtrl.text);
                    if (parsed == null) return false;
                    final nh = HSVColor.fromColor(parsed);
                    hue = nh.hue;
                    saturation = nh.saturation;
                    value = nh.value;
                    hexCtrl.text = _colorToRgbHex6(parsed);
                    setSheet(() {});
                    return true;
                  }

                  return SizedBox(
                    height: mh,
                    child: Material(
                      color: p.surface,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 10),
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: p.hairline,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Farbe wählen',
                                    style: Theme.of(sheetCtx)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: p.text,
                                        ),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Aktuelle Farbe',
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: compose(),
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: p.hairline,
                                        width: 1.5,
                                      ),
                                      boxShadow: p.cardShadows,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: hexCtrl,
                                    keyboardType: TextInputType.visiblePassword,
                                    style: Theme.of(sheetCtx)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w600,
                                          color: p.text,
                                        ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      filled: true,
                                      fillColor: p.bg.withValues(alpha: 0.4),
                                      labelText: 'Hex',
                                      hintText: '#aabbcc',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: p.hairline,
                                        ),
                                      ),
                                    ),
                                    onSubmitted: (_) {
                                      applyHexDraft();
                                    },
                                    onEditingComplete: applyHexDraft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, lc) {
                                final maxW = lc.maxWidth;
                                const hueW = 32.0;
                                const gutter = 12.0;
                                final avail = (maxW - 16 * 2 - gutter - hueW)
                                    .clamp(120.0, 400.0);
                                final side = min(lc.maxHeight - 28, avail);

                                return SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    8,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Listener(
                                        behavior: HitTestBehavior.opaque,
                                        onPointerDown: (e) {
                                          final w = side.clamp(
                                            1e-6,
                                            double.infinity,
                                          );
                                          sheetDrag.svPressed = true;
                                          sheetDrag.svOrigin = e.localPosition;
                                          sheetDrag.satAnchor =
                                              (e.localPosition.dx / w).clamp(
                                                0.0,
                                                1.0,
                                              );
                                          sheetDrag.valAnchor =
                                              (1 - e.localPosition.dy / w)
                                                  .clamp(0.0, 1.0);
                                          saturation = sheetDrag.satAnchor;
                                          value = sheetDrag.valAnchor;
                                          syncHexFromWheel();
                                          setSheet(() {});
                                        },
                                        onPointerMove: (e) {
                                          if (!sheetDrag.svPressed) return;
                                          final w = side.clamp(
                                            1e-6,
                                            double.infinity,
                                          );
                                          final delta =
                                              e.localPosition -
                                              sheetDrag.svOrigin;
                                          saturation =
                                              (sheetDrag.satAnchor +
                                                      delta.dx /
                                                          w *
                                                          _kColorPickerDragScale)
                                                  .clamp(0.0, 1.0);
                                          value =
                                              (sheetDrag.valAnchor -
                                                      delta.dy /
                                                          w *
                                                          _kColorPickerDragScale)
                                                  .clamp(0.0, 1.0);
                                          syncHexFromWheel();
                                          setSheet(() {});
                                        },
                                        onPointerUp: (_) {
                                          sheetDrag.svPressed = false;
                                        },
                                        onPointerCancel: (_) {
                                          sheetDrag.svPressed = false;
                                        },
                                        child: SizedBox(
                                          width: side,
                                          height: side,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                child: SizedBox.expand(
                                                  child: Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      DecoratedBox(
                                                        decoration: BoxDecoration(
                                                          gradient:
                                                              LinearGradient(
                                                                colors: [
                                                                  Colors.white,
                                                                  pureHue(),
                                                                ],
                                                                begin: Alignment
                                                                    .centerLeft,
                                                                end: Alignment
                                                                    .centerRight,
                                                              ),
                                                        ),
                                                      ),
                                                      DecoratedBox(
                                                        decoration: BoxDecoration(
                                                          gradient: LinearGradient(
                                                            colors: [
                                                              Colors.black
                                                                  .withValues(
                                                                    alpha: 0,
                                                                  ),
                                                              Colors.black,
                                                            ],
                                                            begin: Alignment
                                                                .topCenter,
                                                            end: Alignment
                                                                .bottomCenter,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                left: saturation * side - 11,
                                                top: (1 - value) * side - 11,
                                                child: IgnorePointer(
                                                  child: Container(
                                                    width: 22,
                                                    height: 22,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 2.5,
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                                alpha: 0.35,
                                                              ),
                                                          blurRadius: 6,
                                                          offset: const Offset(
                                                            0,
                                                            2,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: gutter),
                                      Listener(
                                        behavior: HitTestBehavior.opaque,
                                        onPointerDown: (e) {
                                          final hTrack = side.clamp(
                                            1e-6,
                                            double.infinity,
                                          );
                                          sheetDrag.huePressed = true;
                                          sheetDrag.hueYAnchor =
                                              e.localPosition.dy;
                                          sheetDrag.hueAnchorDegrees =
                                              (e.localPosition.dy /
                                                      hTrack *
                                                      360)
                                                  .clamp(0.0, 360.0);
                                          hue =
                                              sheetDrag.hueAnchorDegrees % 360;
                                          syncHexFromWheel();
                                          setSheet(() {});
                                        },
                                        onPointerMove: (e) {
                                          if (!sheetDrag.huePressed) return;
                                          final hTrack = side.clamp(
                                            1e-6,
                                            double.infinity,
                                          );
                                          final dy =
                                              e.localPosition.dy -
                                              sheetDrag.hueYAnchor;
                                          var nh =
                                              sheetDrag.hueAnchorDegrees +
                                              dy /
                                                  hTrack *
                                                  360 *
                                                  _kHuePickerDragScale;
                                          nh %= 360;
                                          if (nh < 0) nh += 360;
                                          hue = nh;
                                          syncHexFromWheel();
                                          setSheet(() {});
                                        },
                                        onPointerUp: (_) {
                                          sheetDrag.huePressed = false;
                                        },
                                        onPointerCancel: (_) {
                                          sheetDrag.huePressed = false;
                                        },
                                        child: SizedBox(
                                          width: hueW,
                                          height: side,
                                          child: Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: SizedBox.expand(
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin:
                                                            Alignment.topCenter,
                                                        end: Alignment
                                                            .bottomCenter,
                                                        colors: const [
                                                          Color(0xFFFF0000),
                                                          Color(0xFFFF00FF),
                                                          Color(0xFF8800FF),
                                                          Color(0xFF0000FF),
                                                          Color(0xFF00FFFF),
                                                          Color(0xFF00FF00),
                                                          Color(0xFFFFFF00),
                                                          Color(0xFFFF0000),
                                                        ],
                                                        stops: const [
                                                          0.0,
                                                          0.167,
                                                          0.25,
                                                          0.333,
                                                          0.5,
                                                          0.667,
                                                          0.833,
                                                          1.0,
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                left: -2,
                                                right: -2,
                                                top: (hue / 360 * side).clamp(
                                                  0.0,
                                                  side - 6,
                                                ),
                                                child: IgnorePointer(
                                                  child: Container(
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            99,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 2,
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                                alpha: 0.35,
                                                              ),
                                                          blurRadius: 4,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              6,
                              16,
                              14 + MediaQuery.of(sheetCtx).padding.bottom,
                            ),
                            child: Row(
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(sheetCtx),
                                  child: Text(
                                    'Abbrechen',
                                    style: TextStyle(
                                      color: p.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    foregroundColor: p.bg,
                                    backgroundColor: p.text,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: () =>
                                      Navigator.pop(sheetCtx, compose()),
                                  child: const Text('Übernehmen'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
    hexCtrl.dispose();
    return result;
  }

  List<PlannerReminderSlice> _reminderSlicesForToday() {
    final now = DateTime.now();
    final d = _onlyDay(now);
    final list = _days[d];
    if (list == null || list.isEmpty) {
      return const [];
    }
    return [
      for (final b in list)
        PlannerReminderSlice(
          id: b.id,
          title: b.title.trim().isEmpty ? 'Block' : b.title,
          startMin: b.startMin,
          endMin: b.endMin,
          allDay: b.allDay,
          muteReminders: b.muteReminders,
          shouldRemind:
              !b.completed && !b.allDay && b.isLinearSlot && !b.isOvernightSlot,
        ),
    ];
  }

  Future<void> _syncReminders() async {
    if (!mounted) return;
    final slices = _reminderSlicesForToday();
    final now = DateTime.now();
    try {
      tickWebOrForegroundReminders(slices, now, _reminderPrefs);
      await rescheduleTodayReminders(slices, now, _reminderPrefs);
    } catch (_) {
      // Reminder-/Notification-Fehler sollen UI nicht lahmlegen.
    }
  }

  Future<void> _loadReminderPrefs() async {
    final p = await loadPlannerReminderPrefs();
    if (!mounted) return;
    setState(() => _reminderPrefs = p);
    unawaited(_syncReminders());
  }

  Future<void> _loadShowFreeTimeLanes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final on = prefs.getBool(_kShowFreeTimeLanesPrefKey) ?? true;
      if (!mounted) return;
      setState(() => _showFreeTimeLanes = on);
    } catch (_) {}
  }

  Future<void> _setShowFreeTimeLanes(bool on) async {
    setState(() => _showFreeTimeLanes = on);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShowFreeTimeLanesPrefKey, on);
    } catch (_) {}
  }

  bool _isDeepWorkSessionBlock(TimeBlock b) {
    if (b.allDay || b.completed) return false;
    final title = b.title.toLowerCase();
    return title.contains('deep work') || title.contains('deepwork');
  }

  /// Offene To-dos hängen immer an der aktuellen bzw. nächsten Deep-Work-Session
  /// des betrachteten Tags — nicht an jeder Deep-Work-Karte gleichzeitig.
  bool _blockShowsRolledDeepWorkTodos(TimeBlock b) {
    if (!_deepWorkTodoEnabled) return false;
    final host = _activeDeepWorkSessionNow();
    return host != null && host.id == b.id;
  }

  TimeBlock? _activeDeepWorkSessionNow() {
    final now = DateTime.now();
    if (_onlyDay(_selectedDate) != _onlyDay(now)) {
      return _nextOpenDeepWorkSession();
    }
    final nowMin = now.hour * 60 + now.minute;
    final day = _getBlocksForDay(_selectedDate);
    for (final b in day) {
      if (!_isDeepWorkSessionBlock(b) || !b.isLinearSlot) continue;
      if (nowMin >= b.startMin && nowMin < b.endMin) return b;
    }
    return _nextOpenDeepWorkSession();
  }

  TimeBlock? _nextOpenDeepWorkSession() {
    final now = DateTime.now();
    final viewingToday = _onlyDay(_selectedDate) == _onlyDay(now);
    final nowMin = now.hour * 60 + now.minute;
    final day = _getBlocksForDay(_selectedDate);
    TimeBlock? fallback;
    for (final b in day) {
      if (!_isDeepWorkSessionBlock(b) || !b.isLinearSlot) continue;
      fallback ??= b;
      if (!viewingToday || b.endMin > nowMin) return b;
    }
    if (fallback != null) return fallback;

    // Kein Deep Work mehr heute: nächster Kalendertag mit Deep-Work-Slot.
    for (var i = 1; i <= 14; i++) {
      final d = _onlyDay(now.add(Duration(days: i)));
      _ensureDayExists(d);
      final later = _getBlocksForDay(d);
      for (final b in later) {
        if (_isDeepWorkSessionBlock(b) && b.isLinearSlot) return b;
      }
    }
    return null;
  }

  List<DeepWorkTodoItem> _openDeepWorkTodos() =>
      _deepWorkTodos.where((t) => !t.done && t.title.trim().isNotEmpty).toList();

  Future<void> _loadDeepWorkTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_kDeepWorkTodoEnabledPrefKey) ?? true;
      final raw = prefs.getString(_kDeepWorkTodoItemsPrefKey);
      final items = <DeepWorkTodoItem>[];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) {
              final item = DeepWorkTodoItem.fromJson(e);
              if (item.id.isEmpty || item.title.isEmpty) continue;
              items.add(item);
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _deepWorkTodoEnabled = enabled;
        _deepWorkTodos
          ..clear()
          ..addAll(items);
      });
      _expandHostDeepWorkIfNeeded();
    } catch (_) {}
  }

  Future<void> _saveDeepWorkTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDeepWorkTodoEnabledPrefKey, _deepWorkTodoEnabled);
      await prefs.setString(
        _kDeepWorkTodoItemsPrefKey,
        jsonEncode(_deepWorkTodos.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _setDeepWorkTodoEnabled(bool on) async {
    setState(() => _deepWorkTodoEnabled = on);
    await _saveDeepWorkTodos();
    if (on) _expandHostDeepWorkIfNeeded();
  }

  void _expandHostDeepWorkIfNeeded() {
    if (!_deepWorkTodoEnabled) return;
    if (_openDeepWorkTodos().isEmpty) return;
    final host = _activeDeepWorkSessionNow();
    if (host == null) return;
    if (_expandedBlockIds.contains(host.id)) return;
    setState(() => _expandedBlockIds.add(host.id));
  }

  Future<void> _addDeepWorkTodo(String rawTitle) async {
    final title = rawTitle.trim();
    if (title.isEmpty) return;
    setState(() {
      _deepWorkTodos.add(DeepWorkTodoItem(id: _nextId(), title: title));
    });
    await _saveDeepWorkTodos();
    _expandHostDeepWorkIfNeeded();
  }

  Future<void> _toggleDeepWorkTodo(DeepWorkTodoItem item, bool done) async {
    setState(() => item.done = done);
    await _saveDeepWorkTodos();
  }

  Future<void> _removeDeepWorkTodo(DeepWorkTodoItem item) async {
    setState(() => _deepWorkTodos.removeWhere((t) => t.id == item.id));
    await _saveDeepWorkTodos();
  }

  Future<void> _openDeepWorkTodoSheet() async {
    final addCtrl = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          final p = sheetCtx.palette;
          return StatefulBuilder(
            builder: (context, setLocal) {
              void refresh() => setLocal(() {});
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  child: Material(
                    color: p.surface,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                                  color: p.hairline,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  Icons.checklist_rounded,
                                  color: p.text,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'To do List',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Offene Punkte stehen in der aktuellen Deep-Work-Session. '
                              'Was nicht abgehakt ist, wandert automatisch in die nächste.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: p.muted,
                                    height: 1.35,
                                  ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('In Deep Work anzeigen'),
                              subtitle: const Text(
                                'Aus: Liste bleibt, hängt aber nicht mehr in Deep-Work-Blöcken.',
                              ),
                              value: _deepWorkTodoEnabled,
                              onChanged: (v) async {
                                await _setDeepWorkTodoEnabled(v);
                                refresh();
                              },
                            ),
                            if (_deepWorkTodos.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                child: Text(
                                  'Noch keine Aufgaben. Füge unten den ersten Eintrag hinzu.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: p.muted),
                                ),
                              )
                            else
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 320,
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _deepWorkTodos.length,
                                  itemBuilder: (c, i) {
                                    final item = _deepWorkTodos[i];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Checkbox(
                                        value: item.done,
                                        onChanged: (v) async {
                                          await _toggleDeepWorkTodo(
                                            item,
                                            v ?? false,
                                          );
                                          refresh();
                                        },
                                      ),
                                      title: Text(
                                        item.title,
                                        style: TextStyle(
                                          color: p.text,
                                          decoration: item.done
                                              ? TextDecoration.lineThrough
                                              : null,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        tooltip: 'Entfernen',
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: p.muted,
                                        ),
                                        onPressed: () async {
                                          await _removeDeepWorkTodo(item);
                                          refresh();
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: addCtrl,
                                    textInputAction: TextInputAction.done,
                                    decoration: InputDecoration(
                                      hintText: 'Neue Aufgabe …',
                                      hintStyle: TextStyle(color: p.muted),
                                      filled: true,
                                      fillColor: p.bg.withValues(alpha: 0.35),
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: p.hairline,
                                        ),
                                      ),
                                    ),
                                    onSubmitted: (v) async {
                                      await _addDeepWorkTodo(v);
                                      addCtrl.clear();
                                      refresh();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: () async {
                                    await _addDeepWorkTodo(addCtrl.text);
                                    addCtrl.clear();
                                    refresh();
                                  },
                                  child: const Icon(Icons.add_rounded),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      addCtrl.dispose();
    }
  }

  /// „Mehr“-Menü oben rechts: alle Werkzeuge als beschriftete Liste.
  Future<void> _openMoreActionsSheet() async {
    final p = context.palette;
    final items = <({IconData icon, String label, String? sub, VoidCallback onTap})>[
      (
        icon: Icons.autorenew_rounded,
        label: 'Projekt-Rotation',
        sub: _projectRotation.upcoming()?.title == null
            ? 'Projekte festlegen'
            : 'Als Nächstes: ${_projectRotation.upcoming()!.title}',
        onTap: _openProjectRotationSheet,
      ),
      (
        icon: Icons.checklist_rounded,
        label: 'To-do-Liste (Deep Work)',
        sub: null,
        onTap: _openDeepWorkTodoSheet,
      ),
      (
        icon: Icons.edit_note_rounded,
        label: 'Notizen zum Tag',
        sub: null,
        onTap: _openIndividuellNotesSheet,
      ),
      (
        icon: Icons.date_range_rounded,
        label: 'Preset-Zeitraum',
        sub: 'Welche Vorlage an welchen Tagen gilt',
        onTap: _openPresetWindowDialog,
      ),
      (
        icon: Icons.notifications_none_outlined,
        label: 'Erinnerungen & Wecker',
        sub: null,
        onTap: _openReminderPrefsSheet,
      ),
      (
        icon: _showFreeTimeLanes
            ? Icons.view_agenda_outlined
            : Icons.view_day_outlined,
        label: _showFreeTimeLanes
            ? 'Freizeit-Leisten ausblenden'
            : 'Freizeit-Leisten anzeigen',
        sub: 'Nur in der Listen-Ansicht',
        onTap: () => unawaited(_setShowFreeTimeLanes(!_showFreeTimeLanes)),
      ),
      (
        icon: Icons.format_color_fill_outlined,
        label: 'Kategoriefarben',
        sub: null,
        onTap: _openCategoryColorSettings,
      ),
      (
        icon: Icons.cloud_outlined,
        label: 'Cloud-Sync',
        sub: 'Mehrere Geräte',
        onTap: _openCloudSyncSheet,
      ),
    ];
    final picked = await showModalBottomSheet<VoidCallback>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: Material(
            color: p.surface,
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.85,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: p.hairline,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    for (final it in items)
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Icon(it.icon, color: p.accent),
                        title: Text(
                          it.label,
                          style: TextStyle(
                            color: p.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: it.sub == null
                            ? null
                            : Text(it.sub!, style: TextStyle(color: p.muted)),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: p.muted,
                        ),
                        onTap: () => Navigator.pop(sheetCtx, it.onTap),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) picked();
  }

  // ─── Raster-Ansicht (Zeitraster wie im Kalender) ───────────────────────────

  static const double _kGridHourH = 64.0;
  static const double _kGridGutterW = 46.0;
  static const String _kDayGridViewPrefKey = 'planner_day_grid_view_v1';

  Future<void> _loadDayGridView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final on = prefs.getBool(_kDayGridViewPrefKey) ?? true;
      if (!mounted) return;
      setState(() => _dayGridView = on);
    } catch (_) {}
  }

  Future<void> _setDayGridView(bool on) async {
    setState(() {
      _dayGridView = on;
      _gridScrolledForDay = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDayGridViewPrefKey, on);
    } catch (_) {}
  }

  void _toggleBlockCompletedFromGrid(TimeBlock block) {
    _recordUndoSnapshot();
    setState(() {
      block.completed = !block.completed;
      _dayPlanPresetKind[_onlyDay(_selectedDate)] = _kIndividualDayPresetKey;
    });
    _syncProjectRotationForBlock(block);
    _schedulePersistDayPlans();
  }

  /// Startet das Raster beim Öffnen bei „jetzt − 1 h“ (heute) bzw. beim ersten Block.
  void _maybeAutoScrollGrid(List<TimeBlock> blocks) {
    final day = _onlyDay(_selectedDate);
    if (_gridScrolledForDay == day) return;
    _gridScrolledForDay = day;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_gridScroll.hasClients) return;
      final now = DateTime.now();
      int targetMin;
      if (day == _onlyDay(now)) {
        targetMin = now.hour * 60 + now.minute - 60;
      } else {
        targetMin = 1440;
        for (final b in blocks) {
          if (b.allDay || b.isOvernightSlot) continue;
          if (b.startMin < targetMin) targetMin = b.startMin;
        }
        if (targetMin == 1440) targetMin = 7 * 60;
        targetMin -= 30;
      }
      final off = (targetMin.clamp(0, 1440) / 60.0) * _kGridHourH;
      _gridScroll.jumpTo(off.clamp(0.0, _gridScroll.position.maxScrollExtent));
    });
  }

  Widget _dayTimeGrid(
    BuildContext context,
    List<TimeBlock> blocks, {
    required double hPad,
    required double bottomPad,
  }) {
    final p = context.palette;
    const ppm = _kGridHourH / 60.0;
    const totalH = _kGridHourH * 24;
    final isToday = _onlyDay(_selectedDate) == _onlyDay(DateTime.now());
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    // Segmente: Übernacht-Blöcke in zwei Teile (Abend + früher Morgen) zerlegen.
    final segs = <({TimeBlock b, int s, int e})>[];
    final allDay = <TimeBlock>[];
    for (final b in blocks) {
      if (b.allDay) {
        allDay.add(b);
      } else if (b.isLinearSlot) {
        segs.add((b: b, s: b.startMin, e: b.endMin));
      } else if (b.isOvernightSlot) {
        segs.add((b: b, s: b.startMin, e: 1440));
        if (b.endMin > 0) segs.add((b: b, s: 0, e: b.endMin));
      }
    }
    segs.sort((a, c) {
      final x = a.s.compareTo(c.s);
      return x != 0 ? x : c.e.compareTo(a.e);
    });

    // Überlappungen nebeneinander: Cluster bilden, in Spalten verteilen.
    final col = List<int>.filled(segs.length, 0);
    final cols = List<int>.filled(segs.length, 1);
    var i = 0;
    while (i < segs.length) {
      var j = i;
      var clusterEnd = segs[i].e;
      final colEnds = <int>[];
      while (j < segs.length && (j == i || segs[j].s < clusterEnd)) {
        final sg = segs[j];
        var placed = false;
        for (var c = 0; c < colEnds.length; c++) {
          if (colEnds[c] <= sg.s) {
            col[j] = c;
            colEnds[c] = sg.e;
            placed = true;
            break;
          }
        }
        if (!placed) {
          col[j] = colEnds.length;
          colEnds.add(sg.e);
        }
        if (sg.e > clusterEnd) clusterEnd = sg.e;
        j++;
      }
      for (var k = i; k < j; k++) {
        cols[k] = colEnds.length;
      }
      i = j;
    }

    // Freie Lücken (≥ 30 min) zwischen erstem und letztem Block des Tages.
    final gaps = <({int s, int e})>[];
    final linear = segs.where((x) => x.s > 0 || x.e < 1440).toList();
    if (linear.isNotEmpty) {
      var cursor = -1;
      for (final sg in linear) {
        if (cursor >= 0 && sg.s - cursor >= 30) {
          gaps.add((s: cursor, e: sg.s));
        }
        if (sg.e > cursor) cursor = sg.e;
      }
    }

    _maybeAutoScrollGrid(blocks);

    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: p.muted.withValues(alpha: 0.8),
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allDay.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(hPad + _kGridGutterW, 2, hPad, 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in allDay)
                  ActionChip(
                    avatar: Icon(
                      _resolveBlockIcon(b),
                      size: 16,
                      color: _stripeForBlock(b),
                    ),
                    label: Text(b.title),
                    onPressed: () => _openEditBlockDialog(b),
                  ),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: _gridScroll,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(hPad, 8, hPad, bottomPad + 8),
            child: SizedBox(
              height: totalH,
              child: LayoutBuilder(
                builder: (context, cons) {
                  final laneW = cons.maxWidth - _kGridGutterW;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Stundenlinien + Beschriftung
                      for (var h = 0; h <= 24; h++)
                        Positioned(
                          top: h * _kGridHourH,
                          left: 0,
                          right: 0,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: _kGridGutterW - 6,
                                child: Transform.translate(
                                  offset: const Offset(0, -0.5),
                                  child: Text(
                                    h == 24 ? '' : '${h.toString().padLeft(2, '0')}:00',
                                    style: labelStyle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: p.hairline.withValues(
                                    alpha: p.isDark ? 0.55 : 0.9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Freie Zeit
                      for (final g in gaps)
                        Positioned(
                          top: g.s * ppm + 3,
                          height: (g.e - g.s) * ppm - 6,
                          left: _kGridGutterW,
                          right: 0,
                          child: IgnorePointer(
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: p.muted.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Text(
                                'frei · ${_fmtGridDur(g.e - g.s)}',
                                style: labelStyle?.copyWith(
                                  color: p.muted.withValues(alpha: 0.65),
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Blöcke
                      for (var k = 0; k < segs.length; k++)
                        _gridBlockPositioned(
                          context,
                          segs[k].b,
                          segs[k].s,
                          segs[k].e,
                          left: _kGridGutterW + laneW * col[k] / cols[k],
                          width: laneW / cols[k],
                          ppm: ppm,
                        ),
                      // Jetzt-Linie
                      if (isToday)
                        Positioned(
                          top: nowMin * ppm - 4,
                          left: _kGridGutterW - 5,
                          right: 0,
                          child: IgnorePointer(
                            child: Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: kDefaultCategoryColors['Fokus'],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 2,
                                    color: kDefaultCategoryColors['Fokus'],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _fmtGridDur(int m) {
    final h = m ~/ 60;
    final r = m % 60;
    if (h == 0) return '$r min';
    if (r == 0) return '$h h';
    return '$h:${r.toString().padLeft(2, '0')} h';
  }

  Widget _gridBlockPositioned(
    BuildContext context,
    TimeBlock block,
    int s,
    int e, {
    required double left,
    required double width,
    required double ppm,
  }) {
    final p = context.palette;
    final stripe = _stripeForBlock(block);
    final mealVis = _useMealVisualFor(block);
    final live = _isWallClockActiveBlock(block);
    final done = block.completed;
    final gridFillFrac = live
        ? _slotElapsedFractionWhileLive(block)
        : (_isBlockPast(block) ? 1.0 : null);
    final rawH = (e - s) * ppm;
    final h = max(rawH - 3, 20.0);
    final compact = h < 44;
    final twoLineTitle = h >= 92;
    final edge = mealVis ? MealBlockTheme.outline : stripe;
    final fill = mealVis
        ? MealBlockTheme.fillBase.withValues(
            alpha: live ? 0.16 : MealBlockTheme.cardFillAlpha + 0.03,
          )
        : stripe.withValues(
            alpha: live ? p.stripeFillAlpha + 0.10 : p.stripeFillAlpha,
          );
    final titleClr = done ? p.muted.withValues(alpha: 0.6) : p.text;
    final subClr = p.muted.withValues(alpha: done ? 0.45 : 0.9);
    final dur = block.spanMinutes;
    final timeLabel =
        '${_fmtMin(block.startMin)}–${_fmtMin(block.endMin % 1440)} · ${_fmtGridDur(dur)}';
    final isProject = _isProjectSessionBlock(block);
    final projectName = isProject ? _projectSessionLabel(block) : null;
    final shownTitle = projectName ?? block.title;
    final shownTime = isProject ? 'Projekt-Session · $timeLabel' : timeLabel;

    Widget check() => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleBlockCompletedFromGrid(block),
      child: Padding(
        padding: EdgeInsets.fromLTRB(2, compact ? 0 : 1, 8, 0),
        child: Container(
          width: compact ? 16 : 19,
          height: compact ? 16 : 19,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? p.text.withValues(alpha: 0.14) : Colors.transparent,
            border: Border.all(
              color: done ? p.text.withValues(alpha: 0.4) : edge,
              width: 1.8,
            ),
          ),
          child: done
              ? Icon(Icons.check_rounded, size: compact ? 11 : 13, color: p.text)
              : null,
        ),
      ),
    );

    final title = Text(
      shownTitle,
      maxLines: twoLineTitle ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontSize: compact ? 12.5 : 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
        color: titleClr,
        decoration: done ? TextDecoration.lineThrough : null,
        decorationColor: p.muted,
      ),
    );

    return Positioned(
      top: s * ppm + 1.5,
      left: left + 1,
      width: width - 2,
      height: h,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (_isProjectSessionBlock(block)) {
              unawaited(_openProjectSessionSheet(block));
            } else {
              _openEditBlockDialog(block);
            }
          },
          child: Ink(
            decoration: BoxDecoration(
              color: Color.alphaBlend(fill, p.surface),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: edge.withValues(
                  alpha: live ? 0.95 : (done ? 0.3 : 0.62),
                ),
                width: live ? 1.8 : 1.2,
              ),
              boxShadow: live
                  ? [
                      BoxShadow(
                        color: edge.withValues(alpha: p.isDark ? 0.45 : 0.25),
                        blurRadius: 18,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (gridFillFrac != null && gridFillFrac > 0.001)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _liveProgressStripeFill(
                        fraction: gridFillFrac.clamp(0.0, 1.0),
                        stripe: edge,
                        clipCornerRadius: 11,
                      ),
                    ),
                  ),
                ClipRect(
              child: Padding(
              padding: EdgeInsets.fromLTRB(8, compact ? 2 : 7, 8, compact ? 2 : 6),
              child: compact
                  ? Row(
                      children: [
                        check(),
                        Expanded(child: title),
                        if (width > 150)
                          Text(
                            _fmtMin(block.startMin),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: subClr),
                          ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        check(),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              title,
                              const SizedBox(height: 2),
                              Text(
                                shownTime,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: subClr,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 1),
                          child: Icon(
                            _resolveBlockIcon(block),
                            size: 16,
                            color: edge.withValues(alpha: done ? 0.4 : 0.85),
                          ),
                        ),
                      ],
                    ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Projekt-Rotation („Projekt-Session“) ─────────────────────────────────

  bool _isProjectSessionBlock(TimeBlock b) =>
      !b.allDay && isProjectSessionTitle(b.title);

  Future<void> _loadProjectRotation() async {
    final r = await ProjectRotation.load();
    if (!mounted) return;
    setState(() => _projectRotation = r);
  }

  Future<void> _saveProjectRotation() async {
    await _projectRotation.save();
    solNotifyPlannerDiskDataChanged();
  }

  /// Nach Abhaken/Öffnen einer Projekt-Session: Rotation weiterdrehen bzw. zurücknehmen.
  void _syncProjectRotationForBlock(TimeBlock b) {
    if (!_isProjectSessionBlock(b) || _projectRotation.isEmpty) return;
    final day = _onlyDay(_selectedDate);
    setState(() {
      if (b.completed) {
        _projectRotation.markDone(day, b.id);
      } else {
        _projectRotation.markUndone(day, b.id);
      }
    });
    unawaited(_saveProjectRotation());
  }

  Widget _projectNextChip(BuildContext context, TimeBlock block, Color? ink) {
    final p = context.palette;
    final name = _projectSessionLabel(block);
    final done = block.completed && name != null;
    final accent = ink ?? p.accent;
    final label = name == null
        ? (_projectRotation.isEmpty ? 'Projekte festlegen' : 'Projekt-Session')
        : (done ? name : 'Als Nächstes · $name');
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => _openProjectSessionSheet(block),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: done ? 0.07 : 0.15),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: accent.withValues(alpha: done ? 0.3 : 0.55),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  done
                      ? Icons.check_rounded
                      : (name == null
                            ? Icons.add_rounded
                            : Icons.autorenew_rounded),
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Projekt einer Projekt-Session: abgehakt → zugeordnetes Projekt,
  /// offen → das nächste in der Rotation (mehrere offene Sessions am Tag zählen weiter).
  RotationProject? _projectSessionProject(TimeBlock b) {
    if (_projectRotation.isEmpty) return null;
    final day = _onlyDay(_selectedDate);
    if (b.completed) {
      final pid = _projectRotation.assigned[ProjectRotation.keyFor(day, b.id)];
      return pid == null ? null : _projectRotation.byId(pid);
    }
    var offset = 0;
    for (final x in _getBlocksForDay(_selectedDate)) {
      if (x.id == b.id || x.completed || !_isProjectSessionBlock(x)) continue;
      if (x.startMin < b.startMin ||
          (x.startMin == b.startMin && x.id.compareTo(b.id) < 0)) {
        offset++;
      }
    }
    return _projectRotation.upcoming(offset);
  }

  String? _projectSessionLabel(TimeBlock b) => _projectSessionProject(b)?.title;

  static const List<String> _kWeekdayShort = [
    'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So',
  ];

  String _fmtShortDate(DateTime d) =>
      '${_kWeekdayShort[d.weekday - 1]}, ${d.day}.${d.month}.${d.year == DateTime.now().year ? '' : d.year}';

  /// Fertigen „Projekt-Session“-Block (60 min) in die nächste freie Lücke des Tages legen.
  void _addProjectSessionBlock() {
    final day = _onlyDay(_selectedDate);
    final blocks = _getBlocksForDay(_selectedDate);
    final now = DateTime.now();
    const want = 60;
    final from = day == _onlyDay(now)
        ? (((now.hour * 60 + now.minute + 14) ~/ 15) * 15).clamp(0, 1440 - want)
        : 9 * 60;
    final busy = <List<int>>[];
    for (final b in blocks) {
      if (b.allDay) continue;
      if (b.isLinearSlot) {
        busy.add([b.startMin, b.endMin]);
      } else if (b.isOvernightSlot) {
        busy.add([b.startMin, 1440]);
        busy.add([0, b.endMin]);
      }
    }
    busy.sort((a, c) => a[0].compareTo(c[0]));
    int? start;
    var cursor = from;
    for (final iv in busy) {
      if (iv[1] <= cursor) continue;
      if (iv[0] - cursor >= want) {
        start = cursor;
        break;
      }
      if (iv[1] > cursor) cursor = iv[1];
    }
    if (start == null && 1440 - cursor >= want) start = cursor;
    final s = start ?? from;
    final e = s + want;
    final label = _categoryColors.containsKey('Fokus')
        ? 'Fokus'
        : _fallbackCategoryLabel();
    _recordUndoSnapshot();
    final block = _newBlock(
      'Projekt-Session',
      s,
      e,
      label,
      '',
      customIconCodePoint: Icons.autorenew_rounded.codePoint,
    );
    setState(() {
      blocks.add(block);
      _repairOverlapsWithPins(blocks);
      _repairUnpinnedLinearOverlaps(blocks);
      _repairOverlapsWithPins(blocks);
      _dayPlanPresetKind[day] = _kIndividualDayPresetKey;
      _gridScrolledForDay = null;
    });
    _schedulePersistDayPlans();
    unawaited(_syncReminders());
    final next = _projectSessionLabel(block);
    final pushed = start == null;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: Duration(seconds: pushed ? 6 : 4),
        content: Text(
          'Projekt-Session ${_fmtMin(block.startMin)}–${_fmtMin(block.endMin % 1440)} hinzugefügt'
          '${next != null ? ' · $next' : ''}'
          '${pushed ? '\nKein freier Platz – folgende Blöcke 1 h nach hinten verschoben.' : ''}',
        ),
        action: pushed
            ? SnackBarAction(label: 'Rückgängig', onPressed: _undoLastChange)
            : null,
      ),
    );
  }

  Widget _sheetFrame(BuildContext sheetCtx, List<Widget> children) {
    final p = sheetCtx.palette;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: Material(
          color: p.surface,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.9,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                          color: p.hairline,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _eyebrow(BuildContext context, String text) {
    final p = context.palette;
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: p.accent,
      ),
    );
  }

  /// Verlauf eines Projekts: Datum, „vor X Tagen“ und Notiz.
  List<Widget> _projectHistoryWidgets(
    BuildContext context,
    RotationProject pr, {
    String? excludeKey,
  }) {
    final p = context.palette;
    final hist = _projectRotation
        .history(pr.id)
        .where((e) => e.key != excludeKey)
        .toList();
    if (hist.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Noch keine erledigten Sessions.',
            style: TextStyle(color: p.muted),
          ),
        ),
      ];
    }
    return [
      for (final e in hist)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: p.bg.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fmtShortDate(e.day),
                      style: TextStyle(
                        color: p.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    lastDoneLabel(e.day),
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                ],
              ),
              if (e.note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  e.note,
                  style: TextStyle(color: p.muted, height: 1.35),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  /// Tippen auf eine Projekt-Session: aktuelles Projekt, Notizen, Verlauf.
  Future<void> _openProjectSessionSheet(TimeBlock block) async {
    final day = _onlyDay(_selectedDate);
    final noteCtrl = TextEditingController(
      text: _projectRotation.noteFor(day, block.id),
    );
    void saveNote() {
      final pr = _projectSessionProject(block);
      if (pr == null) return;
      if (_projectRotation.noteFor(day, block.id) == noteCtrl.text.trim()) {
        return;
      }
      _projectRotation.setNote(day, block.id, pr.id, noteCtrl.text);
      unawaited(_saveProjectRotation());
    }

    String? after;
    try {
      after = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          return StatefulBuilder(
            builder: (context, setLocal) {
              final p = context.palette;
              final pr = _projectSessionProject(block);
              final last = pr == null
                  ? null
                  : _projectRotation.lastDone(pr.id);
              final key = ProjectRotation.keyFor(day, block.id);
              return _sheetFrame(sheetCtx, [
                _eyebrow(
                  context,
                  block.completed ? 'ERLEDIGT' : 'ALS NÄCHSTES',
                ),
                const SizedBox(height: 4),
                Text(
                  pr?.title ?? 'Noch keine Projekte',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmtMin(block.startMin)}–${_fmtMin(block.endMin % 1440)}'
                  '${pr == null ? '' : ' · Zuletzt: ${lastDoneLabel(last)}'}',
                  style: TextStyle(color: p.muted),
                ),
                const SizedBox(height: 16),
                if (pr == null) ...[
                  Text(
                    'Lege zuerst deine Projekte an (z. B. Programmieren, Klavier, Portugiesisch). '
                    'Danach zeigt jede Projekt-Session automatisch das nächste.',
                    style: TextStyle(color: p.muted, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetCtx, 'rotation'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Projekte festlegen'),
                  ),
                ] else ...[
                  TextField(
                    controller: noteCtrl,
                    minLines: 3,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => saveNote(),
                    decoration: InputDecoration(
                      labelText: 'Notizen für diese Session',
                      hintText: 'z. B. heute: Vokabeln Kapitel 3',
                      hintStyle: TextStyle(color: p.muted),
                      filled: true,
                      fillColor: p.bg.withValues(alpha: 0.35),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.hairline),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            saveNote();
                            _toggleBlockCompletedFromGrid(block);
                            setLocal(() {});
                          },
                          icon: Icon(
                            block.completed
                                ? Icons.undo_rounded
                                : Icons.check_rounded,
                          ),
                          label: Text(
                            block.completed ? 'Wieder öffnen' : 'Erledigt',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx, 'edit'),
                        child: const Text('Block bearbeiten'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _eyebrow(context, 'VERLAUF · ${pr.title.toUpperCase()}'),
                  const SizedBox(height: 8),
                  ..._projectHistoryWidgets(context, pr, excludeKey: key),
                ],
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => Navigator.pop(sheetCtx, 'rotation'),
                  icon: const Icon(Icons.autorenew_rounded, size: 18),
                  label: const Text('Alle Projekte & Reihenfolge'),
                ),
              ]);
            },
          );
        },
      );
    } finally {
      saveNote();
      noteCtrl.dispose();
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    if (after == 'edit') _openEditBlockDialog(block);
    if (after == 'rotation') unawaited(_openProjectRotationSheet());
  }

  /// Verlauf & Notizen eines Projekts (aus der Projektliste).
  Future<void> _openProjectLogSheet(RotationProject pr) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final p = context.palette;
            final isNext = _projectRotation.upcoming()?.id == pr.id;
            final count = _projectRotation.history(pr.id).length;
            return _sheetFrame(sheetCtx, [
              if (isNext) _eyebrow(context, 'ALS NÄCHSTES'),
              Text(
                pr.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Zuletzt: ${lastDoneLabel(_projectRotation.lastDone(pr.id))} · '
                '$count ${count == 1 ? 'Session' : 'Sessions'}',
                style: TextStyle(color: p.muted),
              ),
              if (!isNext) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _projectRotation.setNext(pr.id));
                    unawaited(_saveProjectRotation());
                    setLocal(() {});
                  },
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Als Nächstes setzen'),
                ),
              ],
              const SizedBox(height: 20),
              _eyebrow(context, 'VERLAUF'),
              const SizedBox(height: 8),
              ..._projectHistoryWidgets(context, pr),
            ]);
          },
        );
      },
    );
  }

  Future<void> _openProjectRotationSheet() async {
    final addCtrl = TextEditingController();
    final addFocus = FocusNode();
    var addSession = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          return StatefulBuilder(
            builder: (context, setLocal) {
              final p = context.palette;
              final rot = _projectRotation;
              final next = rot.upcoming();
              void changed() {
                setLocal(() {});
                if (mounted) setState(() {});
                unawaited(_saveProjectRotation());
              }

              void addFromField() {
                if (addCtrl.text.trim().isEmpty) return;
                rot.add(addCtrl.text);
                addCtrl.clear();
                changed();
                addFocus.requestFocus();
              }

              return _sheetFrame(sheetCtx, [
                Row(
                  children: [
                    Icon(Icons.autorenew_rounded, color: p.text),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Projekt-Rotation',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Jede Projekt-Session zeigt das nächste Projekt. Erledigt → das nächste ist dran, '
                  'nach dem letzten geht es von vorn los. Tippen zeigt Verlauf & Notizen, '
                  'ziehen ändert die Reihenfolge.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: p.muted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    addSession = true;
                    Navigator.pop(sheetCtx);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Projekt-Session zum Plan hinzufügen'),
                ),
                const SizedBox(height: 14),
                if (rot.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Noch keine Projekte. Füge unten z. B. Programmieren, Klavier, Portugiesisch hinzu.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: p.muted,
                      ),
                    ),
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: rot.items.length,
                    onReorder: (o, n) {
                      rot.reorder(o, n);
                      changed();
                    },
                    itemBuilder: (c, i) {
                      final item = rot.items[i];
                      final isNext = next?.id == item.id;
                      return Padding(
                        key: ValueKey('rot_${item.id}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: isNext
                              ? p.accent.withValues(alpha: 0.10)
                              : p.bg.withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isNext
                                  ? p.accent.withValues(alpha: 0.7)
                                  : p.hairline,
                              width: isNext ? 1.6 : 1,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              await _openProjectLogSheet(item);
                              setLocal(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isNext
                                          ? p.accent
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isNext ? p.accent : p.hairline,
                                      ),
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: isNext ? p.bg : p.accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (isNext)
                                          Text(
                                            'ALS NÄCHSTES',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.4,
                                              color: p.accent,
                                            ),
                                          ),
                                        Text(
                                          item.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: p.text,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        Text(
                                          'Zuletzt: ${lastDoneLabel(rot.lastDone(item.id))}',
                                          style: TextStyle(
                                            color: p.muted,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Entfernen',
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      color: p.muted,
                                    ),
                                    onPressed: () {
                                      rot.remove(item.id);
                                      changed();
                                    },
                                  ),
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        Icons.drag_handle_rounded,
                                        color: p.muted.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: addCtrl,
                        focusNode: addFocus,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Neues Projekt …',
                          hintStyle: TextStyle(color: p.muted),
                          filled: true,
                          fillColor: p.bg.withValues(alpha: 0.35),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: p.hairline),
                          ),
                        ),
                        onSubmitted: (_) => addFromField(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: addFromField,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ]);
            },
          );
        },
      );
    } finally {
      addCtrl.dispose();
      addFocus.dispose();
    }
    if (addSession && mounted) _addProjectSessionBlock();
  }

  Future<void> _openReminderPrefsSheet() async {
    final next = await showPlannerReminderPrefsSheet(
      context,
      initial: _reminderPrefs,
      todayReminderSlices: _reminderSlicesForToday(),
    );
    if (next == null || !mounted) return;
    setState(() => _reminderPrefs = next);
    await savePlannerReminderPrefs(next);
    unawaited(_syncReminders());
  }

  void _stashFreeformForCurrentDay() {
    _freeformNotesByDay[_onlyDay(_selectedDate)] = _freeformCtrl.text;
  }

  void _loadFreeformForCurrentDay() {
    if (!mounted) return;
    final t = _freeformNotesByDay[_onlyDay(_selectedDate)] ?? '';
    if (_freeformCtrl.text == t) return;
    _freeformCtrl.text = t;
  }

  void _scheduleFreeformSave() {
    _stashFreeformForCurrentDay();
    _freeformSaveDebounce?.cancel();
    _freeformSaveDebounce = Timer(
      const Duration(milliseconds: 450),
      _persistFreeformNotes,
    );
  }

  Future<void> _persistFreeformNotes() async {
    _stashFreeformForCurrentDay();
    final out = <String, String>{};
    for (final e in _freeformNotesByDay.entries) {
      if (e.value.trim().isNotEmpty) {
        out[_dateInput(e.key)] = e.value;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFreeformDayNotesPrefKey, jsonEncode(out));
      solNotifyPlannerDiskDataChanged();
    } catch (_) {}
  }

  void _schedulePersistDayPlans() {
    _dayPlansSaveDebounce?.cancel();
    _dayPlansSaveDebounce = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_persistDayPlans()),
    );
  }

  /// Sofort speichern (z. B. Flex-Reorder, App in den Hintergrund) — vermeidet verlorene Timer/Schließungen.
  void _flushPersistDayPlans() {
    _dayPlansSaveDebounce?.cancel();
    unawaited(_persistDayPlans());
  }

  /// Vor dem ersten Frame aus [PlannerHome.initialPlannerDaysJson] / Disk — verhindert Preset-vor-Cache-Race.
  void _mergeDayPlansFromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final root = Map<String, dynamic>.from(decoded);
      final daysRaw = root['days'];
      if (daysRaw is! Map) return;
      final days = Map<String, dynamic>.from(daysRaw);

      final parsedDays = <DateTime, List<TimeBlock>>{};
      final parsedKinds = <DateTime, String>{};

      for (final e in days.entries) {
        final d = _parseDate(e.key.toString());
        if (d == null) continue;
        final day = _onlyDay(d);
        final payload = e.value;
        if (payload is! Map) continue;
        final payloadMap = Map<String, dynamic>.from(payload);
        final pk = payloadMap['presetKind'];
        final bl = payloadMap['blocks'];
        if (pk is! String || pk.isEmpty || bl is! List) continue;
        final blocks = <TimeBlock>[];
        for (final item in bl) {
          try {
            if (item is Map<String, dynamic>) {
              blocks.add(TimeBlock.fromJson(item));
            } else if (item is Map) {
              blocks.add(TimeBlock.fromJson(Map<String, dynamic>.from(item)));
            }
          } catch (_) {}
        }
        if (bl.isNotEmpty && blocks.isEmpty) continue;
        parsedDays[day] = blocks;
        parsedKinds[day] = pk;
      }

      if (parsedDays.isEmpty) return;

      _days.addAll(parsedDays);
      for (final kv in parsedKinds.entries) {
        _dayPlanPresetKind[kv.key] = kv.value;
      }
      _bumpIdCounterFromLoadedDays();
    } catch (_) {}
  }

  void _bumpIdCounterFromLoadedDays() {
    var maxN = _idCounter;
    void scan(String id) {
      final m = RegExp(r'^b(\d+)$').firstMatch(id);
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n > maxN) maxN = n;
      }
    }

    for (final list in _days.values) {
      for (final b in list) {
        scan(b.id);
      }
    }
    _idCounter = maxN;
  }

  Future<void> _persistDayPlans() async {
    try {
      final daysOut = <String, dynamic>{};
      for (final e in _days.entries) {
        final dateKey = _dateInput(e.key);
        final pk = _dayPlanPresetKind[e.key];
        if (pk == null || pk.isEmpty) continue;
        daysOut[dateKey] = {
          'presetKind': pk,
          'blocks': e.value.map((b) => b.toJson()).toList(),
        };
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kPlannerCachedDaysPrefKey,
        jsonEncode(<String, dynamic>{'days': daysOut}),
      );
      solNotifyPlannerDiskDataChanged();
    } catch (_) {}
  }

  Future<void> _loadFreeformNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kFreeformDayNotesPrefKey);
      if (raw == null || raw.isEmpty) {
        if (mounted) {
          _loadFreeformForCurrentDay();
        }
        return;
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        for (final e in map.entries) {
          final d = _parseDate(e.key);
          if (d != null && e.value is String) {
            _freeformNotesByDay[_onlyDay(d)] = e.value as String;
          }
        }
      });
      _loadFreeformForCurrentDay();
    } catch (_) {
      if (mounted) {
        _loadFreeformForCurrentDay();
      }
    }
  }

  Future<void> _loadSubtaskQuickPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSubtaskQuickPresetsPrefKey);
      if (raw == null || raw.isEmpty) {
        if (!mounted) return;
        setState(() {
          _subtaskQuickPresets = List<String>.from(kDefaultSubtaskQuickPresets);
        });
        await _saveSubtaskQuickPresets();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final list = <String>[];
      for (final e in decoded) {
        if (e is String) {
          final s = e.trim();
          if (s.isNotEmpty) list.add(s);
        }
      }
      if (!mounted) return;
      setState(() {
        _subtaskQuickPresets = list;
      });
    } catch (_) {}
  }

  Future<void> _saveSubtaskQuickPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kSubtaskQuickPresetsPrefKey,
        jsonEncode(_subtaskQuickPresets),
      );
      solNotifyPlannerDiskDataChanged();
    } catch (_) {}
  }

  Future<void> _openSubtaskQuickPresetsEditor() async {
    final addCtrl = TextEditingController();
    var items = List<String>.from(_subtaskQuickPresets);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final p = sheetCtx.palette;
        final bottom = MediaQuery.of(sheetCtx).viewInsets.bottom;
        final maxH = MediaQuery.of(sheetCtx).size.height * 0.72;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              child: Container(
                height: maxH,
                color: p.surface,
                child: StatefulBuilder(
                  builder: (ctx, setLocal) {
                    void commitAndPop() {
                      if (!mounted) return;
                      setState(
                        () => _subtaskQuickPresets = List<String>.from(items),
                      );
                      unawaited(_saveSubtaskQuickPresets());
                      Navigator.of(ctx).pop();
                    }

                    return Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 10, bottom: 6),
                          decoration: BoxDecoration(
                            color: p.hairline,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Checklisten-Vorlagen',
                                  style: Theme.of(sheetCtx)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: p.text,
                                      ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: Text(
                                  'Abbrechen',
                                  style: TextStyle(color: p.muted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            'Diese Chips erscheinen beim Bearbeiten eines Blocks; ein Tippen fügt eine abhakbare Unteraufgabe hinzu.',
                            style: Theme.of(sheetCtx).textTheme.bodySmall
                                ?.copyWith(color: p.muted, height: 1.35),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: items.isEmpty
                              ? Center(
                                  child: Text(
                                    'Noch keine Vorlagen — unten hinzufügen.',
                                    style: TextStyle(
                                      color: p.muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    8,
                                  ),
                                  itemCount: items.length,
                                  separatorBuilder: (context, _) => Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: p.hairline.withValues(alpha: 0.85),
                                  ),
                                  itemBuilder: (c, i) {
                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 0,
                                          ),
                                      title: Text(
                                        items[i],
                                        style: TextStyle(
                                          color: p.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        tooltip: 'Entfernen',
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: p.muted,
                                        ),
                                        onPressed: () =>
                                            setLocal(() => items.removeAt(i)),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: addCtrl,
                                  maxLines: 1,
                                  textInputAction: TextInputAction.done,
                                  style: TextStyle(color: p.text),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: p.hintBg,
                                    hintText: 'Neue Vorlage …',
                                    hintStyle: TextStyle(color: p.muted),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(color: p.hairline),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(color: p.hairline),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: p.text.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                  onSubmitted: (_) {
                                    final s = addCtrl.text.trim();
                                    if (s.isEmpty) return;
                                    setLocal(() {
                                      items.add(s);
                                      addCtrl.clear();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    foregroundColor: p.bg,
                                    backgroundColor: p.text,
                                  ),
                                  onPressed: () {
                                    final s = addCtrl.text.trim();
                                    if (s.isEmpty) return;
                                    setLocal(() {
                                      items.add(s);
                                      addCtrl.clear();
                                    });
                                  },
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 22,
                                    color: p.bg,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            14,
                            0,
                            14,
                            12 + MediaQuery.of(ctx).padding.bottom,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                foregroundColor: p.bg,
                                backgroundColor: p.text,
                              ),
                              onPressed: commitAndPop,
                              child: const Text(
                                'Änderungen speichern',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() => addCtrl.dispose());
  }

  /// Einmaliges Willkommens-Statement beim ersten App-Öffnen (nach Install).
  Future<void> _maybeShowFirstLaunchWelcome() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (prefs.getBool(_kFirstLaunchWelcomeShownPrefKey) ?? false) return;
    bool strNonEmpty(String? v) =>
        v != null && v.trim().isNotEmpty && v.trim() != '{}';
    final hasLegacyData =
        strNonEmpty(prefs.getString(_kCategoryCatalogPrefKey)) ||
        strNonEmpty(prefs.getString(_kCategoryColorsPrefKey)) ||
        strNonEmpty(prefs.getString(_kFreeformDayNotesPrefKey)) ||
        strNonEmpty(prefs.getString(_kUserPresetDaysPrefKey)) ||
        strNonEmpty(prefs.getString(_kPresetTaskTemplatesPrefKey));
    if (hasLegacyData) {
      await prefs.setBool(_kFirstLaunchWelcomeShownPrefKey, true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final palette = ctx.palette;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Willkommen',
            style: Theme.of(
              ctx,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Du planst nicht Aufgaben – du planst Zeitblöcke in einem realistischen 24h-Tag.',
            style: Theme.of(
              ctx,
            ).textTheme.bodyLarge?.copyWith(height: 1.4, color: palette.text),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Weiter'),
            ),
          ],
        );
      },
    );
    await prefs.setBool(_kFirstLaunchWelcomeShownPrefKey, true);
  }

  @override
  void initState() {
    super.initState();
    _mergeDayPlansFromJsonString(widget.initialPlannerDaysJson);
    WidgetsBinding.instance.addObserver(this);
    attachPlannerReminderRescheduleCallback(() {
      if (!mounted) return;
      unawaited(_syncReminders());
    });
    unawaited(plannerNotificationsInit());
    _reminderTicker = Timer.periodic(const Duration(seconds: 35), (_) {
      if (!mounted) return;
      unawaited(_syncReminders());
      unawaited(_publishCurrentTaskWidgets());
    });
    _minutePulseTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
      unawaited(_publishCurrentTaskWidgets());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) unawaited(_syncReminders());
      if (mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        unawaited(SolHomeWidgetSync.ensureConfigured());
        unawaited(_publishCurrentTaskWidgets());
      }
      if (!mounted) return;
      await _maybeShowFirstLaunchWelcome();
      if (!mounted) return;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      unawaited(_maybeAutoPullFromCloud());
    });
    _seedBacklog();
    _ensureDayExists(_selectedDate);
    Future<void>.microtask(() {
      if (mounted) unawaited(_syncReminders());
    });
    Future<void>.microtask(_loadCategoryColors);
    Future<void>.microtask(_loadCustomStripeSwatches);
    Future<void>.microtask(_loadCustomCategorySwatches);
    Future<void>.microtask(_loadPresetTaskOverrides);
    Future<void>.microtask(_loadUserPresetDays);
    Future<void>.microtask(_loadBuiltinPresetDisplayOverrides);
    Future<void>.microtask(_loadFreeformNotes);
    Future<void>.microtask(_loadSubtaskQuickPresets);
    Future<void>.microtask(_loadReminderPrefs);
    Future<void>.microtask(_loadDeepWorkTodos);
    Future<void>.microtask(_loadProjectRotation);
    Future<void>.microtask(_loadDayGridView);
    Future<void>.microtask(_loadShowFreeTimeLanes);
    Future<void>.microtask(_loadActivePresetKey);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    attachPlannerReminderRescheduleCallback(null);
    _reminderTicker?.cancel();
    _minutePulseTimer?.cancel();
    _freeformSaveDebounce?.cancel();
    _stashFreeformForCurrentDay();
    unawaited(_persistFreeformNotes());
    _flushPersistDayPlans();
    _freeformCtrl.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _flushPersistDayPlans();
    }
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      unawaited(_syncReminders());
      unawaited(_publishCurrentTaskWidgets());
      unawaited(_maybeAutoPullFromCloud());
    }
  }

  Future<void> _loadCategoryColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawV3 = prefs.getString(_kCategoryCatalogPrefKey);
      if (rawV3 != null && rawV3.isNotEmpty) {
        final decoded = jsonDecode(rawV3);
        if (decoded is Map<String, dynamic>) {
          final ord = decoded['order'];
          final cols = decoded['colors'];
          if (ord is List && cols is Map) {
            final newOrder = <String>[];
            for (final o in ord) {
              if (o is String) {
                final s = o.trim();
                if (s.isNotEmpty) newOrder.add(s);
              }
            }
            final newColors = <String, Color>{};
            for (final e in cols.entries) {
              final k = e.key;
              final v = e.value;
              if (k is String && v is String) {
                newColors[k] = _colorFromHexString(v);
              }
            }
            if (newOrder.isNotEmpty && newColors.isNotEmpty) {
              _applyCategorySnapshot(newOrder, newColors);
              if (!mounted) return;
              setState(() {});
              return;
            }
          }
        }
      }
      final raw = prefs.getString(_kCategoryColorsPrefKey);
      if (raw == null || raw.isEmpty) return;
      final map = Map<String, dynamic>.from(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (map.containsKey('Lesen') && !map.containsKey('Wichtig')) {
        map['Wichtig'] = map['Lesen'];
      }
      final newColors = <String, Color>{};
      for (final e in map.entries) {
        final v = e.value;
        if (v is String) {
          newColors[e.key.toString()] = _colorFromHexString(v);
        }
      }
      final newOrder = <String>[];
      for (final id in kCanonicalDefaultCategoryOrder) {
        if (newColors.containsKey(id)) newOrder.add(id);
      }
      final extras = newColors.keys.where((k) => !newOrder.contains(k)).toList()
        ..sort();
      newOrder.addAll(extras);
      if (newOrder.isEmpty) return;
      _applyCategorySnapshot(newOrder, newColors);
      if (!mounted) return;
      setState(() {});
    } catch (_) {}
  }

  /// Erzwingt: [order] listet alle Kategorien; [colors] hat zu jeder Liste einen Eintrag (fehlende → Grau).
  void _applyCategorySnapshot(List<String> order, Map<String, Color> colors) {
    final o = <String>[];
    final seen = <String>{};
    for (final n in order) {
      if (seen.add(n)) o.add(n);
    }
    for (final k in colors.keys) {
      if (!seen.contains(k)) o.add(k);
    }
    final c = <String, Color>{};
    final fallbackNeutral = const Color(0xFF6B7280);
    for (final n in o) {
      c[n] = colors[n] ?? fallbackNeutral;
    }
    _categoryOrder
      ..clear()
      ..addAll(o);
    _categoryColors
      ..clear()
      ..addAll(c);
  }

  Future<void> _saveCategoryColors() async {
    final out = <String, String>{};
    for (final e in _categoryColors.entries) {
      out[e.key] = _colorToHexArgb(e.value);
    }
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'order': _categoryOrder.toList(),
      'colors': out,
    });
    await prefs.setString(_kCategoryCatalogPrefKey, payload);
    await prefs.setString(_kCategoryColorsPrefKey, jsonEncode(out));
    solNotifyPlannerDiskDataChanged();
  }

  Future<void> _renameCategoryEverywhere(String from, String to) async {
    final t = to.trim();
    if (from == t || t.isEmpty) return;
    if (!_categoryColors.containsKey(from) || _categoryColors.containsKey(t)) {
      return;
    }
    final col = _categoryColors.remove(from)!;
    _categoryColors[t] = col;
    final ix = _categoryOrder.indexOf(from);
    if (ix >= 0) _categoryOrder[ix] = t;

    for (final list in _days.values) {
      for (final b in list) {
        if (b.colorLabel == from) b.colorLabel = t;
      }
    }
    for (final b in _backlog) {
      if (b.colorLabel == from) b.colorLabel = t;
    }

    for (final list in _presetTaskOverrides.values) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].colorLabel == from)
          list[i] = list[i].copyWith(colorLabel: t);
      }
    }

    for (var ui = 0; ui < _userPresetDays.length; ui++) {
      final u = _userPresetDays[ui];
      final newLines = u.lines.map((ln) {
        if (ln.colorLabel == from) return ln.copyWith(colorLabel: t);
        return ln;
      }).toList();
      if (!_presetLinesEqual(newLines, u.lines)) {
        _userPresetDays[ui] = u.copyWith(lines: newLines);
      }
    }

    setState(() {});
    await _saveCategoryColors();
    await _savePresetTaskOverrides();
    await _saveUserPresetDays();
    _schedulePersistDayPlans();
  }

  Future<void> _addNewCategory(String name) async {
    final n = name.trim();
    if (n.isEmpty || _categoryColors.containsKey(n)) return;
    setState(() {
      _categoryColors[n] =
          kCategoryColorSwatches[kCategoryColorSwatches.length ~/ 2];
      _categoryOrder.add(n);
    });
    await _saveCategoryColors();
  }

  /// Beim Löschen einer eigenen Kategorie: andere Kategorie für betroffene Blöcke/Vorlagen.
  String _replacementCategoryLabelBeforeRemove(String removing) {
    for (final k in _categoryOrder) {
      if (k != removing && _categoryColors.containsKey(k)) return k;
    }
    for (final k in kCanonicalDefaultCategoryOrder) {
      if (k != removing && _categoryColors.containsKey(k)) return k;
    }
    try {
      return kCanonicalDefaultCategoryOrder.firstWhere((k) => k != removing);
    } catch (_) {
      return kCanonicalDefaultCategoryOrder.first;
    }
  }

  /// Entfernt eine **eigene** Kategorie (nicht Mahlzeit/Fokus/Routine/Wichtig); [replacement] muss existieren.
  Future<void> _deleteCategoryEverywhere(
    String name,
    String replacement,
  ) async {
    if (kCanonicalDefaultCategoryOrder.contains(name)) return;
    if (!_categoryColors.containsKey(name) || name == replacement) return;

    for (final list in _days.values) {
      for (final b in list) {
        if (b.colorLabel == name) b.colorLabel = replacement;
      }
    }
    for (final b in _backlog) {
      if (b.colorLabel == name) b.colorLabel = replacement;
    }
    for (final list in _presetTaskOverrides.values) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].colorLabel == name) {
          list[i] = list[i].copyWith(colorLabel: replacement);
        }
      }
    }
    for (var ui = 0; ui < _userPresetDays.length; ui++) {
      final u = _userPresetDays[ui];
      final newLines = u.lines.map((ln) {
        if (ln.colorLabel == name) return ln.copyWith(colorLabel: replacement);
        return ln;
      }).toList();
      if (!_presetLinesEqual(newLines, u.lines)) {
        _userPresetDays[ui] = u.copyWith(lines: newLines);
      }
    }

    setState(() {
      _categoryColors.remove(name);
      _categoryOrder.remove(name);
    });
    await _saveCategoryColors();
    await _savePresetTaskOverrides();
    await _saveUserPresetDays();
    _schedulePersistDayPlans();
  }

  String _fallbackCategoryLabel() => _categoryOrder.isNotEmpty
      ? _categoryOrder.first
      : kCanonicalDefaultCategoryOrder.first;

  Future<void> _loadPresetTaskOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPresetTaskTemplatesPrefKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        for (final t in PlannerPresetType.values) {
          final list = map[t.name];
          if (list is! List) continue;
          final lines = <PresetTaskLine>[];
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              lines.add(PresetTaskLine.fromJson(item));
            }
          }
          if (lines.isNotEmpty) {
            _presetTaskOverrides[t] = lines;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _savePresetTaskOverrides() async {
    final out = <String, dynamic>{};
    for (final e in _presetTaskOverrides.entries) {
      if (e.value.isNotEmpty) {
        out[e.key.name] = e.value.map((x) => x.toJson()).toList();
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPresetTaskTemplatesPrefKey, jsonEncode(out));
    solNotifyPlannerDiskDataChanged();
  }

  String _normalizePresetCategoryLabel(String raw) {
    var t = raw.trim();
    if (t == 'Lesen') t = 'Wichtig';
    if (_categoryColors.containsKey(t)) return t;
    return _fallbackCategoryLabel();
  }

  List<PresetTaskLine> _effectivePresetLines(PlannerPresetType preset) {
    final custom = _presetTaskOverrides[preset];
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return builtinPresetLinesFor(preset);
  }

  TimeBlock _blockFromPresetLine(PresetTaskLine line) {
    return _newBlock(
      line.title.isEmpty ? 'Block' : line.title,
      line.startMin,
      line.endMin,
      _normalizePresetCategoryLabel(line.colorLabel),
      '',
      notes: line.notes,
    );
  }

  /// Vorlagenzeilen ab [cutOffMin]: erste Zeile wird bei Bedarf bei [cutOffMin] angeschnitten
  /// (laufender Slot → Preset-Inhalt ab jetzt).
  List<TimeBlock> _blocksFromPresetLinesAfterCutoff(
    int cutOffMin,
    List<PresetTaskLine> linesIn,
  ) {
    const minDur = 15;
    final sorted = [...linesIn]..sort((a, b) {
        final c = a.startMin.compareTo(b.startMin);
        if (c != 0) return c;
        return a.endMin.compareTo(b.endMin);
      });
    final out = <TimeBlock>[];
    for (final ln in sorted) {
      if (ln.endMin <= cutOffMin) continue;
      final start = ln.startMin < cutOffMin ? cutOffMin : ln.startMin;
      final end = ln.endMin;
      if (start >= end || end - start < minDur) continue;
      out.add(_blockFromPresetLine(ln.copyWith(startMin: start, endMin: end)));
    }
    return out;
  }

  Future<void> _loadUserPresetDays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kUserPresetDaysPrefKey);
      if (raw == null || raw.isEmpty) return;
      final arr = jsonDecode(raw);
      if (arr is! List) return;
      final loaded = <UserPresetDay>[];
      for (final item in arr) {
        if (item is Map<String, dynamic>) {
          loaded.add(UserPresetDay.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      if (!mounted) return;
      setState(() {
        _userPresetDays
          ..clear()
          ..addAll(loaded);
        _sanitizeActivePresetKeyIfStale();
      });
    } catch (_) {}
  }

  Future<void> _saveUserPresetDays() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kUserPresetDaysPrefKey,
      jsonEncode(_userPresetDays.map((e) => e.toJson()).toList()),
    );
    solNotifyPlannerDiskDataChanged();
  }

  Future<void> _loadActivePresetKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kActivePresetPrefKey);
      if (raw == null || raw.isEmpty) return;
      if (!_presetKeyIsValid(raw)) return;
      if (!mounted) return;
      setState(() => _activePresetKey = raw);
    } catch (_) {}
  }

  Future<void> _saveActivePresetKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActivePresetPrefKey, _resolvedActivePresetKey());
  }

  Future<void> _saveBuiltinPresetDisplayOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, String>{};
    for (final e in _builtinPresetDisplayOverrides.entries) {
      if (e.value.trim().isEmpty) continue;
      if (e.value.trim() == _presetLabel(e.key)) continue;
      map[e.key.name] = e.value.trim();
    }
    await prefs.setString(_kBuiltinPresetDisplayNamesPrefKey, jsonEncode(map));
    solNotifyPlannerDiskDataChanged();
  }

  Future<void> _loadBuiltinPresetDisplayOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kBuiltinPresetDisplayNamesPrefKey);
      if (raw == null || raw.isEmpty) return;
      final d = jsonDecode(raw);
      if (d is! Map) return;
      if (!mounted) return;
      setState(() {
        _builtinPresetDisplayOverrides.clear();
        for (final e in d.entries) {
          final bt = _tryBuiltinPresetKey(e.key.toString());
          if (bt != null && e.value is String) {
            final s = (e.value as String).trim();
            if (s.isNotEmpty) _builtinPresetDisplayOverrides[bt] = s;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _rehydratePlannerStateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final daysJson = prefs.getString(_kPlannerCachedDaysPrefKey);
    if (!mounted) return;
    setState(() {
      _days.clear();
      _dayPlanPresetKind.clear();
      _freeformNotesByDay.clear();
      _presetTaskOverrides.clear();
      _userPresetDays.clear();
      _builtinPresetDisplayOverrides.clear();
      _subtaskQuickPresets =
          List<String>.from(kDefaultSubtaskQuickPresets);
      _customStripeSwatches.clear();
      _customCategorySwatches.clear();
      _categoryColors = Map<String, Color>.from(kDefaultCategoryColors);
      _categoryOrder =
          List<String>.from(kCanonicalDefaultCategoryOrder);
      _undoStack.clear();
      _presetWindows.clear();
      _selectedBlockIds.clear();
      _expandedBlockIds.clear();
      _sessionLiveByKey.clear();
      _flexMode = false;
      _flexReorderGhostRange = null;
    });
    _mergeDayPlansFromJsonString(daysJson);
    await _loadCategoryColors();
    await _loadCustomStripeSwatches();
    await _loadCustomCategorySwatches();
    await _loadPresetTaskOverrides();
    await _loadUserPresetDays();
    await _loadBuiltinPresetDisplayOverrides();
    await _loadFreeformNotes();
    await _loadSubtaskQuickPresets();
    final nextRem = await loadPlannerReminderPrefs();
    if (!mounted) return;
    setState(() {
      _reminderPrefs = nextRem;
      _sanitizeActivePresetKeyIfStale();
    });
    _loadFreeformForCurrentDay();
    _ensureDayExists(_selectedDate);
    await _syncReminders();
    unawaited(_publishCurrentTaskWidgets());
  }

  Future<void> _maybeAutoPullFromCloud() async {
    if (!SolCloudConfig.isConfigured || !mounted) return;
    try {
      if (!await SolPlannerCloudCoordinator.instance.syncEnabledPrefs()) return;
      final applied =
          await SolPlannerCloudCoordinator.instance.pullAndApplyIfNewer();
      if (applied && mounted) {
        await _rehydratePlannerStateFromSharedPreferences();
      }
    } catch (_) {}
  }

  void _openCloudSyncSheet() {
    unawaited(
      showSolCloudSyncSheet(
        context,
        onAppliedRemotePayload: _rehydratePlannerStateFromSharedPreferences,
      ),
    );
  }

  PlannerPresetType? _tryBuiltinPresetKey(String key) {
    for (final t in PlannerPresetType.values) {
      if (t.name == key) return t;
    }
    return null;
  }

  String? _userIdFromPresetKey(String key) {
    if (!key.startsWith('u:')) return null;
    final id = key.substring(2).trim();
    return id.isEmpty ? null : id;
  }

  UserPresetDay? _userPresetForKey(String key) {
    final id = _userIdFromPresetKey(key);
    if (id == null) return null;
    for (final u in _userPresetDays) {
      if (u.id == id) return u;
    }
    return null;
  }

  bool _presetKeyIsValid(String key) {
    if (_tryBuiltinPresetKey(key) != null) return true;
    return _userPresetForKey(key) != null;
  }

  void _sanitizeActivePresetKeyIfStale() {
    if (_presetKeyIsValid(_activePresetKey)) return;
    _activePresetKey = PlannerPresetType.hustle.name;
  }

  String _resolvedActivePresetKey() {
    _sanitizeActivePresetKeyIfStale();
    return _activePresetKey;
  }

  List<PresetTaskLine> _linesForPresetKey(String key) {
    if (_userIdFromPresetKey(key) != null) {
      final u = _userPresetForKey(key);
      if (u != null && u.lines.isNotEmpty) return u.lines;
      return builtinPresetLinesFor(PlannerPresetType.alltag);
    }
    final t = _tryBuiltinPresetKey(key) ?? PlannerPresetType.hustle;
    return _effectivePresetLines(t);
  }

  List<TimeBlock> _buildPresetBlocksForKey(String key) =>
      _linesForPresetKey(key).map(_blockFromPresetLine).toList();

  int _nowWallClockMinutes() {
    final n = DateTime.now();
    return n.hour * 60 + n.minute;
  }

  String _displayNameForBuiltinPreset(PlannerPresetType p) {
    final raw = _builtinPresetDisplayOverrides[p]?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return _presetLabel(p);
  }

  String _displayNameForPresetKey(String key) {
    if (key == _kIndividualDayPresetKey) return 'Individuell';
    final builtin = _tryBuiltinPresetKey(key);
    if (builtin != null) return _displayNameForBuiltinPreset(builtin);
    final u = _userPresetForKey(key);
    if (u != null) {
      final n = u.name.trim();
      return n.isEmpty ? 'Eigenes Preset' : n;
    }
    return key;
  }

  String _effectiveDayPlanDropdownKey() {
    final d = _onlyDay(_selectedDate);
    final cur = _dayPlanPresetKind[d];
    if (cur == _kIndividualDayPresetKey) return _kIndividualDayPresetKey;
    if (cur != null && cur.isNotEmpty) return cur;
    final w = _presetForDate(d);
    return w?.presetKey ?? _resolvedActivePresetKey();
  }

  void _applyConfirmedPresetLines(
    String presetKey,
    List<PresetTaskLine> linesIn, {
    bool asHauptplan = false,
  }) {
    final od = _onlyDay(_selectedDate);
    _getBlocksForDay(_selectedDate);
    final list = _days[od]!;
    final todayOd = _onlyDay(DateTime.now());
    final isTodayOd = od == todayOd;

    late List<TimeBlock> merged;
    if (!isTodayOd) {
      merged = linesIn.map(_blockFromPresetLine).toList();
    } else {
      final cutoff = _nowWallClockMinutes();
      final allCompleted = list.where((b) => b.completed).toList();
      final future = _blocksFromPresetLinesAfterCutoff(cutoff, linesIn);
      // Wenn die Vorlage nur Slots vor „jetzt“ hätte (z. B. spätabends), ohne Fallback
      // keine neuen Einträge — wirkt dann wie „Lädt nicht“. In dem Fall gesamtes Raster anlegen.
      if (future.isEmpty && linesIn.isNotEmpty) {
        merged = [
          ...allCompleted,
          ...linesIn.map(_blockFromPresetLine),
        ];
      } else {
        merged = [...allCompleted, ...future];
      }
    }

    merged.sort((a, b) {
      final c = a.startMin.compareTo(b.startMin);
      if (c != 0) return c;
      final d = a.endMin.compareTo(b.endMin);
      if (d != 0) return d;
      return a.id.compareTo(b.id);
    });

    list
      ..clear()
      ..addAll(merged);
    _repairOverlapsWithPins(list);
    _repairUnpinnedLinearOverlaps(list);
    _repairOverlapsWithPins(list);

    /// Nach Repairs: Alle **komplett erledigten** Blöcke oben (nach Uhrzeit), darunter Preset/offen —
    /// unabhängig von der Tageszeit (z. B. erledigt am Nachmittag vor morgigen Preset‑Slots).
    if (isTodayOd) {
      int byStart(TimeBlock a, TimeBlock b) {
        final c = a.startMin.compareTo(b.startMin);
        if (c != 0) return c;
        final d = a.endMin.compareTo(b.endMin);
        if (d != 0) return d;
        return a.id.compareTo(b.id);
      }

      final done = list.where((b) => b.completed).toList()..sort(byStart);
      final rest = list.where((b) => !b.completed).toList()..sort(byStart);
      list
        ..clear()
        ..addAll(done)
        ..addAll(rest);
    }

    _dayPlanPresetKind[od] = presetKey;
    if (asHauptplan) {
      _activePresetKey = presetKey;
      _sanitizeActivePresetKeyIfStale();
      _presetWindows.removeWhere((w) => w.isOpenEnd);
      _presetWindows.add(
        PresetWindow(
          from: od,
          to: null,
          presetKey: presetKey,
        ),
      );
      _rewriteMaterializedDaysToHauptplan(from: od);
      unawaited(_saveActivePresetKey());
    }
    _selectedBlockIds.clear();
  }

  void _rewriteMaterializedDaysToHauptplan({required DateTime from}) {
    final start = _onlyDay(from);
    final key = _resolvedActivePresetKey();
    for (final day in _days.keys.toList()) {
      if (day.isBefore(start) || day == start) continue;
      if (_dayPlanPresetKind[day] == _kIndividualDayPresetKey) continue;
      final w = _presetForDate(day);
      if (w != null && !w.isOpenEnd) continue;
      _days[day] = _buildPresetBlocksForKey(key);
      _dayPlanPresetKind[day] = key;
    }
  }

  List<DropdownMenuItem<String>> _presetMenuItems() {
    final haupt = _resolvedActivePresetKey();
    return [
      DropdownMenuItem<String>(
        value: _kHauptplanMenuValue,
        child: Text(
          'Hauptplan · ${_displayNameForPresetKey(haupt)}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      for (final pt in PlannerPresetType.values)
        DropdownMenuItem<String>(
          value: pt.name,
          child: Text(
            _displayNameForBuiltinPreset(pt),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      for (final u in _userPresetDays)
        DropdownMenuItem<String>(
          value: 'u:${u.id}',
          child: Text(
            u.name.trim().isEmpty ? 'Eigenes Preset' : u.name.trim(),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      DropdownMenuItem<String>(
        value: _kCreatePresetMenuValue,
        child: Text(
          '+ Neues Preset erstellen',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: context.palette.text,
          ),
        ),
      ),
    ];
  }

  Future<String?> _promptAndCreateUserPreset() async {
    final nameCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final pal = ctx.palette;
          return AlertDialog(
            title: const Text('Neues Preset'),
            content: TextField(
              controller: nameCtrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Name des Presets',
              ),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Abbrechen', style: TextStyle(color: pal.muted)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Erstellen'),
              ),
            ],
          );
        },
      );
      if (ok != true || !mounted) return null;
      var name = nameCtrl.text.trim();
      if (name.isEmpty) name = 'Mein Preset';
      final id = _newUserPresetDayIdStatic();
      final fromDay = _getBlocksForDay(_selectedDate)
          .where((b) => !b.allDay)
          .map(
            (b) => PresetTaskLine(
              title: b.title.trim().isEmpty ? 'Block' : b.title.trim(),
              startMin: b.startMin,
              endMin: b.endMin,
              colorLabel: b.colorLabel,
              notes: b.notes,
            ),
          )
          .toList();
      final lines = fromDay.isNotEmpty
          ? fromDay
          : builtinPresetLinesFor(
              PlannerPresetType.alltag,
            ).map((e) => e.copy()).toList();
      final key = 'u:$id';
      setState(() {
        _userPresetDays.add(UserPresetDay(id: id, name: name, lines: lines));
      });
      await _saveUserPresetDays();
      return key;
    } finally {
      nameCtrl.dispose();
    }
  }

  Future<void> _runPresetPickAndApplyPreview(String presetKey) async {
    if (!mounted) return;
    final initial = _linesForPresetKey(presetKey).map((e) => e.copy()).toList();
    final edited = await showDialog<_PresetApplyResult>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => _PresetLoadPreviewDialog(
        title: _displayNameForPresetKey(presetKey),
        initialLines: initial,
        isTodayTarget: _onlyDay(_selectedDate) == _onlyDay(DateTime.now()),
        fmtMin: _fmtMin,
        categoryColors: Map<String, Color>.from(_categoryColors),
        hauptplanName: _displayNameForPresetKey(_resolvedActivePresetKey()),
      ),
    );
    if (edited == null || !mounted) return;
    final cleaned = edited.lines
        .map(
          (e) => e.copyWith(
            title: e.title.trim().isEmpty ? 'Block' : e.title.trim(),
          ),
        )
        .toList();
    if (cleaned.isEmpty) return;
    _recordUndoSnapshot(markSelectedDayAsIndividual: false);
    setState(
      () => _applyConfirmedPresetLines(
        presetKey,
        cleaned,
        asHauptplan: edited.asHauptplan,
      ),
    );
    _flushPersistDayPlans();
  }

  /// Mindestens eine markierte verschiebbare Zeile nötig → dann erscheinen Griffflächen
  /// an **allen** ausgewählten verschiebbaren Blöcken; Ziehen verschiebt den Chunk gemeinsam.
  int? _flexDragAnchorListIndex(List<TimeBlock> blocks) {
    if (!_flexMode || blocks.isEmpty) return null;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (_selectedBlockIds.contains(b.id) && _flexBlockAllowsDragReorder(b)) {
        return i;
      }
    }
    return null;
  }

  /// Gleiche zusammenhängende Auswahl wie beim Ablegen ([_flexDayReorderBlocks]) um [index].
  ({int start, int end}) _flexReorderChunkBounds(List<TimeBlock> blocks, int index) {
    if (blocks.isEmpty) return (start: 0, end: 0);
    if (index < 0 || index >= blocks.length) {
      final i = index.clamp(0, blocks.length - 1);
      return (start: i, end: i);
    }
    bool selDrag(int i) {
      final b = blocks[i];
      return _selectedBlockIds.contains(b.id) && _flexBlockAllowsDragReorder(b);
    }

    if (!selDrag(index)) return (start: index, end: index);
    var start = index;
    while (start > 0 && selDrag(start - 1)) {
      start--;
    }
    var end = index;
    while (end + 1 < blocks.length && selDrag(end + 1)) {
      end++;
    }
    return (start: start, end: end);
  }

  void _clearFlexReorderGhost() {
    if (_flexReorderGhostRange == null) return;
    setState(() => _flexReorderGhostRange = null);
  }

  Widget _presetDropdownForHeadline(
    BuildContext context,
    double maxPresetWidth, {
    bool compact = false,
    /// Z. B. Modalsheet schließen, bevor der Preset-Dialog angezeigt wird.
    VoidCallback? dismissHostingOverlay,
  }) {
    final p = context.palette;
    final sw = MediaQuery.sizeOf(context).width;
    final cur = _effectiveDayPlanDropdownKey();
    final String? value = cur == _kIndividualDayPresetKey
        ? null
        : (_presetKeyIsValid(cur) ? cur : _resolvedActivePresetKey());

    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 7, vertical: 4)
        : const EdgeInsets.only(left: 8, right: 4);
    final radius = compact ? 12.0 : 14.0;
    final iconSz = compact ? 17.0 : 20.0;
    final hintStyle = compact
        ? Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: sw < 380 ? 13 : 13.5,
            color: p.text,
            letterSpacing: -0.15,
          )
        : Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: p.text,
          );

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxPresetWidth),
        child: Container(
          padding: pad,
          decoration: BoxDecoration(
            color: p.hintBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: p.hairline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              borderRadius: BorderRadius.circular(compact ? 14 : 16),
              dropdownColor: p.surface,
              icon: Icon(
                Icons.expand_more_rounded,
                color: p.muted,
                size: iconSz,
              ),
              value: value,
              hint: Text(
                cur == _kIndividualDayPresetKey
                    ? 'Individuell'
                    : _displayNameForPresetKey(cur),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hintStyle,
              ),
              items: _presetMenuItems(),
              onChanged: (v) {
                if (v == null) return;
                void runPick(String key) {
                  dismissHostingOverlay?.call();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    unawaited(_runPresetPickAndApplyPreview(key));
                  });
                }

                if (v == _kCreatePresetMenuValue) {
                  unawaited(() async {
                    final key = await _promptAndCreateUserPreset();
                    if (key == null || !mounted) return;
                    runPick(key);
                  }());
                  return;
                }
                if (v == _kHauptplanMenuValue) {
                  runPick(_resolvedActivePresetKey());
                  return;
                }
                runPick(v);
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _getBlocksForDay(_selectedDate);
    final flexFocusId = _flexMode
        ? _flexModeNextIncompleteBlockId(blocks)
        : null;
    final selectedCount = blocks
        .where((b) => _selectedBlockIds.contains(b.id))
        .length;
    final doneCount = blocks.where((b) => b.completed).length;
    final totalCount = blocks.length;
    final flexDragAnchorIdx = _flexDragAnchorListIndex(blocks);
    final screenW = MediaQuery.sizeOf(context).width;
    final reminderBellBesideCalendar = screenW < 410;
    final padH = screenW < 360 ? 8.0 : (screenW < 420 ? 9.0 : 11.0);
    final listHPad = screenW < 380 ? 7.0 : 9.0;
    // Abstand Liste → untere Zeile „Ablage / +“ (einheitlich mit letztem Karten‑Abstand).
    const listBottomPad = 14.0;
    final headlineSize = screenW < 380 ? 24.0 : 28.0;
    final isViewingToday = _onlyDay(_selectedDate) == _onlyDay(DateTime.now());
    final tightPhone = screenW < 405;
    final dayLanes = _showFreeTimeLanes
        ? _clockLanesForDay(blocks)
        : [for (final b in blocks) _ClockLane.block(b)];

    return Scaffold(
      backgroundColor: context.palette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padH, 4, 4, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    isViewingToday ? 'Heute' : 'Dein Tag',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontSize: headlineSize,
                                          fontWeight: FontWeight.w800,
                                          color: context.palette.text,
                                          letterSpacing: -0.4,
                                          height: 1.05,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _dateLabel(_selectedDate),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: context.palette.muted,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: _dayGridView
                                      ? 'Als Liste anzeigen'
                                      : 'Als Zeitraster anzeigen',
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => unawaited(
                                    _setDayGridView(!_dayGridView),
                                  ),
                                  icon: Icon(
                                    _dayGridView
                                        ? Icons.view_agenda_outlined
                                        : Icons.calendar_view_day_rounded,
                                    size: 20,
                                    color: _dayGridView
                                        ? context.palette.accent
                                        : context.palette.muted,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Großen Kalender öffnen',
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed: _openBigCalendar,
                                  icon: Icon(
                                    Icons.calendar_month_rounded,
                                    size: 20,
                                    color: context.palette.muted,
                                  ),
                                ),
                                if (reminderBellBesideCalendar)
                                  IconButton(
                                    tooltip: 'Erinnerungen & Wecker',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: _openReminderPrefsSheet,
                                    icon: Icon(
                                      Icons.notifications_none_outlined,
                                      size: 20,
                                      color: context.palette.muted,
                                    ),
                                  ),
                                if (totalCount > 0)
                                  Text(
                                    '$doneCount/$totalCount',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: context.palette.muted,
                                          letterSpacing: 0.2,
                                        ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: context.palette.isDark ? 'Hell' : 'Dunkel',
                            onPressed: widget.onToggleAppearance,
                            icon: Icon(
                              context.palette.isDark
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                              size: 22,
                              color: context.palette.muted,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Rückgängig (letzte Änderung am Plan)',
                            onPressed: _undoStack.isEmpty ? null : _undoLastChange,
                            icon: Icon(
                              Icons.undo_rounded,
                              size: 22,
                              color: _undoStack.isEmpty
                                  ? context.palette.muted.withValues(alpha: 0.3)
                                  : context.palette.muted,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Mehr',
                            onPressed: _openMoreActionsSheet,
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              size: 24,
                              color: context.palette.text,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            _weekStrip(),
            _topControls(context, selectedCount, flexMode: _flexMode),
            Padding(
              padding: EdgeInsets.fromLTRB(listHPad, 4, listHPad, 6),
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: CurrentPlannerTaskCard(
                    vm: _currentTaskVmForWallClockNow(),
                    size: screenW >= 460
                        ? CurrentTaskVisualSize.medium
                        : CurrentTaskVisualSize.compact,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: (_dayGridView && !_flexMode)
                      ? _dayTimeGrid(
                          context,
                          blocks,
                          hPad: listHPad,
                          bottomPad: listBottomPad,
                        )
                      : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    cacheExtent: 400,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      listHPad,
                      4,
                      listHPad,
                      listBottomPad,
                    ),
                    itemCount: dayLanes.length,
                    onReorder: _flexDayReorderFromLanes,
                    proxyDecorator:
                        (Widget child, int index, Animation<double> ani) {
                          final a = CurvedAnimation(
                            parent: ani,
                            curve: Curves.easeOutCubic,
                          );
                          return AnimatedBuilder(
                            animation: a,
                            builder: (context, _) {
                              final t = a.value;
                              return Material(
                                elevation: 8 * t,
                                shadowColor: Colors.black38,
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: Opacity(
                                  opacity: 0.94 + 0.06 * t,
                                  child: child,
                                ),
                              );
                            },
                          );
                        },
                    itemBuilder: (context, index) {
                      final lane = dayLanes[index];
                      final pad = EdgeInsets.only(
                        bottom: index == dayLanes.length - 1
                            ? 0
                            : (_showFreeTimeLanes ? 10 : 22),
                      );
                      if (lane.isGap) {
                        return Padding(
                          key: ValueKey<String>(
                            'gap-${lane.startMin}-${lane.endMin}',
                          ),
                          padding: pad,
                          child: _freeGapCard(
                            context,
                            startMin: lane.startMin,
                            endMin: lane.endMin,
                            tightPhone: tightPhone,
                          ),
                        );
                      }
                      final block = lane.block!;
                      final selected = _selectedBlockIds.contains(block.id);
                      final flexSpotlight =
                          flexFocusId != null && block.id == flexFocusId;
                      return Padding(
                        key: ValueKey<String>(block.id),
                        padding: pad,
                        child: _blockCard(
                          context,
                          block,
                          selected,
                          flexSpotlight,
                          flexListIndex: _flexMode ? index : null,
                          flexDragAnchorIndex: flexDragAnchorIdx,
                        ),
                      );
                    },
                  ),
                ),
              ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_flexMode)
            _flexModeSelectionBar(
              context,
              blocks: blocks,
              selectedCount: selectedCount,
            ),
          _bottomBar(),
        ],
      ),
    );
  }

  /// Schwefel‑Oliv wie im Flex‑Referenz‑UI; unabhängig vom Theme‑Accent lesbar.
  static const Color _kFlexBarOlive = Color(0xFF837839);

  Widget _flexModeSelectionBar(
    BuildContext context, {
    required List<TimeBlock> blocks,
    required int selectedCount,
  }) {
    final p = context.palette;
    final hp = MediaQuery.sizeOf(context).width < 380 ? 7.0 : 9.0;
    final leftPillBg = p.isDark
        ? const Color(0xFF252528)
        : const Color(0xFFE8EAEF);
    final dividerClr = p.isDark
        ? Colors.white.withValues(alpha: 0.12)
        : p.hairline;
    final reorderable =
        blocks.where(_flexBlockAllowsDragReorder).length;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        );

    return Material(
      color: p.bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(hp, 8, hp, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: leftPillBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: p.isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : p.hairline,
                  ),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(999),
                            ),
                            onTap: selectedCount > 0 ? _clearSelection : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '$selectedCount ausgewählt',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle?.copyWith(
                                    color: _kFlexBarOlive,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        indent: 10,
                        endIndent: 10,
                        color: dividerClr,
                      ),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(999),
                            ),
                            onTap: reorderable == 0
                                ? null
                                : () => _flexSelectAllReorderable(blocks),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Alle auswählen',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: labelStyle?.copyWith(
                                    color: reorderable == 0
                                        ? p.muted.withValues(alpha: 0.45)
                                        : p.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: _kFlexBarOlive,
              borderRadius: BorderRadius.circular(999),
              elevation: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _exitFlexMode,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  child: Text(
                    'Fertig',
                    style: labelStyle?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topControls(
    BuildContext context,
    int selectedCount, {
    bool flexMode = false,
  }) {
    if (selectedCount <= 0) {
      return const SizedBox.shrink();
    }
    final sw = MediaQuery.sizeOf(context).width;
    final outer = EdgeInsets.fromLTRB(
      sw < 380 ? 8.0 : 12.0,
      4,
      sw < 380 ? 8.0 : 12.0,
      0,
    );
    final innerHoriz = sw < 380 ? 8.0 : 10.0;
    return Padding(
      padding: outer,
      child: Material(
        color: context.palette.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.palette.hairline),
            boxShadow: context.palette.cardShadows,
          ),
          padding: EdgeInsets.symmetric(horizontal: innerHoriz, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  label: Text(
                    '$selectedCount',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.palette.text,
                    ),
                  ),
                  onPressed: () {},
                ),
                const SizedBox(width: 6),
                ActionChip(
                  label: const Text('Merge'),
                  onPressed: selectedCount >= 2 && _canMergeSelection()
                      ? _mergeSelectedBlocks
                      : null,
                ),
                const SizedBox(width: 6),
                ActionChip(
                  label: const Text('+15'),
                  onPressed: () => _shiftSelectedBlocks(15),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  label: const Text('−15'),
                  onPressed: () => _shiftSelectedBlocks(-15),
                ),
                if (flexMode) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Um wie viel verschieben — Zeiger drehen',
                    child: ActionChip(
                      avatar: const Icon(Icons.schedule_rounded, size: 18),
                      label: const Text('Verschieben'),
                      onPressed: () async {
                        final d = await showFlexShiftDialSheet(context);
                        if (!context.mounted) return;
                        if (d != null && d != 0) {
                          _shiftSelectedBlocks(d);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('Auswahl lösen'),
                    onPressed: _clearSelection,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _weekStrip() {
    final monday = _selectedDate.subtract(
      Duration(days: _selectedDate.weekday - 1),
    );
    final today = _onlyDay(DateTime.now());
    final hStrip = MediaQuery.sizeOf(context).width < 380 ? 6.0 : 8.0;
    final qh = MediaQuery.sizeOf(context).height;
    final stripH = qh < 640 ? 72.0 : 80.0;
    return SizedBox(
      height: stripH,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(hStrip, 4, hStrip, 0),
        itemCount: 7,
        itemBuilder: (context, i) {
          final d = _onlyDay(monday.add(Duration(days: i)));
          final sel = _isSameDay(d, _selectedDate);
          final isToday = _isSameDay(d, today);
          final p = context.palette;
          final onWeekSel = p.isDark
              ? const Color(0xFF1A1512)
              : const Color(0xFFF8F9FB);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _pickDate(d),

                /// Leicht höher als das sichtbare Kärtchen für zuverlässigere Finger-Treffer.
                child: Ink(
                  width: 52,
                  height: stripH - 6,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    color: sel
                        ? p.weekSelected
                        : (isToday ? p.weekUnsel : Colors.transparent),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isToday && !sel
                          ? p.muted.withValues(alpha: 0.45)
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _shortWeekday(d),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? onWeekSel : p.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${d.day}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: sel ? onWeekSel : p.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openBigCalendar() async {
    var draft = _onlyDay(_selectedDate);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final p = ctx.palette;
        return AlertDialog(
          title: const Text('Kalender'),
          content: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setD) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Vergangenheit anschauen oder zukünftige Tage planen.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: p.muted),
                    ),
                    const SizedBox(height: 10),
                    CalendarDatePicker(
                      initialDate: draft,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                      currentDate: _onlyDay(DateTime.now()),
                      onDateChanged: (d) => setD(() => draft = _onlyDay(d)),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final today = _onlyDay(DateTime.now());
                _pickDate(today);
                Navigator.pop(ctx);
              },
              child: const Text('Heute'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen'),
            ),
            FilledButton(
              onPressed: () {
                _pickDate(draft);
                Navigator.pop(ctx);
              },
              child: const Text('Tag öffnen'),
            ),
          ],
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _shortWeekday(DateTime d) {
    const names = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return names[d.weekday - 1];
  }

  Widget _selectionBubble({
    required TimeBlock block,
    required bool selected,
    required Color fill,
    required Color stripe,
    required AppPalette p,
  }) {
    final bubble = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? fill : Colors.transparent,
        border: Border.all(color: selected ? stripe : p.hairline, width: 2),
      ),
      child: selected
          ? Center(child: Icon(Icons.check, size: 13, color: stripe))
          : null,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _flexMode ? () => _toggleBlockSelect(block.id) : null,
          customBorder: const CircleBorder(),

          /// Mindest-Ziel ~48×48 (Material · barrierefreie Bedienung).
          child: SizedBox(width: 48, height: 48, child: Center(child: bubble)),
        ),
      ),
    );
  }

  /// Großer Ruhebereich, wenn für den gewählten Tag noch keine Blöcke existieren.
  Widget _freiraumDayArea(BuildContext context) {
    final sw = MediaQuery.sizeOf(context).width;
    final h = sw < 380 ? 5.0 : 7.0;
    final b = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(h, 4, h, 28 + b),
      child: SizedBox.expand(child: _freiraumDayCard(context)),
    );
  }

  Widget _freiraumDayCard(BuildContext context) {
    final p = context.palette;
    final hx = MediaQuery.sizeOf(context).width < 400 ? 20.0 : 28.0;
    final vy = MediaQuery.sizeOf(context).width < 400 ? 24.0 : 32.0;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openNewBlockDialog,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: p.hairline.withValues(alpha: p.isDark ? 0.5 : 0.75),
              width: 1.1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(p.surface.withValues(alpha: 0.5), p.bg),
                Color.alphaBlend(p.hintBg.withValues(alpha: 0.65), p.bg),
              ],
            ),
            boxShadow: p.cardShadows,
          ),
          child: SizedBox.expand(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: hx, vertical: vy),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hourglass_empty_rounded,
                      size: 42,
                      color: p.muted.withValues(alpha: 0.42),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Freiraum',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                        color: p.text.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Für diesen Tag ist noch nichts eingetragen — das ist Absicht: '
                      'den Raum bewusst frei halten, oder mit + deinen ersten Block setzen.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                        color: p.muted.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Tippen zum Anlegen',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.15,
                        color: p.accent.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _freiraumBacklogArea(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: p.hairline.withValues(alpha: p.isDark ? 0.45 : 0.7),
            width: 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(p.surface.withValues(alpha: 0.4), p.bg),
              Color.alphaBlend(p.hintBg.withValues(alpha: 0.55), p.bg),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 34,
                  color: p.muted.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 14),
                Text(
                  'Ablage ist leer',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: p.text.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Alles, was du auf „Ablage“ legst, landet hier — später in den Plan ziehen.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
                    color: p.muted.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openIndividuellNotesSheet() async {
    final p = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final padBottom = MediaQuery.of(ctx).viewInsets.bottom;
        final maxH = MediaQuery.of(ctx).size.height * 0.92;
        return Padding(
          padding: EdgeInsets.only(bottom: padBottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              child: SizedBox(
                height: maxH,
                child: Container(
                  color: p.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: p.hairline,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/note_header_icon.png',
                              width: 34,
                              height: 34,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (c, e, s) => Icon(
                                Icons.edit_note_rounded,
                                size: 26,
                                color: p.accent.withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Individuell',
                                style: Theme.of(ctx).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: p.text,
                                    ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: Text(
                                'Fertig',
                                style: TextStyle(
                                  color: p.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Freier Text zu diesem Tag — Gedanken, Links, Erinnerungen, alles was du willst.',
                          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            color: p.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                          child: TextField(
                            controller: _freeformCtrl,
                            maxLines: null,
                            minLines: 10,
                            textAlignVertical: TextAlignVertical.top,
                            style: TextStyle(color: p.text, height: 1.45),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: p.bg.withValues(alpha: 0.5),
                              hintText: 'Hier eintragen …',
                              hintStyle: TextStyle(
                                color: p.muted.withValues(alpha: 0.65),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: p.hairline.withValues(alpha: 0.9),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: p.accent.withValues(alpha: 0.55),
                                ),
                              ),
                              contentPadding: const EdgeInsets.fromLTRB(
                                14,
                                14,
                                14,
                                14,
                              ),
                            ),
                            onChanged: (_) => _scheduleFreeformSave(),
                          ),
                        ),
                      ),
                      SizedBox(height: 8 + MediaQuery.of(ctx).padding.bottom),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Zeigt die Blockdauer, oder wenn der Slot gerade läuft (nur wenn der angezeigte Tag [heute] ist): „noch …“ plus Restzeit.
  String _blockDurationSubtitle(TimeBlock block) {
    if (_onlyDay(_selectedDate) != _onlyDay(DateTime.now())) {
      return _humanDuration(block.duration);
    }
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final remain = _remainingMinutesIfBlockActiveNow(block, nowMin);
    if (remain != null && remain > 0) {
      return 'noch ${_humanDuration(remain)}';
    }
    return _humanDuration(block.duration);
  }

  /// Minuten bis Blockende, wenn „jetzt“ innerhalb dieses Slots liegt; sonst `null`.
  /// Ganztags nicht: würde sonst dauerhaft mit Uhrzeit-Slots kollidieren („aktuell“).
  int? _remainingMinutesIfBlockActiveNow(TimeBlock block, int nowMin) {
    if (block.completed) return null;
    if (block.allDay) return null;
    if (block.isLinearSlot) {
      if (nowMin >= block.startMin && nowMin < block.endMin) {
        return block.endMin - nowMin;
      }
      return null;
    }
    if (block.isOvernightSlot) {
      if (nowMin >= block.startMin) {
        return (1440 - nowMin) + block.endMin;
      }
      if (nowMin < block.endMin) {
        return block.endMin - nowMin;
      }
      return null;
    }
    return null;
  }

  /// `true`, wenn die Uhrzeit gerade in diesem Block liegt (gleiche Logik wie „noch …“ in der Subtitle).
  bool _isWallClockActiveBlock(TimeBlock block) {
    if (_onlyDay(_selectedDate) != _onlyDay(DateTime.now())) {
      return false;
    }
    if (block.completed) return false;
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final remain = _remainingMinutesIfBlockActiveNow(block, nowMin);
    return remain != null && remain > 0;
  }

  /// Anteil verstrichene Zeit im Slot (0…1), nur wenn Uhrzeit im Block; für Füllung in der Block-Karte.
  double? _slotElapsedFractionWhileLive(TimeBlock block) {
    if (block.completed) return null;
    if (_onlyDay(_selectedDate) != _onlyDay(DateTime.now())) return null;
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final rem = _remainingMinutesIfBlockActiveNow(block, nowMin);
    if (rem == null || rem <= 0) return null;
    if (block.isLinearSlot) {
      final d = block.endMin - block.startMin;
      if (d <= 0) return null;
      return ((d - rem) / d).clamp(0.0, 1.0);
    }
    if (block.isOvernightSlot) {
      final total = (1440 - block.startMin) + block.endMin;
      if (total <= 0) return null;
      return ((total - rem) / total).clamp(0.0, 1.0);
    }
    return null;
  }

  ProbeBlock _probeBlockForCurrentTaskWidget(TimeBlock b) {
    return probeFromPlannerBlock(
      title: b.title,
      startMin: b.startMin,
      endMin: b.endMin,
      colorLabel: b.colorLabel,
      completed: b.completed,
      accentArgb: _stripeForBlock(b).toARGB32(),
      allDay: b.allDay,
    );
  }

  CurrentTaskViewModel _currentTaskVmForWallClockNow() {
    final n = DateTime.now();
    final probes = _getBlocksForDay(
      n,
    ).map(_probeBlockForCurrentTaskWidget).toList();
    return resolveCurrentPlannerTask(
      blocks: probes,
      todayCalendarDay: _onlyDay(n),
      now: n,
    );
  }

  Future<void> _publishCurrentTaskWidgets() async {
    if (kIsWeb) return;
    await SolHomeWidgetSync.publish(_currentTaskVmForWallClockNow());
  }

  /// Streifen-Verlauf; [clipCornerRadius] ≈ Innenkante der Karte (leicht erweitert gegen Anti-Alias-Lücken).
  /// Block liegt komplett in der Vergangenheit (→ voll gefüllt dargestellt).
  bool _isBlockPast(TimeBlock b) {
    if (b.allDay) return false;
    final now = DateTime.now();
    final today = _onlyDay(now);
    final day = _onlyDay(_selectedDate);
    if (day.isBefore(today)) return true;
    if (day.isAfter(today)) return false;
    if (!b.isLinearSlot) return false;
    return b.endMin <= now.hour * 60 + now.minute;
  }

  Widget _liveProgressStripeFill({
    required double fraction,
    required Color stripe,
    required double clipCornerRadius,
  }) {
    final r = clipCornerRadius.clamp(1.5, 20.0);
    final borderRadius = fraction >= 0.998
        ? BorderRadius.circular(r)
        : BorderRadius.only(
            topLeft: Radius.circular(r),
            topRight: Radius.circular(r),
          );
    return ClipRRect(
      borderRadius: borderRadius,
      // HardEdge sonst oft 1px dunkler Spalt neben dem Stroke an der Rundung.
      clipBehavior: Clip.hardEdge,
      child: FractionallySizedBox(
        alignment: Alignment.topCenter,
        heightFactor: fraction.clamp(0.0, 1.0),
        widthFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                stripe.withValues(alpha: 0.74),
                stripe.withValues(alpha: 0.52),
              ],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// Mindesthöhe proportional zur Slotdauer — eher linear, damit 24 h visuell
  /// vergleichbar bleiben (Lücken zählen mit).
  double _minutesToLaneHeight(int minutes, {required bool tightPhone}) {
    final ppm = tightPhone ? 0.58 : 0.68;
    final lo = tightPhone ? 36.0 : 40.0;
    return max(lo, minutes.clamp(15, 1440) * ppm);
  }

  double _blockListCardMinHeight(TimeBlock block, {required bool tightPhone}) {
    if (block.allDay) {
      return tightPhone ? 70.0 : 78.0;
    }
    var d = block.duration;
    if (d <= 0) d = 15;
    if (!_showFreeTimeLanes) {
      const refMinDur = 15;
      const refMaxDur = 300;
      final lo = tightPhone ? 52.0 : 58.0;
      final hi = tightPhone ? 128.0 : 146.0;
      d = d.clamp(refMinDur, refMaxDur);
      final lin = ((d - refMinDur) / (refMaxDur - refMinDur)).clamp(0.0, 1.0);
      return lo + sqrt(lin) * (hi - lo);
    }
    return _minutesToLaneHeight(d, tightPhone: tightPhone);
  }

  List<_ClockLane> _clockLanesForDay(List<TimeBlock> blocks) {
    final allDay = blocks.where((b) => b.allDay).toList();
    final timed = blocks.where((b) => !b.allDay).toList();
    final occupied = List<bool>.filled(1440, false);
    for (final b in timed) {
      if (b.isLinearSlot) {
        final end = b.endMin.clamp(0, 1440);
        for (var m = b.startMin.clamp(0, 1439); m < end; m++) {
          occupied[m] = true;
        }
      } else if (b.isOvernightSlot) {
        for (var m = b.startMin.clamp(0, 1439); m < 1440; m++) {
          occupied[m] = true;
        }
        for (var m = 0; m < b.endMin.clamp(0, 1440); m++) {
          occupied[m] = true;
        }
      }
    }
    final gaps = <_ClockLane>[];
    var i = 0;
    while (i < 1440) {
      if (occupied[i]) {
        i++;
        continue;
      }
      final start = i;
      while (i < 1440 && !occupied[i]) {
        i++;
      }
      if (i - start >= 15) {
        gaps.add(_ClockLane.gap(start, i));
      }
    }
    final timedLanes = [
      for (final b in timed) _ClockLane.block(b),
      ...gaps,
    ];
    timedLanes.sort((a, b) {
      final cmp = a.laneStart.compareTo(b.laneStart);
      if (cmp != 0) return cmp;
      if (a.isGap != b.isGap) return a.isGap ? 1 : -1;
      return 0;
    });
    return [
      for (final b in allDay) _ClockLane.block(b),
      ...timedLanes,
    ];
  }

  Widget _freeGapCard(
    BuildContext context, {
    required int startMin,
    required int endMin,
    required bool tightPhone,
  }) {
    final p = context.palette;
    final h = _minutesToLaneHeight(
      endMin - startMin,
      tightPhone: tightPhone,
    );
    final timeColW = tightPhone ? 44.0 : 48.0;
    final railW = tightPhone ? 28.0 : 33.0;
    final gapAfterRail = tightPhone ? 7.0 : 9.0;
    final compact = h < 64;
    final faint = p.muted.withValues(alpha: p.isDark ? 0.16 : 0.22);
    final wash = p.muted.withValues(alpha: p.isDark ? 0.028 : 0.04);
    final stroke = p.muted.withValues(alpha: p.isDark ? 0.08 : 0.12);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openNewBlockDialog(
          startMin: startMin,
          endMin: min(endMin, startMin + 60),
        ),
        borderRadius: BorderRadius.circular(16),
        child: ClipRect(
          child: SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                SizedBox(
                  width: railW,
                  child: Center(
                    child: Container(
                      width: compact ? 16 : (tightPhone ? 22 : 24),
                      height: compact ? 16 : (tightPhone ? 22 : 24),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: stroke, width: 1),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: gapAfterRail),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: wash,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: stroke),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        compact ? 6 : 10,
                        12,
                        compact ? 6 : 10,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: compact
                            ? Text(
                                'Freizeit',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: faint,
                                      height: 1.1,
                                    ),
                              )
                            : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Freizeit',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontSize: tightPhone ? 15 : 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                    color: faint,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Genieß deinen Tag',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontSize: tightPhone ? 11.5 : 12,
                                          fontWeight: FontWeight.w500,
                                          color: faint,
                                          height: 1.2,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.light_mode_outlined,
                                  size: 15,
                                  color: faint,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: timeColW,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 4,
                      top: compact ? 6 : 10,
                      bottom: compact ? 6 : 10,
                    ),
                    child: compact
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              _fmtMin(startMin),
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: faint,
                                    height: 1,
                                  ),
                            ),
                          )
                        : Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _fmtMin(startMin),
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontSize: tightPhone ? 11.5 : 12,
                                  fontWeight: FontWeight.w700,
                                  color: faint,
                                  height: 1,
                                ),
                          ),
                          Text(
                            endMin >= 1440 ? '24:00' : _fmtMin(endMin),
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontSize: tightPhone ? 10.5 : 11,
                                  fontWeight: FontWeight.w500,
                                  color: faint,
                                  height: 1,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _blockCard(
    BuildContext context,
    TimeBlock block,
    bool selected,
    bool flexSpotlight, {
    int? flexListIndex,
    int? flexDragAnchorIndex,
    VoidCallback? onFlexDragHandlePointerDown,
    bool suppressFlexDragHandle = false,
  }) {
    final p = context.palette;
    final isLiveNow = _isWallClockActiveBlock(block);
    _SessionLiveProgress? liveSessionProg;
    if (block.sessionSegments.isNotEmpty &&
        isLiveNow &&
        block.isLinearSlot &&
        !block.completed) {
      liveSessionProg = _sessionLiveProgress(block);
    }
    final highlightCard = selected || flexSpotlight || isLiveNow;
    final sw = MediaQuery.sizeOf(context).width;
    final tightPhone = sw < 405;
    final timeColW = tightPhone ? 30.0 : 34.0;
    final railW = tightPhone ? 25.0 : 29.0;
    final gapAfterRail = tightPhone ? 3.0 : 4.0;
    /// Digitale Zeitspur vor dem Icon-Rail; Darstellung linksbündig in dieser Zone,
    /// damit sie optisch weiter von den Symbolen entfernt sitzt als bei reiner Mittelteilung.
    final timeBandW = timeColW + gapAfterRail;
    /// Abstand Liste → erste Inhalts-Spalte (Breite des Zeit+Rail-Clusters).
    final leadingTimeGutterPx = !_flexMode ? 2.0 : 0.0;
    final mealVis = _useMealVisualFor(block);
    final openFreizeitSlot =
        !mealVis && _isFreizeitOffenPlaceholderTitle(block.title);
    final stripe = _stripeForBlock(block);
    final fill = stripe.withValues(alpha: p.stripeFillAlpha);
    final lineClr = p.hairline.withValues(alpha: p.isDark ? 0.65 : 0.85);
    final durLabel = _blockDurationSubtitle(block);
    final expanded = _expandedBlockIds.contains(block.id);
    final subDone = block.subtasks.where((s) => s.done).length;
    final subTotal = block.subtasks.length;
    final deepTodos = _blockShowsRolledDeepWorkTodos(block)
        ? _openDeepWorkTodos()
        : const <DeepWorkTodoItem>[];
    final deepTodoCount = deepTodos.length;
    // Vergangene Blöcke sind komplett gefüllt, der laufende anteilig; Schein nur beim laufenden.
    final pastFilled = !isLiveNow && _isBlockPast(block);
    final liveFillFrac = isLiveNow
        ? _slotElapsedFractionWhileLive(block)
        : (pastFilled ? 1.0 : null);
    final activeLiveForeground = (isLiveNow || pastFilled) && !mealVis;
    // Zeitspalte + Icon-Leiste liegen außerhalb der Füllung: nur der laufende Block wird hervorgehoben.
    final railLive = isLiveNow && !mealVis;
    final liveLightUi = activeLiveForeground && !p.isDark;
    /// Nur lesen wenn [activeLiveForeground] — sonst [Colors.transparent] (Dummy).
    final Color liveInk =
        activeLiveForeground ? (liveLightUi ? p.text : Colors.white) : Colors.transparent;
    final Color liveSoft = activeLiveForeground
        ? (liveLightUi
            ? p.muted.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.92))
        : Colors.transparent;

    final liveBorderPx = highlightCard ? (isLiveNow ? 2.35 : 1.85) : 1.4;
    // Innenradius ~ R−Stroke, etwas Überstand: Anti-Alias lässt sonst einen dünnen Spalt zwischen Rand und Streifen.
    final innerClipRadiusLive = !mealVis
        ? ((14.0 - liveBorderPx) + 1.05).clamp(6.5, 13.4)
        : 14.0;

    final Color borderLine = mealVis
        ? MealBlockTheme.outline.withValues(
            alpha: highlightCard ? (isLiveNow ? 0.92 : 0.68) : 0.52,
          )
        : stripe.withValues(
            alpha: highlightCard ? (isLiveNow ? 0.92 : 0.88) : 0.66,
          );
    final Color glowBase = mealVis ? MealBlockTheme.shadowGlow : stripe;
    final tp = Theme.of(context).platform;
    final mobilePerf = tp == TargetPlatform.iOS || tp == TargetPlatform.android;
    /// 0 = normal, 1 = ausgewählt / Spotlight, 2 = gerade aktiv (Wallclock).
    final glowTier = isLiveNow ? 2 : (highlightCard ? 1 : 0);
    final List<BoxShadow> liveOuterGlow = glowTier == 2
        ? [
            BoxShadow(
              color: glowBase.withValues(alpha: p.isDark ? 0.65 : 0.42),
              blurRadius: 28,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: glowBase.withValues(alpha: p.isDark ? 0.38 : 0.22),
              blurRadius: 44,
              spreadRadius: -8,
              offset: Offset.zero,
            ),
            BoxShadow(
              color: p.accent.withValues(alpha: p.isDark ? 0.32 : 0.18),
              blurRadius: 20,
              spreadRadius: -4,
              offset: const Offset(0, 2),
            ),
          ]
        : glowTier == 1
        ? [
            BoxShadow(
              color: glowBase.withValues(alpha: p.isDark ? 0.44 : 0.30),
              blurRadius: 24,
              spreadRadius: 1,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: glowBase.withValues(alpha: p.isDark ? 0.28 : 0.16),
              blurRadius: 38,
              spreadRadius: -7,
              offset: Offset.zero,
            ),
            BoxShadow(
              color: p.accent.withValues(alpha: p.isDark ? 0.22 : 0.13),
              blurRadius: 17,
              spreadRadius: -3,
              offset: const Offset(0, 2),
            ),
          ]
        : const <BoxShadow>[];
    final List<BoxShadow> rim = [
      ...liveOuterGlow,
      if (mobilePerf)
        BoxShadow(
          color: glowBase.withValues(
            alpha: p.isDark
                ? (glowTier >= 2
                      ? 0.28
                      : glowTier >= 1
                      ? 0.22
                      : 0.16)
                : (glowTier >= 2
                      ? 0.14
                      : glowTier >= 1
                      ? 0.11
                      : 0.07),
          ),
          blurRadius: glowTier >= 2 ? 12 : (glowTier >= 1 ? 8 : 5),
          offset: const Offset(0, 1.5),
        )
      else ...[
        BoxShadow(
          color: glowBase.withValues(
            alpha: p.isDark
                ? (glowTier >= 2
                      ? 0.38
                      : glowTier >= 1
                      ? 0.35
                      : 0.32)
                : (glowTier >= 2
                      ? 0.2
                      : glowTier >= 1
                      ? 0.16
                      : 0.12),
          ),
          blurRadius: glowTier >= 2 ? 14 : (glowTier >= 1 ? 12 : 10),
          spreadRadius: 0,
          offset: Offset.zero,
        ),
        BoxShadow(
          color: glowBase.withValues(
            alpha: p.isDark
                ? (glowTier >= 2
                      ? 0.24
                      : glowTier >= 1
                      ? 0.20
                      : 0.16)
                : (glowTier >= 2
                      ? 0.12
                      : glowTier >= 1
                      ? 0.09
                      : 0.06),
          ),
          blurRadius: glowTier >= 2 ? 22 : (glowTier >= 1 ? 20 : 18),
          spreadRadius: glowTier >= 2 ? 0 : -1,
          offset: const Offset(0, 2),
        ),
      ],
    ];
    final List<BoxShadow> cardDropShadows = openFreizeitSlot
        ? const <BoxShadow>[]
        : [
            ...rim,
            if (!mobilePerf && p.cardShadows != null) ...p.cardShadows!,
          ];
    final Color slotGreyFill = Color.alphaBlend(
      p.muted.withValues(alpha: p.isDark ? 0.30 : 0.24),
      p.surface,
    );
    final Color slotGreyBorder =
        p.muted.withValues(alpha: p.isDark ? 0.72 : 0.62);
    final Color cardEdgeColor = openFreizeitSlot ? slotGreyBorder : borderLine;
    final Color railLineClr =
        openFreizeitSlot ? p.muted.withValues(alpha: 0.52) : lineClr;
    final Color railIconFg = railLive
        ? liveInk
        : (openFreizeitSlot
              ? p.muted.withValues(alpha: 0.52)
              : stripe.withValues(alpha: mealVis ? 0.86 : 0.92));

    void cardPrimaryTap() {
      if (_flexMode) {
        _toggleBlockSelect(block.id);
      } else if (_isProjectSessionBlock(block)) {
        unawaited(_openProjectSessionSheet(block));
      } else {
        _openEditBlockDialog(block);
      }
    }

    final flexColW = tightPhone ? 29.0 : 33.0;
    final showFlexDragCol = flexListIndex != null;
    final flexDragActivated = flexDragAnchorIndex != null;
    final showDragHandle =
        !suppressFlexDragHandle &&
        showFlexDragCol &&
        selected &&
        flexDragActivated &&
        _flexBlockAllowsDragReorder(block);

    final cardListMinHeight = _blockListCardMinHeight(
      block,
      tightPhone: tightPhone,
    );

    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: cardListMinHeight),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_flexMode)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _selectionBubble(
                    block: block,
                    selected: selected,
                    fill: fill,
                    stripe: stripe,
                    p: p,
                  ),
                ),
              SizedBox(
                width: leadingTimeGutterPx + timeBandW + railW,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: cardPrimaryTap,
                          onLongPress: _flexMode
                              ? () => _openEditBlockDialog(block)
                              : null,
                          splashColor: p.muted.withValues(alpha: 0.14),
                          highlightColor: p.muted.withValues(alpha: 0.06),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 10,
                              bottom: 10,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _fmtMin(block.startMin),
                                    textAlign: TextAlign.left,
                                    style: Theme.of(context).textTheme.labelMedium
                                        ?.copyWith(
                                          fontSize: tightPhone ? 11 : 11.5,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0,
                                          color: railLive
                                              ? liveInk
                                              : p.muted,
                                          height: 1,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _fmtMin(block.endMin),
                                    textAlign: TextAlign.left,
                                    style: Theme.of(context).textTheme.labelSmall
                                        ?.copyWith(
                                          fontSize: tightPhone ? 10 : 10.5,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                          fontWeight: FontWeight.w500,
                                          color: railLive
                                              ? liveSoft
                                              : p.muted.withValues(alpha: 0.75),
                                          height: 1,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: railW,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: cardPrimaryTap,
                          onLongPress: _flexMode
                              ? () => _openEditBlockDialog(block)
                              : null,
                          splashColor: stripe.withValues(alpha: 0.15),
                          highlightColor: stripe.withValues(alpha: 0.08),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: isLiveNow ? 2.5 : 1.5,
                                  decoration: BoxDecoration(
                                    color: openFreizeitSlot
                                        ? railLineClr
                                        : (isLiveNow
                                              ? stripe.withValues(alpha: 0.92)
                                              : lineClr),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: tightPhone ? 4 : 5,
                                  ),
                                  child: Container(
                                    constraints: BoxConstraints(
                                      minHeight: tightPhone ? 40 : 44,
                                      minWidth: tightPhone ? 32 : 36,
                                    ),
                                    decoration: BoxDecoration(
                                      color: railLive
                                          ? (liveLightUi
                                              ? stripe.withValues(alpha: 0.14)
                                              : Colors.white.withValues(alpha: 0.12))
                                          : openFreizeitSlot
                                              ? p.muted.withValues(alpha: 0.08)
                                              : p.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: railLive
                                            ? (liveLightUi
                                                ? stripe.withValues(alpha: 0.72)
                                                : Colors.white.withValues(alpha: 0.82))
                                            : openFreizeitSlot
                                                ? slotGreyBorder
                                                : p.hairline.withValues(alpha: 0.95),
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      _resolveBlockIcon(block),
                                      size: tightPhone ? 18 : 20,
                                      color: railIconFg,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: gapAfterRail),
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: openFreizeitSlot
                          ? slotGreyFill
                          : mealVis
                          ? (glowTier >= 2
                              ? Color.alphaBlend(
                                  MealBlockTheme.shadowGlow.withValues(
                                    alpha: p.isDark ? 0.11 : 0.09,
                                  ),
                                  p.surface,
                                )
                              : glowTier >= 1
                              ? MealBlockTheme.shadowGlow.withValues(
                                  alpha: p.isDark ? 0.14 : 0.12,
                                )
                              : Color.alphaBlend(
                                  MealBlockTheme.fillBase.withValues(
                                    alpha: MealBlockTheme.cardFillAlpha,
                                  ),
                                  p.surface,
                                ))
                        : (isLiveNow && !mealVis)
                        ? Color.alphaBlend(
                            stripe.withValues(
                              alpha:
                                  liveLightUi ? 0.28 : (p.isDark ? 0.1 : 0.09),
                            ),
                            p.surface,
                          )
                        : highlightCard
                        ? stripe.withValues(alpha: isLiveNow ? 0.26 : 0.14)
                        : Color.alphaBlend(fill, p.surface),
                    border: Border.all(
                      color: cardEdgeColor,
                      width: openFreizeitSlot
                          ? (highlightCard ? 2.08 : 2.02)
                          : (highlightCard
                                ? (isLiveNow ? 2.35 : 1.85)
                                : 1.4),
                    ),
                    boxShadow: cardDropShadows,
                  ),
                  child: Stack(
                    fit: StackFit.passthrough,
                    clipBehavior: Clip
                        .antiAlias, // Progress-Füllung an Kartenrundung koppeln
                    children: [
                      if (liveFillFrac != null && liveFillFrac > 0.001)
                        Positioned.fill(
                          child: _liveProgressStripeFill(
                            fraction: liveFillFrac.clamp(0.0, 1.0),
                            stripe:
                                openFreizeitSlot ? p.muted : stripe,
                            clipCornerRadius: innerClipRadiusLive,
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          tightPhone ? 5 : 7,
                          tightPhone ? 9 : 10,
                          tightPhone ? 4 : 6,
                          tightPhone ? 9 : 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Tooltip(
                                  message: block.completed
                                      ? 'Als offen markieren (${block.colorLabel})'
                                      : 'Als erledigt abhaken (${block.colorLabel})',
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () {
                                        setState(() {
                                          block.completed = !block.completed;
                                          _dayPlanPresetKind[_onlyDay(
                                                _selectedDate,
                                              )] =
                                              _kIndividualDayPresetKey;
                                        });
                                        _syncProjectRotationForBlock(block);
                                        _schedulePersistDayPlans();
                                      },
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Center(
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: activeLiveForeground
                                                    ? (block.completed
                                                          ? liveInk.withValues(
                                                              alpha:
                                                                  liveLightUi
                                                                  ? 0.42
                                                                  : 0.45,
                                                            )
                                                          : liveLightUi
                                                          ? stripe
                                                              .withValues(
                                                                alpha:
                                                                    0.9,
                                                              )
                                                          : Colors.white)
                                                    : (block.completed
                                                          ? p.text.withValues(
                                                              alpha: 0.4,
                                                            )
                                                          : (openFreizeitSlot
                                                                ? slotGreyBorder
                                                                : stripe)),
                                                width: block.completed
                                                    ? 2.1
                                                    : 2,
                                              ),
                                              color: block.completed
                                                  ? (activeLiveForeground
                                                        ? liveInk.withValues(
                                                            alpha:
                                                                liveLightUi
                                                                ? 0.12
                                                                : 0.18,
                                                          )
                                                        : p.text.withValues(
                                                            alpha: 0.1,
                                                          ))
                                                  : activeLiveForeground
                                                  ? liveLightUi
                                                        ? stripe.withValues(
                                                              alpha:
                                                                  0.22,
                                                            )
                                                        : Colors.white.withValues(
                                                            alpha:
                                                                0.2,
                                                          )
                                                  : openFreizeitSlot
                                                      ? p.muted.withValues(
                                                          alpha:
                                                              highlightCard
                                                                  ? 0.16
                                                                  : 0.06,
                                                        )
                                                      : stripe.withValues(
                                                          alpha:
                                                              highlightCard
                                                                  ? 0.28
                                                                  : 0.08,
                                                        ),
                                            ),
                                            child: block.completed
                                                ? Icon(
                                                    Icons.check_rounded,
                                                    size: 14,
                                                    color:
                                                        activeLiveForeground
                                                        ? liveInk
                                                        : p.text,
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                PopupMenuButton<String>(
                                  padding: EdgeInsets.zero,
                                  splashRadius: 23,
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  icon: Icon(
                                    Icons.more_horiz,
                                    color:
                                        activeLiveForeground ? liveInk : p.muted,
                                    size: 22,
                                  ),
                                  color: p.surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: p.hairline),
                                  ),
                                  onSelected: (v) {
                                    switch (v) {
                                      case 'pin':
                                        _togglePin(block);
                                        break;
                                      case 'split':
                                        _splitBlock(block);
                                        break;
                                      case 'copy':
                                        _duplicateBlock(block);
                                        break;
                                      case 'edit':
                                        _openEditBlockDialog(block);
                                        break;
                                      case 'inbox':
                                        _moveToBacklog(block);
                                        break;
                                    }
                                  },
                                  itemBuilder: (c) => [
                                    PopupMenuItem(
                                      value: 'pin',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          block.pinned
                                              ? Icons.push_pin
                                              : Icons.push_pin_outlined,
                                          size: 20,
                                        ),
                                        title: Text(
                                          block.pinned
                                              ? 'Fixierung lösen'
                                              : 'Block fixieren',
                                        ),
                                        dense: true,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'split',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.call_split,
                                          size: 20,
                                        ),
                                        title: Text('Teilen'),
                                        dense: true,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'copy',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.copy, size: 20),
                                        title: Text('Duplizieren'),
                                        dense: true,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.edit_outlined,
                                          size: 20,
                                        ),
                                        title: Text('Bearbeiten'),
                                        dense: true,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'inbox',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.inbox_outlined,
                                          size: 20,
                                        ),
                                        title: Text('Ablage'),
                                        dense: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: cardPrimaryTap,
                                    onLongPress: _flexMode
                                        ? () => _openEditBlockDialog(block)
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 0,
                                        right: 2,
                                        top: 2,
                                        bottom: 4,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  block.title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        fontSize: tightPhone
                                                            ? 15
                                                            : 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: -0.25,
                                                        color:
                                                            activeLiveForeground
                                                            ? (block.completed
                                                                  ? liveInk
                                                                      .withValues(
                                                                        alpha:
                                                                            0.55,
                                                                      )
                                                                  : liveInk)
                                                            : openFreizeitSlot
                                                                  ? (block
                                                                          .completed
                                                                      ? p.muted
                                                                      .withValues(
                                                                        alpha:
                                                                            0.4,
                                                                      )
                                                                      : p.muted
                                                                          .withValues(
                                                                        alpha:
                                                                            0.58,
                                                                      ))
                                                                  : (block
                                                                          .completed
                                                                      ? p.muted
                                                                      .withValues(
                                                                        alpha:
                                                                            0.55,
                                                                      )
                                                                      : p.text),
                                                        height: 1.25,
                                                        decoration:
                                                            block.completed
                                                            ? TextDecoration
                                                                  .lineThrough
                                                            : null,
                                                        decorationColor:
                                                            activeLiveForeground
                                                                ? liveInk
                                                                    .withValues(
                                                                      alpha:
                                                                          0.5,
                                                                    )
                                                                : p.muted,
                                                      ),
                                                ),
                                              ),
                                              if (block.pinned)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 6,
                                                      ),
                                                  child: Tooltip(
                                                    message:
                                                        'Fixiert — beim Verschieben anderer stabil',
                                                    child: Icon(
                                                      Icons
                                                          .lock_outline_rounded,
                                                      size: 17,
                                                      color:
                                                          activeLiveForeground
                                                          ? liveInk
                                                          : p.muted.withValues(
                                                              alpha: 0.95,
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            deepTodoCount > 0
                                                ? '${block.colorLabel} · $durLabel · $deepTodoCount To-do${deepTodoCount == 1 ? '' : 's'}'
                                                : '${block.colorLabel} · $durLabel',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontSize: tightPhone
                                                      ? 11.5
                                                      : 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: activeLiveForeground
                                                      ? (block.completed
                                                            ? liveInk.withValues(
                                                                alpha:
                                                                    liveLightUi
                                                                    ? 0.48
                                                                    : 0.5,
                                                              )
                                                            : liveInk)
                                                      : openFreizeitSlot
                                                            ? p.muted.withValues(
                                                                alpha:
                                                                    block.completed
                                                                    ? 0.38
                                                                    : 0.45,
                                                              )
                                                            : (block.completed
                                                                  ? p.muted
                                                                      .withValues(
                                                                    alpha:
                                                                        0.5,
                                                                  )
                                                                  : p.muted),
                                                  height: 1.25,
                                                  decoration: block.completed
                                                      ? TextDecoration
                                                            .lineThrough
                                                      : null,
                                                  decorationColor:
                                                      activeLiveForeground
                                                      ? liveInk.withValues(
                                                          alpha:
                                                              liveLightUi
                                                              ? 0.45
                                                              : 0.55,
                                                        )
                                                      : p.muted,
                                                ),
                                          ),
                                          if (_isProjectSessionBlock(block)) ...[
                                            const SizedBox(height: 7),
                                            _projectNextChip(
                                              context,
                                              block,
                                              activeLiveForeground
                                                  ? liveInk
                                                  : null,
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          if (liveSessionProg != null) ...[
                                            BlockSessionLiveStrip(
                                              segments: block.sessionSegments,
                                              segmentIndex:
                                                  liveSessionProg.segmentIndex,
                                              phaseStartedAt:
                                                  liveSessionProg.phaseStartedAt,
                                              onAdvance: () =>
                                                  _advanceSessionLive(block),
                                              onReset: () =>
                                                  _resetSessionLive(block),
                                              activeForeground:
                                                  activeLiveForeground,
                                              inkWhenActive:
                                                  activeLiveForeground
                                                      ? liveInk
                                                      : null,
                                              softWhenActive:
                                                  activeLiveForeground
                                                      ? liveSoft
                                                      : null,
                                              stripeColor: openFreizeitSlot
                                                  ? p.muted
                                                  : stripe,
                                              mutedColor: activeLiveForeground
                                                  ? liveSoft
                                                  : p.muted,
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              if (block.recurrence !=
                                                  BlockRecurrence.none)
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.repeat_rounded,
                                                      size: 14,
                                                      color:
                                                          activeLiveForeground
                                                          ? liveInk
                                                          : p.muted.withValues(
                                                              alpha: 0.85,
                                                            ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      _blockRecurrenceSummary(
                                                        block,
                                                      ),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            fontSize: 11.5,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                activeLiveForeground
                                                                ? liveInk
                                                                : p.muted,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              if (subTotal > 0)
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.checklist_rounded,
                                                      size: 14,
                                                      color:
                                                          activeLiveForeground
                                                          ? liveInk
                                                          : p.muted.withValues(
                                                              alpha: 0.85,
                                                            ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '$subDone/$subTotal',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            fontSize: 11.5,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color:
                                                                activeLiveForeground
                                                                ? liveInk
                                                                : p.muted,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              if (block.notes.trim().isNotEmpty)
                                                Icon(
                                                  Icons.notes_rounded,
                                                  size: 15,
                                                  color: activeLiveForeground
                                                      ? liveInk
                                                      : p.muted.withValues(
                                                          alpha: 0.85,
                                                        ),
                                                ),
                                              if (subTotal > 0 ||
                                                  deepTodoCount > 0)
                                                InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      if (expanded) {
                                                        _expandedBlockIds
                                                            .remove(block.id);
                                                      } else {
                                                        _expandedBlockIds.add(
                                                          block.id,
                                                        );
                                                      }
                                                    });
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: SizedBox(
                                                    width: 44,
                                                    height: 40,
                                                    child: Center(
                                                      child: Icon(
                                                        expanded
                                                            ? Icons
                                                                  .expand_less_rounded
                                                            : Icons
                                                                  .expand_more_rounded,
                                                        size: 22,
                                                        color:
                                                            activeLiveForeground
                                                            ? liveInk
                                                            : p.muted,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (expanded && deepTodoCount > 0) ...[
                                            const SizedBox(height: 10),
                                            Text(
                                              'To do List',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.2,
                                                    color: activeLiveForeground
                                                        ? Colors.white
                                                              .withValues(
                                                                alpha: 0.78,
                                                              )
                                                        : p.muted,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            ...deepTodos.take(8).map(
                                              (item) => Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 6,
                                                ),
                                                child: InkWell(
                                                  onTap: () =>
                                                      unawaited(
                                                        _toggleDeepWorkTodo(
                                                          item,
                                                          !item.done,
                                                        ),
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Icon(
                                                        item.done
                                                            ? Icons
                                                                  .check_box_rounded
                                                            : Icons
                                                                  .check_box_outline_blank_rounded,
                                                        size: 17,
                                                        color:
                                                            activeLiveForeground
                                                            ? Colors.white
                                                            : p.muted,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          item.title,
                                                          style:
                                                              Theme.of(
                                                                    context,
                                                                  )
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    fontSize:
                                                                        13,
                                                                    height:
                                                                        1.35,
                                                                    decoration:
                                                                        item.done
                                                                        ? TextDecoration
                                                                              .lineThrough
                                                                        : null,
                                                                    color:
                                                                        activeLiveForeground
                                                                        ? Colors
                                                                              .white
                                                                        : p.text.withValues(
                                                                            alpha:
                                                                                0.92,
                                                                          ),
                                                                  ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (deepTodoCount > 8)
                                              Text(
                                                '+${deepTodoCount - 8} weitere',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color:
                                                          activeLiveForeground
                                                          ? Colors.white
                                                                .withValues(
                                                                  alpha: 0.7,
                                                                )
                                                          : p.muted,
                                                    ),
                                              ),
                                          ],
                                          if (expanded && subTotal > 0) ...[
                                            const SizedBox(height: 10),
                                            ...block.subtasks
                                                .take(8)
                                                .map(
                                                  (s) => Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 6,
                                                        ),
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Icon(
                                                          s.done
                                                              ? Icons
                                                                    .check_box_rounded
                                                              : Icons
                                                                    .check_box_outline_blank_rounded,
                                                          size: 17,
                                                          color:
                                                              activeLiveForeground
                                                              ? liveInk
                                                              : p.muted,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            s.title,
                                                            style: Theme.of(context)
                                                                .textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                                  fontSize: 13,
                                                                  height: 1.35,
                                                                  color:
                                                                      activeLiveForeground
                                                                      ? liveInk
                                                                      : p.text.withValues(
                                                                          alpha:
                                                                              0.92,
                                                                        ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showFlexDragCol)
                SizedBox(
                  width: flexColW,
                  child: Center(
                    child: showDragHandle
                        ? Tooltip(
                            message:
                                'Ziehen — alle markierten verschiebbaren Blöcke wandern zusammen '
                                '(dazwischen liegende werden mit markiert).',
                            child: Listener(
                              behavior: HitTestBehavior.deferToChild,
                              onPointerDown: (_) =>
                                  onFlexDragHandlePointerDown?.call(),
                              child: ReorderableDragStartListener(
                                index: flexListIndex,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    size: tightPhone ? 22 : 24,
                                    color:
                                        activeLiveForeground ? liveInk : p.muted.withValues(alpha: 0.88),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final hp = MediaQuery.sizeOf(context).width < 380 ? 7.0 : 9.0;
    final p = context.palette;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    Widget addChip() {
      return Tooltip(
        message: 'Neuer Block',
        child: Material(
          color: p.surface,
          elevation: kIsWeb ? 1 : 2.5,
          shadowColor: Colors.black38,
          shape: CircleBorder(side: BorderSide(color: p.hairline, width: 1)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _openNewBlockDialog,
            customBorder: const CircleBorder(),
            splashColor: p.accent.withValues(alpha: 0.14),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.add_rounded, size: 26, color: p.text),
            ),
          ),
        ),
      );
    }

    return Material(
      color: p.surface,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.hairline)),
        ),
        padding: EdgeInsets.fromLTRB(hp, 6, hp, 6 + safeBottom),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.text,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _openBacklogSheet,
                icon: const Icon(Icons.inbox_outlined, size: 20),
                label: Text(
                  'Ablage (${_backlog.length})',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            SizedBox(width: hp < 10 ? 6 : 8),
            Expanded(
              child: Tooltip(
                message: 'Preset wählen, Flex‑Modus, Preset-Raster',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.text,
                    side: BorderSide(color: p.hairline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _openPlannerModeSheet,
                  icon: const Icon(Icons.apps_rounded, size: 20),
                  label: Text(
                    'Modus',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: hp < 10 ? 10 : 12),
            addChip(),
          ],
        ),
      ),
    );
  }

  void _ensureDayExists(DateTime date) {
    final day = _onlyDay(date);
    if (_days.containsKey(day)) return;

    final window = _presetForDate(day);
    final presetKey = window?.presetKey ?? _resolvedActivePresetKey();
    _days[day] = _buildPresetBlocksForKey(presetKey);
    _dayPlanPresetKind.putIfAbsent(day, () => presetKey);
  }

  /// Erste noch nicht erledigte Aufgabe des Tages (gleiche Sortierung wie die Liste).
  String? _flexModeNextIncompleteBlockId(List<TimeBlock> sortedDayBlocks) {
    for (final b in sortedDayBlocks) {
      if (!b.completed) return b.id;
    }
    return null;
  }

  /// Nur lineare Zeitblöcke ohne Fixierung; Ganztags/Über‑Nacht nicht per Griff sortieren.
  bool _flexBlockAllowsDragReorder(TimeBlock b) =>
      b.isLinearSlot && !b.pinned && !b.allDay && !b.isOvernightSlot;

  /// Zwischen kleinstem und größtem Index markierter verschiebbarer Blöcke auch die
  /// übrigen (nicht-fixierten) linearen Slots markieren — damit liegt ein durchgehender
  /// Chunk vor und lässt sich gemeinsam per Griff verschieben.
  void _stretchFlexReorderSelectionInPlace(List<TimeBlock> day) {
    if (!_flexMode || _selectedBlockIds.length < 2) return;
    final idx = <int>[];
    for (var i = 0; i < day.length; i++) {
      final b = day[i];
      if (_selectedBlockIds.contains(b.id) && _flexBlockAllowsDragReorder(b)) {
        idx.add(i);
      }
    }
    if (idx.length < 2) return;
    final lo = idx.first;
    final hi = idx.last;
    for (var j = lo; j <= hi; j++) {
      final b = day[j];
      if (_flexBlockAllowsDragReorder(b)) {
        _selectedBlockIds.add(b.id);
      }
    }
  }

  /// Nach manueller Listen-Reihenfolge neue Start-/Endzeiten setzen, damit Sortierung der Liste konsistent wird.
  void _repackDayAfterFlexReorder(List<TimeBlock> ordered) {
    const minDur = 15;
    if (ordered.isEmpty) return;

    var cursor = ordered
        .map((e) => e.startMin)
        .fold<int>(ordered.first.startMin, (a, b) => a < b ? a : b)
        .clamp(0, 1439);

    for (final b in ordered) {
      if (b.allDay) continue;
      if (!b.isLinearSlot) continue;
      if (b.isOvernightSlot) continue;

      if (b.pinned) {
        final ps = b.startMin;
        final pe = b.endMin;
        if (cursor >= ps && cursor < pe) cursor = pe;
        continue;
      }

      final space = 1440 - cursor;
      if (space < minDur) break;
      final durRaw = b.duration.clamp(minDur, 1440);
      final dur = durRaw.clamp(minDur, space);

      b.startMin = cursor;
      var endMin = cursor + dur;
      if (endMin > 1440) endMin = 1440;
      if (endMin - b.startMin < minDur) {
        endMin = (b.startMin + minDur).clamp(0, 1440);
      }
      b.endMin = endMin;
      cursor = b.endMin;
      if (cursor >= 1440) break;
    }
  }

  /// Gleiche Reihenfolge wie in der Liste / [ReorderableListView] ([_getBlocksForDay] sortiert ebenso).
  void _sortBlocksChronologically(List<TimeBlock> list) {
    list.sort((a, b) {
      final c = a.startMin.compareTo(b.startMin);
      if (c != 0) return c;
      final d = a.endMin.compareTo(b.endMin);
      if (d != 0) return d;
      return a.id.compareTo(b.id);
    });
  }

  /// [newIndex] = Flutter-[ReorderCallback], Ziel vor Element `newIndex` bei noch enthaltener Ursprungsliste (ein Element gezogen). Nach Entfernen von [start…start+k−1] den Einfügeindex für denselben Platz wie bei Einzelelement ermitteln.
  int _flexChunkInsertDestAfterRemovingChunk({
    required int newIndex,
    required int chunkStart,
    required int chunkLen,
  }) {
    assert(chunkLen >= 1);
    if (newIndex <= chunkStart) {
      return newIndex;
    }
    if (newIndex >= chunkStart + chunkLen) {
      return newIndex - chunkLen;
    }
    return chunkStart;
  }

  void _flexDayReorderFromLanes(int oldIndex, int newIndex) {
    if (!_flexMode) return;
    final lanes = _clockLanesForDay(_getBlocksForDay(_selectedDate));
    if (oldIndex < 0 || oldIndex >= lanes.length) return;
    if (lanes[oldIndex].isGap) return;
    var n = 0;
    for (var i = 0; i < oldIndex; i++) {
      if (!lanes[i].isGap) n++;
    }
    var dest = 0;
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    for (var i = 0; i < insertAt && i < lanes.length; i++) {
      if (!lanes[i].isGap) dest++;
    }
    _flexDayReorderBlocks(n, dest);
  }

  void _flexDayReorderBlocks(int oldIndex, int newIndex) {
    if (!_flexMode) return;
    final dk = _onlyDay(_selectedDate);
    _ensureDayExists(_selectedDate);
    final list = _days[dk]!;
    // Nach ±15 ohne Neu-Sort können Index und Eintrag auseinanderlaufen → stiller Abbruch.
    _sortBlocksChronologically(list);
    if (oldIndex < 0 || oldIndex >= list.length) return;

    final moved = list[oldIndex];
    if (!_selectedBlockIds.contains(moved.id)) return;
    if (!_flexBlockAllowsDragReorder(moved)) return;

    bool selDrag(int i) {
      final b = list[i];
      return _selectedBlockIds.contains(b.id) && _flexBlockAllowsDragReorder(b);
    }

    var start = oldIndex;
    while (start > 0 && selDrag(start - 1)) {
      start--;
    }
    var end = oldIndex;
    while (end + 1 < list.length && selDrag(end + 1)) {
      end++;
    }
    final k = end - start + 1;

    _recordUndoSnapshot();
    setState(() {
      _flexReorderGhostRange = null;
      final chunk = list.sublist(start, end + 1);
      list.removeRange(start, end + 1);

      var dest = _flexChunkInsertDestAfterRemovingChunk(
        newIndex: newIndex,
        chunkStart: start,
        chunkLen: k,
      );
      if (dest < 0) dest = 0;
      if (dest > list.length) dest = list.length;
      list.insertAll(dest, chunk);

      _repackDayAfterFlexReorder(list);
      _sortBlocksChronologically(list);
      _repairUnpinnedLinearOverlaps(list);
      _repairOverlapsWithPins(list);
      _dayPlanPresetKind[dk] = _kIndividualDayPresetKey;
      if (!kIsWeb) {
        HapticFeedback.lightImpact();
      }
    });
    _flushPersistDayPlans();
    _offerUndoSnack(
      k > 1
          ? 'Mehrere Blöcke neu geordnet – oben oder hier rückgängig.'
          : 'Reihenfolge geändert – oben oder hier rückgängig.',
    );
  }

  List<TimeBlock> _getBlocksForDay(DateTime date) {
    final day = _onlyDay(date);
    _days.putIfAbsent(day, () {
      final w = _presetForDate(day);
      final pk = w?.presetKey ?? _resolvedActivePresetKey();
      _dayPlanPresetKind.putIfAbsent(day, () => pk);
      return _buildPresetBlocksForKey(pk);
    });
    final list = _days[day]!;
    _sortBlocksChronologically(list);
    _repairOverlapsWithPins(list);
    _repairUnpinnedLinearOverlaps(list);
    _repairOverlapsWithPins(list);
    return list;
  }

  /// Nimmt zwei unfixierte lineare Slots, die sich zeitlich überschneiden —
  /// schiebt den späteren Listen-Eintrag hinter das Ende des vorigen (Datenbasis).
  void _repairUnpinnedLinearOverlaps(List<TimeBlock> day) {
    const minDur = 15;
    if (day.length < 2) return;
    for (var i = 1; i < day.length; i++) {
      final prev = day[i - 1];
      final cur = day[i];
      if (!prev.isLinearSlot || !cur.isLinearSlot) continue;
      if (prev.isOvernightSlot || cur.isOvernightSlot) continue;
      if (prev.pinned || cur.pinned) continue;
      if (cur.startMin >= prev.endMin) continue;

      final dur = cur.duration < minDur ? minDur : cur.duration;
      final start = prev.endMin;
      if (start >= 1440) continue;
      var end = start + dur;
      if (end > 1440) end = 1440;
      if (end <= start) continue;
      if (end - start < minDur) {
        end = start + minDur;
        if (end > 1440) end = 1440;
      }
      cur.startMin = start;
      cur.endMin = end;
    }
  }

  Future<void> _openPresetTaskTemplatesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final padBottom = MediaQuery.of(sheetCtx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: padBottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _PresetTemplatesEditorSheet(
              initialKey: _resolvedActivePresetKey(),
              overrides: Map<PlannerPresetType, List<PresetTaskLine>>.from(
                _presetTaskOverrides,
              ),
              userPresets: List<UserPresetDay>.from(_userPresetDays),
              presetCategories: List<String>.from(_categoryOrder),
              builtinDisplayNames: Map<PlannerPresetType, String>.from(
                _builtinPresetDisplayOverrides,
              ),
              categoryColors: Map<String, Color>.from(_categoryColors),
              onSaved: (merged, users, builtinNames) async {
                if (!mounted) return;
                setState(() {
                  _presetTaskOverrides.clear();
                  _presetTaskOverrides.addAll(merged);
                  _userPresetDays
                    ..clear()
                    ..addAll(users);
                  _builtinPresetDisplayOverrides
                    ..clear()
                    ..addAll(builtinNames);
                  _sanitizeActivePresetKeyIfStale();
                });
                await _savePresetTaskOverrides();
                await _saveUserPresetDays();
                await _saveBuiltinPresetDisplayOverrides();
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPlannerIconPicker({
    required void Function(int? code) onPicked,
    int? currentCode,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final p = ctx.palette;
        final maxH = MediaQuery.of(ctx).size.height * 0.88;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: Container(
            color: p.surface,
            height: maxH,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  decoration: BoxDecoration(
                    color: p.hairline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Symbol wählen',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: p.text,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          onPicked(null);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Kategorie-Icon'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                      for (final cat in kPlannerIconCatalog)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 8,
                                  left: 4,
                                ),
                                child: Text(
                                  cat.key,
                                  style: Theme.of(ctx).textTheme.labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: p.muted,
                                      ),
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final ic in cat.value)
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          onPicked(ic.codePoint);
                                          Navigator.pop(ctx);
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: ic.codePoint == currentCode
                                                  ? p.text.withValues(
                                                      alpha: 0.4,
                                                    )
                                                  : p.hairline,
                                            ),
                                            color: p.bg.withValues(alpha: 0.25),
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            ic,
                                            color: p.text.withValues(
                                              alpha: 0.9,
                                            ),
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _toggleWeekdayInMask(int mask, int dayIndex0to6) {
    var m = mask;
    if (m == 0) m = 0x7F;
    m ^= 1 << dayIndex0to6;
    if (m == 0) m = 1 << dayIndex0to6;
    if (m == 0x7F) return 0;
    return m;
  }

  Future<void> _showRecurrenceConfigurator({
    required BlockRecurrence initialKind,
    required int initialWeekdayMask,
    required int initialMonthDay,
    required void Function(BlockRecurrence kind, int weekdayMask, int monthDay)
    onDone,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final p = ctx.palette;
        var kind = initialKind;
        var weekdayMask = initialWeekdayMask;
        var monthDay = initialMonthDay.clamp(1, 28);
        const dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
        return StatefulBuilder(
          builder: (context, setLocal) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: Container(
                color: p.surface,
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
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
                            color: p.hairline,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Text(
                        'Wiederholung',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: p.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in <(String, BlockRecurrence)>[
                            ('Einmalig', BlockRecurrence.none),
                            ('Täglich', BlockRecurrence.daily),
                            ('Wöchentlich', BlockRecurrence.weekly),
                            ('Monatlich', BlockRecurrence.monthly),
                          ])
                            ChoiceChip(
                              label: Text(e.$1),
                              selected: kind == e.$2,
                              onSelected: (v) {
                                if (v) {
                                  setLocal(() => kind = e.$2);
                                }
                              },
                            ),
                        ],
                      ),
                      if (kind == BlockRecurrence.weekly) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Wochentage',
                          style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: p.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: List.generate(7, (i) {
                            final on =
                                weekdayMask == 0 ||
                                ((weekdayMask >> i) & 1) != 0;
                            return FilterChip(
                              label: Text(dayNames[i]),
                              selected: on,
                              onSelected: (_) {
                                setLocal(() {
                                  weekdayMask = _toggleWeekdayInMask(
                                    weekdayMask,
                                    i,
                                  );
                                });
                              },
                            );
                          }),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          weekdayMask == 0
                              ? 'Alle Tage. Zum Eingrenzen Tage abwählen.'
                              : _weekdayShortMaskLabel(weekdayMask),
                          style: Theme.of(
                            ctx,
                          ).textTheme.bodySmall?.copyWith(color: p.muted),
                        ),
                      ],
                      if (kind == BlockRecurrence.monthly) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Tag im Monat (1–28)',
                          style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: p.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: p.bg.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: p.hairline),
                          ),
                          child: DropdownButton<int>(
                            value: monthDay,
                            isExpanded: true,
                            underline: const SizedBox.shrink(),
                            dropdownColor: p.surface,
                            items: [
                              for (var d = 1; d <= 28; d++)
                                DropdownMenuItem(value: d, child: Text('$d')),
                            ],
                            onChanged: (v) {
                              if (v != null) setLocal(() => monthDay = v);
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () {
                          onDone(
                            kind,
                            kind == BlockRecurrence.weekly ? weekdayMask : 0,
                            kind == BlockRecurrence.monthly ? monthDay : 1,
                          );
                          Navigator.pop(ctx);
                        },
                        child: const Text('Übernehmen'),
                      ),
                      SizedBox(height: MediaQuery.of(ctx).padding.bottom),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openNewBlockDialog({int? startMin, int? endMin}) {
    _openBlockDialog(draftStartMin: startMin, draftEndMin: endMin);
  }

  void _openEditBlockDialog(TimeBlock block) {
    _openBlockDialog(editing: block);
  }

  bool _followingBlockAllowsTimeSteal(TimeBlock n) =>
      n.isLinearSlot && !n.pinned && !n.allDay && !n.isOvernightSlot;

  /// Nimmt höchstens [overlap] Min beim Folgeblock, lässt mindestens 15 Min dort übrig.
  int _stealMinutesTowardFollowing(TimeBlock following, int newEditedEndMin) {
    const minDur = 15;
    if (newEditedEndMin <= following.startMin) return 0;
    final overlap = newEditedEndMin - following.startMin;
    final maxGive = following.duration - minDur;
    if (maxGive <= 0) return 0;
    return min(overlap, maxGive);
  }

  Future<void> _openBlockDialog({
    TimeBlock? editing,
    int? draftStartMin,
    int? draftEndMin,
  }) async {
    final titleCtrl = TextEditingController(text: editing?.title ?? '');
    final notesCtrl = TextEditingController(text: editing?.notes ?? '');
    final subtaskInputCtrl = TextEditingController();

    final origEditEndMin = editing?.endMin;

    var draftStart = editing?.startMin ?? draftStartMin ?? 540;
    var draftEnd = editing?.endMin ??
        draftEndMin ??
        ((draftStartMin != null) ? (draftStartMin + 60) % 1440 : 600);
    if (draftEnd == draftStart) draftEnd = (draftStart + 60) % 1440;
    var useDurationInput = false;
    var initialDuration = _spanMinutesRaw(draftStart, draftEnd);
    if (initialDuration <= 0) initialDuration = 60;
    var durationHours = (initialDuration ~/ 60).clamp(0, 23);
    var durationMinutes = (initialDuration % 60).clamp(0, 59);
    var allDay = editing?.allDay ?? false;
    var recurrence = editing?.recurrence ?? BlockRecurrence.none;
    var recurrenceWeekdayMask = editing?.recurrenceWeekdayMask ?? 0;
    var recurrenceMonthDay = editing?.recurrenceMonthDay.clamp(1, 28) ?? 1;
    int? draftCustomIconCode = editing?.customIconCodePoint;
    var completed = editing?.completed ?? false;
    var muteReminders = editing?.muteReminders ?? false;
    var colorLabel = editing?.colorLabel ?? _fallbackCategoryLabel();
    if (colorLabel == 'Lesen') colorLabel = 'Wichtig';
    if (!_categoryColors.containsKey(colorLabel)) {
      colorLabel = _fallbackCategoryLabel();
    }
    var useCategoryStripe = true;
    String? draftCustomStripeHex;
    if (editing != null) {
      final ch = editing.customStripeHex?.trim();
      if (ch != null && ch.isNotEmpty) {
        useCategoryStripe = false;
        draftCustomStripeHex = ch;
      }
    }
    final draftSubtasks = editing != null
        ? editing.subtasks
              .map((s) => BlockSubtask(id: s.id, title: s.title, done: s.done))
              .toList()
        : <BlockSubtask>[];
    final draftSessionSegments = editing != null
        ? editing.sessionSegments
              .map(
                (s) => BlockSessionSegment(
                  id: s.id,
                  durationMinutes: s.durationMinutes,
                  isPause: s.isPause,
                ),
              )
              .toList()
        : <BlockSessionSegment>[];
    const pauseMinuteChoices = [5, 10, 15, 20, 25, 30];
    const focusMinuteChoices = [
      15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 75, 90, 105, 120, 150, 180,
    ];
    final subtaskCtrlById = <String, TextEditingController>{};
    for (final s in draftSubtasks) {
      subtaskCtrlById[s.id] = TextEditingController(text: s.title);
    }

    List<BlockSubtask> subtasksFromDraftWithNewIds() {
      final out = <BlockSubtask>[];
      for (final s in draftSubtasks) {
        final t = (subtaskCtrlById[s.id]?.text ?? s.title).trim();
        if (t.isEmpty) continue;
        out.add(BlockSubtask(id: _nextId(), title: t, done: s.done));
      }
      return out;
    }

    List<BlockSubtask> subtasksFromDraftKeepIds() {
      final out = <BlockSubtask>[];
      for (final s in draftSubtasks) {
        final t = (subtaskCtrlById[s.id]?.text ?? s.title).trim();
        if (t.isEmpty) continue;
        out.add(BlockSubtask(id: s.id, title: t, done: s.done));
      }
      return out;
    }

    void syncDurationFromRange() {
      final d = _spanMinutesRaw(draftStart, draftEnd);
      if (d <= 0) return;
      durationHours = (d ~/ 60).clamp(0, 23);
      durationMinutes = (d % 60).clamp(0, 59);
    }

    Future<void> pickStart(StateSetter setSheet) async {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: draftStart ~/ 60, minute: draftStart % 60),
      );
      if (t != null) {
        setSheet(() {
          draftStart = t.hour * 60 + t.minute;
          allDay = false;
          if (!useDurationInput) syncDurationFromRange();
        });
      }
    }

    Future<void> pickEnd(StateSetter setSheet) async {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: draftEnd ~/ 60, minute: draftEnd % 60),
      );
      if (t != null) {
        setSheet(() {
          draftEnd = t.hour * 60 + t.minute;
          allDay = false;
          syncDurationFromRange();
        });
      }
    }

    bool validateTimes(int sm, int em, bool ad) {
      if (ad) return true;
      return sm != em;
    }

    Future<void> commit(StateSetter setSheet) async {
      final title = titleCtrl.text.trim();
      if (title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte einen Titel eingeben.')),
        );
        return;
      }
      var sm = draftStart;
      var em = draftEnd;
      if (allDay) {
        sm = 0;
        em = 1440;
      } else if (useDurationInput) {
        final h = durationHours;
        final m = durationMinutes;
        final dur = h * 60 + m;
        if (dur <= 0 || dur >= 1440) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Dauer bitte zwischen 1 Min und 23 Std 59 Min wählen.',
              ),
            ),
          );
          return;
        }
        em = (sm + dur) % 1440;
      }
      if (!validateTimes(sm, em, allDay)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Start und Ende dürfen nicht gleich sein.'),
          ),
        );
        return;
      }

      final spanLin =
          allDay || sm >= em ? 0 : _spanMinutesRaw(sm, em);
      if (draftSessionSegments.isNotEmpty) {
        if (allDay || sm >= em || editing?.isOvernightSlot == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Fokus-/Pause-Abschnitte nur bei einem normalen Tages-Slot (nicht ganztägig, Start vor Ende).',
              ),
            ),
          );
          return;
        }
        if (!sessionSegmentsValidForSpan(draftSessionSegments, spanLin)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Session: Summe ist ${sessionSegmentsTotalMinutes(draftSessionSegments)} Min, '
                'Block aber $spanLin Min — bitte Abschnitte anpassen oder mit „Leeren“ entfernen.',
              ),
            ),
          );
          return;
        }
      }

      List<BlockSessionSegment> builtSessionSegments() => [
            for (final s in draftSessionSegments)
              BlockSessionSegment(
                id: editing == null ? _nextId() : s.id,
                durationMinutes: s.durationMinutes,
                isPause: s.isPause,
              ),
          ];

      var stealFromNextMin = 0;
      TimeBlock? stealFromBlock;
      if (editing != null &&
          origEditEndMin != null &&
          !allDay &&
          sm < em &&
          !editing.isOvernightSlot) {
        final day = _getBlocksForDay(_selectedDate);
        final idx = day.indexWhere((b) => b.id == editing.id);
        if (idx >= 0 && idx + 1 < day.length) {
          final nxt = day[idx + 1];
          if (_followingBlockAllowsTimeSteal(nxt)) {
            stealFromNextMin = _stealMinutesTowardFollowing(nxt, em);
            if (stealFromNextMin > 0) {
              if (!context.mounted) {
                stealFromNextMin = 0;
              } else {
                final yn = await showDialog<bool>(
                  context: context,
                  builder: (ctx) {
                    final p2 = ctx.palette;
                    final nt = nxt.title.trim().isEmpty
                        ? '(ohne Titel)'
                        : nxt.title.trim();
                    return AlertDialog(
                      title: Text(
                        'Aus „$nt“ abziehen?',
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      content: Text(
                        'Dein Block geht bis ${_fmtMin(em)} und schneidet den '
                        'nächsten Zeitblock ab ${_fmtMin(nxt.startMin)}. '
                        'Sollen dafür $stealFromNextMin Min von der Dauer von '
                        '„$nt“ abgezogen werden (${_fmtMin(nxt.startMin)}–'
                        '${_fmtMin(nxt.endMin)} beginnt danach später)?',
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: p2.text.withValues(alpha: 0.92),
                          height: 1.35,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            'Nein',
                            style: TextStyle(color: p2.muted),
                          ),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Ja'),
                        ),
                      ],
                    );
                  },
                );
                if (!mounted) return;
                if (yn == true) {
                  stealFromBlock = nxt;
                } else {
                  stealFromNextMin = 0;
                }
              }
            }
          }
        }
      }

      String? stripeHexOut;
      if (useCategoryStripe || allDay) {
        stripeHexOut = null;
      } else {
        stripeHexOut = draftCustomStripeHex?.trim();
        if (stripeHexOut == null || stripeHexOut.isEmpty) {
          stripeHexOut = _colorToHexArgb(_stripeColor(colorLabel));
        }
      }

      _recordUndoSnapshot();
      setState(() {
        if (editing == null) {
          _getBlocksForDay(_selectedDate).add(
            _newBlock(
              title,
              sm,
              em,
              colorLabel,
              '',
              allDay: allDay,
              recurrence: recurrence,
              recurrenceWeekdayMask: recurrenceWeekdayMask,
              recurrenceMonthDay: recurrenceMonthDay,
              customIconCodePoint: draftCustomIconCode,
              customStripeHex: stripeHexOut,
              notes: notesCtrl.text,
              completed: completed,
              muteReminders: muteReminders,
              subtasks: subtasksFromDraftWithNewIds(),
              sessionSegments: builtSessionSegments(),
            ),
          );
        } else {
          editing.title = title;
          editing.startMin = sm;
          editing.endMin = em;
          editing.colorLabel = colorLabel;
          editing.emoji = '';
          editing.allDay = allDay;
          editing.recurrence = recurrence;
          editing.recurrenceWeekdayMask = recurrenceWeekdayMask;
          editing.recurrenceMonthDay = recurrenceMonthDay;
          editing.customIconCodePoint = draftCustomIconCode;
          editing.customStripeHex = stripeHexOut;
          editing.notes = notesCtrl.text;
          editing.completed = completed;
          editing.muteReminders = muteReminders;
          editing.subtasks
            ..clear()
            ..addAll(subtasksFromDraftKeepIds());
          editing.sessionSegments
            ..clear()
            ..addAll(builtSessionSegments());
          if (stealFromBlock != null && stealFromNextMin > 0) {
            stealFromBlock.startMin =
                stealFromBlock.startMin + stealFromNextMin;
          }
        }
        final dayFinal = _getBlocksForDay(_selectedDate);
        _repairOverlapsWithPins(dayFinal);
        _repairUnpinnedLinearOverlaps(dayFinal);
        _repairOverlapsWithPins(dayFinal);
        _dayPlanPresetKind[_onlyDay(_selectedDate)] = _kIndividualDayPresetKey;
      });
      if (editing != null) _syncProjectRotationForBlock(editing);
      _schedulePersistDayPlans();
      if (!mounted) return;
      Navigator.pop(context);
      unawaited(_syncReminders());
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final padBottom = MediaQuery.of(sheetCtx).viewInsets.bottom;
        final maxH = MediaQuery.of(sheetCtx).size.height * 0.94;

        return StatefulBuilder(
          builder: (context, setSheet) {
            void appendSubtaskFromInput() {
              final t = subtaskInputCtrl.text.trim();
              if (t.isEmpty) return;
              setSheet(() {
                final id = _nextId();
                subtaskCtrlById[id] = TextEditingController(text: t);
                draftSubtasks.add(BlockSubtask(id: id, title: t));
                subtaskInputCtrl.clear();
              });
            }

            void appendSubtaskFromPreset(String rawTitle) {
              final t = rawTitle.trim();
              if (t.isEmpty) return;
              setSheet(() {
                final id = _nextId();
                subtaskCtrlById[id] = TextEditingController(text: t);
                draftSubtasks.add(BlockSubtask(id: id, title: t));
              });
            }

            final p = context.palette;
            final heroBg = p.surface;
            final previewStart = allDay ? 0 : draftStart;
            final previewEnd = allDay ? 1440 : draftEnd;
            final previewDur = allDay
                ? 1440
                : _spanMinutesRaw(previewStart, previewEnd);

            TextStyle metaSmall(Color c) =>
                Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontSize: 13,
                  color: c,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                );

            Widget dividerRow() => Divider(
              height: 1,
              thickness: 1,
              color: p.hairline.withValues(alpha: 0.85),
            );

            Widget infoRow({
              required IconData icon,
              required String title,
              String? trailing,
              VoidCallback? onTap,
            }) {
              return InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 22, color: p.accent),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: p.text,
                              ),
                        ),
                      ),
                      if (trailing != null)
                        Text(
                          trailing,
                          style: TextStyle(color: p.muted, fontSize: 15),
                        ),
                      if (onTap != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, color: p.muted),
                      ],
                    ],
                  ),
                ),
              );
            }

            Widget insetDivider() => Padding(
              padding: const EdgeInsets.only(left: 52),
              child: Divider(
                height: 1,
                thickness: 1,
                color: p.hairline.withValues(alpha: 0.85),
              ),
            );

            Future<void> openColorSheet() async {
              final outerSet = setSheet;
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (cctx) {
                  return StatefulBuilder(
                    builder: (context, setPal) {
                      void setSheet(VoidCallback f) {
                        outerSet(f);
                        setPal(() {});
                      }

                      final p = context.palette;
                      return _sheetFrame(cctx, [
                                      Text(
                                        'Kategorie',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: p.muted,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          for (final k in _categoryOrder.where(
                                            (k) => _categoryColors.containsKey(k),
                                          ))
                                            ChoiceChip(
                                              showCheckmark: false,
                                              avatar: Container(
                                                width: 10,
                                                height: 10,
                                                decoration: BoxDecoration(
                                                  color: _categoryColors[k],
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              label: Text(k),
                                              selected: colorLabel == k,
                                              selectedColor:
                                                  (_categoryColors[k] ?? p.accent)
                                                      .withValues(alpha: 0.25),
                                              side: BorderSide(
                                                color: colorLabel == k
                                                    ? (_categoryColors[k] ??
                                                          p.accent)
                                                    : p.hairline,
                                              ),
                                              onSelected: (_) => setSheet(
                                                () => colorLabel = k,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Randfarbe',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: p.muted,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              useCategoryStripe
                                                  ? 'Wie Kategorie'
                                                  : 'Eigene Akzentfarbe',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: p.text.withValues(
                                                      alpha: 0.92,
                                                    ),
                                                  ),
                                            ),
                                          ),
                                          Switch.adaptive(
                                            value: useCategoryStripe,
                                            onChanged: (v) {
                                              setSheet(() {
                                                useCategoryStripe = v;
                                                if (v) {
                                                  draftCustomStripeHex = null;
                                                } else {
                                                  draftCustomStripeHex ??=
                                                      _colorToHexArgb(
                                                        _stripeColor(
                                                          colorLabel,
                                                        ),
                                                      );
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                      if (!useCategoryStripe) ...[
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: IconButton(
                                            tooltip:
                                                'Randfarbe frei wählen — Farbplatte & Regenbogen',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () async {
                                              final start =
                                                  draftCustomStripeHex != null
                                                  ? _colorFromHexString(
                                                      draftCustomStripeHex!,
                                                    )
                                                  : _stripeColor(colorLabel);
                                              final picked =
                                                  await _pickStripeColorFromFullPalette(
                                                    start,
                                                  );
                                              if (picked == null || !mounted)
                                                return;
                                              final pickedHex = _colorToHexArgb(
                                                picked,
                                              );
                                              setSheet(() {
                                                draftCustomStripeHex =
                                                    pickedHex;
                                              });
                                              final exists =
                                                  _customStripeSwatches.any(
                                                    (x) =>
                                                        x.toARGB32() ==
                                                        picked.toARGB32(),
                                                  );
                                              if (!exists &&
                                                  !_isBuiltinStripeSwatch(
                                                    picked,
                                                  )) {
                                                setState(() {
                                                  _customStripeSwatches.add(
                                                    picked,
                                                  );
                                                });
                                                await _saveCustomStripeSwatches();
                                              }
                                            },
                                            icon: Icon(
                                              Icons.add_circle_outline,
                                              color: p.accent,
                                            ),
                                          ),
                                        ),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (final c
                                                in _allStripeSwatches())
                                              Builder(
                                                builder: (_) {
                                                  final isCustom =
                                                      !_isBuiltinStripeSwatch(
                                                        c,
                                                      );
                                                  final isActive =
                                                      draftCustomStripeHex ==
                                                      _colorToHexArgb(c);
                                                  return GestureDetector(
                                                    onTap: () => setSheet(
                                                      () =>
                                                          draftCustomStripeHex =
                                                              _colorToHexArgb(
                                                                c,
                                                              ),
                                                    ),
                                                    child: Stack(
                                                      clipBehavior: Clip.none,
                                                      children: [
                                                        Container(
                                                          width: 32,
                                                          height: 32,
                                                          decoration: BoxDecoration(
                                                            color: c,
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                              color: isActive
                                                                  ? p.accent
                                                                  : p.hairline
                                                                        .withValues(
                                                                          alpha:
                                                                              0.55,
                                                                        ),
                                                              width: isActive
                                                                  ? 2.6
                                                                  : 1,
                                                            ),
                                                          ),
                                                        ),
                                                        if (isCustom)
                                                          Positioned(
                                                            right: -4,
                                                            top: -4,
                                                            child: GestureDetector(
                                                              onTap: () async {
                                                                setState(() {
                                                                  _customStripeSwatches
                                                                      .removeWhere(
                                                                        (x) =>
                                                                            x.toARGB32() ==
                                                                            c.toARGB32(),
                                                                      );
                                                                });
                                                                if (draftCustomStripeHex ==
                                                                    _colorToHexArgb(
                                                                      c,
                                                                    )) {
                                                                  setSheet(() {
                                                                    draftCustomStripeHex =
                                                                        _colorToHexArgb(
                                                                          _stripeColor(
                                                                            colorLabel,
                                                                          ),
                                                                        );
                                                                  });
                                                                }
                                                                await _saveCustomStripeSwatches();
                                                              },
                                                              child: Container(
                                                                width: 16,
                                                                height: 16,
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      p.surface,
                                                                  shape: BoxShape
                                                                      .circle,
                                                                  border: Border.all(
                                                                    color: p
                                                                        .hairline,
                                                                  ),
                                                                ),
                                                                child: Icon(
                                                                  Icons
                                                                      .close_rounded,
                                                                  size: 11,
                                                                  color:
                                                                      p.muted,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Eigene Farben: + hinzufügen, X löschen',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: p.muted.withValues(
                                                  alpha: 0.9,
                                                ),
                                              ),
                                        ),
                                      ],
                      ]);
                    },
                  );
                },
              );
            }

            return Padding(
              padding: EdgeInsets.only(bottom: padBottom),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                  child: Container(
                    color: p.bg,
                    height: maxH,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Builder(
                                  builder: (context) {
                                    final accentCol =
                                        (!useCategoryStripe &&
                                            draftCustomStripeHex != null)
                                        ? _colorFromHexString(
                                            draftCustomStripeHex!,
                                          )
                                        : _stripeColor(colorLabel);
                                    final headBg = Color.alphaBlend(
                                      accentCol.withValues(
                                        alpha: p.isDark ? 0.42 : 0.30,
                                      ),
                                      p.bg,
                                    );
                                    final btnBg = Color.alphaBlend(
                                      Colors.black.withValues(alpha: 0.28),
                                      headBg,
                                    );
                                    Widget roundBtn(Widget child) => Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: btnBg,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: child,
                                    );
                                    return Container(
                                      color: headBg,
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        10,
                                        16,
                                        22,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Center(
                                            child: Container(
                                              width: 40,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: p.text.withValues(
                                                  alpha: 0.3,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              roundBtn(
                                                IconButton(
                                                  tooltip: 'Schließen',
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  icon: Icon(
                                                    Icons.close_rounded,
                                                    color: p.text,
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              if (editing != null)
                                                roundBtn(
                                                  PopupMenuButton<String>(
                                                    icon: Icon(
                                                      Icons.more_horiz,
                                                      color: p.muted,
                                                    ),
                                                    color: p.surface,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      side: BorderSide(
                                                        color: p.hairline,
                                                      ),
                                                    ),
                                                    onSelected: (v) {
                                                      final b = editing;
                                                      if (b == null) return;
                                                      Navigator.pop(context);
                                                      Future.microtask(() {
                                                        if (!mounted) return;
                                                        switch (v) {
                                                          case 'pin':
                                                            _togglePin(b);
                                                            break;
                                                          case 'split':
                                                            _splitBlock(b);
                                                            break;
                                                          case 'copy':
                                                            _duplicateBlock(b);
                                                            break;
                                                          case 'inbox':
                                                            _moveToBacklog(b);
                                                            break;
                                                        }
                                                      });
                                                    },
                                                    itemBuilder: (c) => [
                                                      if (editing != null)
                                                        const PopupMenuItem(
                                                          value: 'pin',
                                                          child: Text(
                                                            'Fixierung',
                                                          ),
                                                        ),
                                                      if (editing != null)
                                                        const PopupMenuItem(
                                                          value: 'split',
                                                          child: Text('Teilen'),
                                                        ),
                                                      if (editing != null)
                                                        const PopupMenuItem(
                                                          value: 'copy',
                                                          child: Text(
                                                            'Duplizieren',
                                                          ),
                                                        ),
                                                      if (editing != null)
                                                        const PopupMenuItem(
                                                          value: 'inbox',
                                                          child: Text(
                                                            'In Ablage',
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 74,
                                                height: 108,
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    Positioned.fill(
                                                      child: Material(
                                                        color: accentCol
                                                            .withValues(
                                                              alpha: 0.35,
                                                            ),
                                                        shape: StadiumBorder(
                                                          side: BorderSide(
                                                            color: p.text,
                                                            width: 3,
                                                          ),
                                                        ),
                                                        child: InkWell(
                                                          customBorder:
                                                              const StadiumBorder(),
                                                          onTap: () {
                                                            _showPlannerIconPicker(
                                                              currentCode:
                                                                  draftCustomIconCode,
                                                              onPicked: (c) =>
                                                                  setSheet(
                                                                    () =>
                                                                        draftCustomIconCode =
                                                                            c,
                                                                  ),
                                                            );
                                                          },
                                                          child: Center(
                                                            child: Icon(
                                                              _draftBlockIcon(
                                                                colorLabel,
                                                                draftCustomIconCode,
                                                              ),
                                                              size: 34,
                                                              color: p.text,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Positioned(
                                                      left: -8,
                                                      bottom: -8,
                                                      child: Material(
                                                        color: btnBg,
                                                        shape:
                                                            const CircleBorder(),
                                                        child: InkWell(
                                                          customBorder:
                                                              const CircleBorder(),
                                                          onTap: () =>
                                                              openColorSheet(),
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  9,
                                                                ),
                                                            child: Icon(
                                                              Icons
                                                                  .palette_outlined,
                                                              size: 20,
                                                              color: p.text,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 18),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      allDay
                                                          ? 'Ganztags'
                                                          : '${_fmtMin(previewStart)}–${_fmtMin(previewEnd % 1440)} (${_humanDuration(previewDur)})',
                                                      style: metaSmall(
                                                        p.text.withValues(
                                                          alpha: 0.65,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                TextField(
                                                  controller: titleCtrl,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headlineSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        letterSpacing: -0.5,
                                                        color: p.text,
                                                        fontSize: 22,
                                                      ),
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    border: InputBorder.none,
                                                    hintText: 'Titel',
                                                    hintStyle: TextStyle(
                                                      color: p.muted,
                                                    ),
                                                  ),
                                                  maxLines: 2,
                                                ),
                                                if (editing == null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: ActionChip(
                                                      avatar: Icon(
                                                        Icons.autorenew_rounded,
                                                        size: 16,
                                                        color: p.accent,
                                                      ),
                                                      label: const Text(
                                                        'Projekt-Session',
                                                      ),
                                                      onPressed: () =>
                                                          setSheet(() {
                                                        titleCtrl.text =
                                                            'Projekt-Session';
                                                        if (_categoryColors
                                                            .containsKey(
                                                              'Fokus',
                                                            )) {
                                                          colorLabel = 'Fokus';
                                                        }
                                                        draftCustomIconCode =
                                                            Icons
                                                                .autorenew_rounded
                                                                .codePoint;
                                                      }),
                                                    ),
                                                  ),
                                                    const SizedBox(height: 6),
                                                    InkWell(
                                                      onTap: () =>
                                                          openColorSheet(),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 4,
                                                            ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Container(
                                                              width: 10,
                                                              height: 10,
                                                              decoration:
                                                                  BoxDecoration(
                                                                    color:
                                                                        accentCol,
                                                                    shape: BoxShape
                                                                        .circle,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Text(
                                                              colorLabel,
                                                              style: TextStyle(
                                                                color: p.text
                                                                    .withValues(
                                                                      alpha:
                                                                          0.8,
                                                                    ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (editing != null)
                                                GestureDetector(
                                                  onTap: () => setSheet(
                                                    () => completed = !completed,
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 10,
                                                        ),
                                                    child: Container(
                                                      width: 32,
                                                      height: 32,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: p.text,
                                                          width: 2,
                                                        ),
                                                        color: completed
                                                            ? p.text
                                                            : null,
                                                      ),
                                                      child: completed
                                                          ? Icon(
                                                              Icons.check_rounded,
                                                              size: 20,
                                                              color: headBg,
                                                            )
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    14,
                                    18,
                                    0,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: p.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: p.hairline),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    children: [
                                      infoRow(
                                        icon: Icons.calendar_month_rounded,
                                        title: _dateSheetHeading(_selectedDate),
                                        onTap: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: _selectedDate,
                                            firstDate: DateTime(2024),
                                            lastDate: DateTime(2035),
                                          );
                                          if (picked != null) {
                                            _pickDate(picked);
                                          }
                                        },
                                      ),
                                      insetDivider(),
                                      infoRow(
                                        icon: Icons.schedule_rounded,
                                        title: allDay
                                            ? 'Ganztags'
                                            : '${_fmtMin(draftStart)} – ${_fmtMin(draftEnd)}${_spanCrossesMidnight(draftStart, draftEnd) ? ' (+1)' : ''}',
                                        trailing: allDay
                                            ? null
                                            : _humanDuration(previewDur),
                                        onTap: allDay
                                            ? null
                                            : () async {
                                                await pickStart(setSheet);
                                                if (!useDurationInput) {
                                                  await pickEnd(setSheet);
                                                }
                                              },
                                      ),
                                      if (!allDay)
                                        if (useDurationInput)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              14,
                                              0,
                                              14,
                                              12,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Text(
                                                        'Std',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .labelLarge
                                                            ?.copyWith(
                                                              color: p.muted,
                                                            ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      SizedBox(
                                                        height: 120,
                                                        child: CupertinoPicker(
                                                          scrollController:
                                                              FixedExtentScrollController(
                                                                initialItem:
                                                                    durationHours,
                                                              ),
                                                          itemExtent: 34,
                                                          magnification: 1.08,
                                                          useMagnifier: true,
                                                          squeeze: 1.2,
                                                          onSelectedItemChanged: (v) {
                                                            HapticFeedback.selectionClick();
                                                            setSheet(
                                                              () =>
                                                                  durationHours =
                                                                      v,
                                                            );
                                                          },
                                                          children: [
                                                            for (
                                                              var h = 0;
                                                              h <= 23;
                                                              h++
                                                            )
                                                              Center(
                                                                child: Text(
                                                                  '$h',
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Text(
                                                        'Min',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .labelLarge
                                                            ?.copyWith(
                                                              color: p.muted,
                                                            ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      SizedBox(
                                                        height: 120,
                                                        child: CupertinoPicker(
                                                          scrollController:
                                                              FixedExtentScrollController(
                                                                initialItem:
                                                                    durationMinutes,
                                                              ),
                                                          itemExtent: 34,
                                                          magnification: 1.08,
                                                          useMagnifier: true,
                                                          squeeze: 1.2,
                                                          onSelectedItemChanged: (v) {
                                                            HapticFeedback.selectionClick();
                                                            setSheet(
                                                              () =>
                                                                  durationMinutes =
                                                                      v,
                                                            );
                                                          },
                                                          children: [
                                                            for (
                                                              var m = 0;
                                                              m <= 59;
                                                              m++
                                                            )
                                                              Center(
                                                                child: Text(
                                                                  '$m',
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      insetDivider(),
                                      infoRow(
                                        icon: Icons.repeat_rounded,
                                        title: _draftRecurrenceSummary(
                                          recurrence: recurrence,
                                          weekdayMask: recurrenceWeekdayMask,
                                          monthDay: recurrenceMonthDay,
                                        ),
                                        onTap: () async {
                                          await _showRecurrenceConfigurator(
                                            initialKind: recurrence,
                                            initialWeekdayMask:
                                                recurrenceWeekdayMask,
                                            initialMonthDay: recurrenceMonthDay,
                                            onDone: (k, wm, md) {
                                              setSheet(() {
                                                recurrence = k;
                                                recurrenceWeekdayMask = wm;
                                                recurrenceMonthDay = md;
                                              });
                                            },
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                if (!allDay) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Material(
                                      color: muteReminders
                                          ? p.surface
                                          : p.accent.withValues(alpha: 0.18),
                                      shape: StadiumBorder(
                                        side: BorderSide(
                                          color: muteReminders
                                              ? p.hairline
                                              : p.accent.withValues(alpha: 0.6),
                                        ),
                                      ),
                                      child: InkWell(
                                        customBorder: const StadiumBorder(),
                                        onTap: () => setSheet(
                                          () => muteReminders = !muteReminders,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                muteReminders
                                                    ? Icons
                                                          .notifications_off_outlined
                                                    : Icons
                                                          .notifications_active_outlined,
                                                size: 20,
                                                color: muteReminders
                                                    ? p.muted
                                                    : p.accent,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                muteReminders
                                                    ? 'Hinweise aus'
                                                    : 'Hinweise an',
                                                style: TextStyle(
                                                  color: p.text,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Container(
                                  decoration: BoxDecoration(
                                    color: p.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: p.hairline),
                                    boxShadow: p.cardShadows,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      10,
                                      12,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Checkliste',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: p.text,
                                                    ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Vorlagen bearbeiten',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 36,
                                                minHeight: 36,
                                              ),
                                              icon: Icon(
                                                Icons.tune_rounded,
                                                size: 20,
                                                color: p.muted,
                                              ),
                                              onPressed: () async {
                                                await _openSubtaskQuickPresetsEditor();
                                                if (mounted) setSheet(() {});
                                              },
                                            ),
                                          ],
                                        ),
                                        if (_subtaskQuickPresets
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                for (final preset
                                                    in _subtaskQuickPresets)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 8,
                                                          bottom: 2,
                                                        ),
                                                    child: ActionChip(
                                                      label: Text(
                                                        preset,
                                                        style: TextStyle(
                                                          color: p.text,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 0,
                                                          ),
                                                      backgroundColor: p.chipBg,
                                                      side: BorderSide(
                                                        color: p.hairline,
                                                      ),
                                                      onPressed: () =>
                                                          appendSubtaskFromPreset(
                                                            preset,
                                                          ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ] else ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Noch keine Schnell-Vorlagen — über das Symbol rechts eigene Einträge anlegen.',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: p.muted,
                                                  fontSize: 12.5,
                                                  height: 1.35,
                                                ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        ...draftSubtasks.asMap().entries.map((
                                          e,
                                        ) {
                                          final i = e.key;
                                          final st = e.value;
                                          final stCtrl =
                                              subtaskCtrlById[st.id]!;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Checkbox.adaptive(
                                                  value: st.done,
                                                  activeColor: p.text
                                                      .withValues(alpha: 0.65),
                                                  onChanged: (v) {
                                                    setSheet(() {
                                                      draftSubtasks[i] = st
                                                          .copyWith(
                                                            done: v ?? false,
                                                          );
                                                    });
                                                  },
                                                ),
                                                Expanded(
                                                  child: TextField(
                                                    key: ValueKey<String>(
                                                      st.id,
                                                    ),
                                                    controller: stCtrl,
                                                    style: TextStyle(
                                                      color: p.text,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    decoration:
                                                        const InputDecoration(
                                                          isDense: true,
                                                          border:
                                                              InputBorder.none,
                                                        ),
                                                  ),
                                                ),
                                                IconButton(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  icon: Icon(
                                                    Icons.close_rounded,
                                                    size: 18,
                                                    color: p.muted,
                                                  ),
                                                  onPressed: () {
                                                    setSheet(() {
                                                      subtaskCtrlById
                                                          .remove(st.id)
                                                          ?.dispose();
                                                      draftSubtasks.removeAt(i);
                                                    });
                                                  },
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              tooltip: 'Unterpunkt hinzufügen',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 40,
                                                minHeight: 40,
                                              ),
                                              onPressed: appendSubtaskFromInput,
                                              icon: Icon(
                                                Icons.add_task_rounded,
                                                size: 22,
                                                color: p.muted,
                                              ),
                                            ),
                                            Expanded(
                                              child: TextField(
                                                controller: subtaskInputCtrl,
                                                maxLines: 1,
                                                textInputAction:
                                                    TextInputAction.done,
                                                decoration: InputDecoration(
                                                  hintText:
                                                      'Unterpunkt hinzufügen …',
                                                  hintStyle: TextStyle(
                                                    color: p.muted,
                                                  ),
                                                  border: InputBorder.none,
                                                  isDense: true,
                                                ),
                                                onSubmitted: (_) =>
                                                    appendSubtaskFromInput(),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (!allDay &&
                                            previewStart < previewEnd) ...[
                                          const SizedBox(height: 14),
                                          dividerRow(),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Fokus & Pausen',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: p.text,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Optional: Block in Fokus- und Pausenabschnitte teilen, mit Timer.',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: p.muted,
                                                  height: 1.35,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              FilledButton.tonalIcon(
                                                onPressed: () => setSheet(() {
                                                  draftSessionSegments.add(
                                                    BlockSessionSegment(
                                                      id: _nextId(),
                                                      durationMinutes: 50,
                                                      isPause: false,
                                                    ),
                                                  );
                                                }),
                                                icon: const Icon(
                                                  Icons.center_focus_strong,
                                                  size: 18,
                                                ),
                                                label: const Text('+ Fokus'),
                                              ),
                                              FilledButton.tonalIcon(
                                                onPressed: () => setSheet(() {
                                                  draftSessionSegments.add(
                                                    BlockSessionSegment(
                                                      id: _nextId(),
                                                      durationMinutes: 10,
                                                      isPause: true,
                                                    ),
                                                  );
                                                }),
                                                icon: const Icon(
                                                  Icons.local_cafe_rounded,
                                                  size: 18,
                                                ),
                                                label: const Text('+ Pause'),
                                              ),
                                              TextButton(
                                                onPressed: () => setSheet(() {
                                                  draftSessionSegments.clear();
                                                }),
                                                child: Text(
                                                  'Session leeren',
                                                  style: TextStyle(
                                                    color: p.muted,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (draftSessionSegments.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Builder(
                                              builder: (ctx) {
                                                final sum =
                                                    sessionSegmentsTotalMinutes(
                                                  draftSessionSegments,
                                                );
                                                final ok = sum == previewDur;
                                                return Text(
                                                  '$sum / $previewDur Min'
                                                  '${ok ? ' · passt' : ' · noch anpassen'}',
                                                  style: Theme.of(ctx)
                                                      .textTheme
                                                      .labelLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: ok
                                                            ? Colors.green
                                                            : Colors.orange,
                                                      ),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 8),
                                            ...draftSessionSegments
                                                .asMap()
                                                .entries
                                                .map((e) {
                                              final i = e.key;
                                              final seg = e.value;
                                              final choices = seg.isPause
                                                  ? pauseMinuteChoices
                                                  : focusMinuteChoices;
                                              int snapped(int v) {
                                                var best = choices.first;
                                                var bd = (v - best).abs();
                                                for (final c in choices) {
                                                  final d = (v - c).abs();
                                                  if (d < bd) {
                                                    best = c;
                                                    bd = d;
                                                  }
                                                }
                                                return best;
                                              }

                                              final dv = snapped(
                                                seg.durationMinutes,
                                              );
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      seg.isPause
                                                          ? Icons
                                                              .local_cafe_rounded
                                                          : Icons.timer_outlined,
                                                      size: 22,
                                                      color: p.muted,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      flex: 2,
                                                      child:
                                                          DropdownButtonFormField<
                                                              int>(
                                                        value: dv,
                                                        decoration:
                                                            InputDecoration(
                                                          labelText: seg.isPause
                                                              ? 'Pause'
                                                              : 'Fokus',
                                                          isDense: true,
                                                          filled: true,
                                                          fillColor: p.bg
                                                              .withValues(
                                                                alpha: 0.35,
                                                          ),
                                                        ),
                                                        items: [
                                                          for (final m
                                                              in choices)
                                                            DropdownMenuItem(
                                                              value: m,
                                                              child: Text(
                                                                '$m Min',
                                                              ),
                                                            ),
                                                        ],
                                                        onChanged: (v) {
                                                          if (v == null) {
                                                            return;
                                                          }
                                                          setSheet(() {
                                                            draftSessionSegments[
                                                                    i] =
                                                                seg.copyWith(
                                                              durationMinutes:
                                                                  v,
                                                            );
                                                          });
                                                        },
                                                      ),
                                                    ),
                                                    IconButton(
                                                      tooltip:
                                                          seg.isPause
                                                          ? 'Als Fokus'
                                                          : 'Als Pause',
                                                      onPressed: () =>
                                                          setSheet(() {
                                                        final nextPause =
                                                            !seg.isPause;
                                                        final list = nextPause
                                                            ? pauseMinuteChoices
                                                            : focusMinuteChoices;
                                                        int snapNew(int v) {
                                                          var best = list.first;
                                                          var bd =
                                                              (v - best).abs();
                                                          for (final c
                                                              in list) {
                                                            final d =
                                                                (v - c).abs();
                                                            if (d < bd) {
                                                              best = c;
                                                              bd = d;
                                                            }
                                                          }
                                                          return best;
                                                        }

                                                        draftSessionSegments[
                                                                i] =
                                                            seg.copyWith(
                                                          isPause: nextPause,
                                                          durationMinutes:
                                                              snapNew(
                                                            nextPause
                                                                ? 10
                                                                : 25,
                                                          ),
                                                        );
                                                      }),
                                                      icon: Icon(
                                                        Icons.swap_horiz_rounded,
                                                        color: p.muted,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Entfernen',
                                                      onPressed: () =>
                                                          setSheet(() {
                                                        draftSessionSegments
                                                            .removeAt(i);
                                                      }),
                                                      icon: Icon(
                                                        Icons.close_rounded,
                                                        color: p.muted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ],
                                        const SizedBox(height: 16),
                                        dividerRow(),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: notesCtrl,
                                          minLines: 3,
                                          maxLines: 8,
                                          style: TextStyle(
                                            color: p.text,
                                            height: 1.45,
                                          ),
                                          decoration: InputDecoration(
                                            hintText:
                                                'Notizen, Links, Kurzinfos …',
                                            hintStyle: TextStyle(
                                              color: p.muted.withValues(
                                                alpha: 0.85,
                                              ),
                                            ),
                                            border: InputBorder.none,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  decoration: BoxDecoration(
                                    color: p.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: p.hairline),
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      childrenPadding:
                                          const EdgeInsets.fromLTRB(
                                            14,
                                            0,
                                            14,
                                            14,
                                          ),
                                      expandedCrossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      iconColor: p.muted,
                                      collapsedIconColor: p.muted,
                                      title: Text(
                                        'Weitere Optionen',
                                        style: TextStyle(
                                          color: p.text,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Ganztags · Zeit als Dauer eingeben',
                                        style: TextStyle(
                                          color: p.muted,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      children: [
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          'Ganztags',
                                          style: TextStyle(color: p.text),
                                        ),
                                        value: allDay,
                                        onChanged: (v) => setSheet(() {
                                          allDay = v;
                                          if (v) {
                                            draftStart = 0;
                                            draftEnd = 1440;
                                          }
                                        }),
                                      ),
                                      if (!allDay) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Zeit eingeben als',
                                          style: TextStyle(
                                            color: p.muted,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            ChoiceChip(
                                              label: const Text('Start/Ende'),
                                              selected: !useDurationInput,
                                              onSelected: (v) {
                                                if (!v) return;
                                                setSheet(
                                                  () => useDurationInput = false,
                                                );
                                              },
                                            ),
                                            ChoiceChip(
                                              label: const Text('Dauer'),
                                              selected: useDurationInput,
                                              onSelected: (v) {
                                                if (!v) return;
                                                setSheet(() {
                                                  useDurationInput = true;
                                                  syncDurationFromRange();
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                      ],
                                    ),
                                  ),
                                ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: p.bg,
                            border: Border(
                              top: BorderSide(color: p.hairline),
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            14,
                            10,
                            14,
                            14 + MediaQuery.of(context).padding.bottom,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (editing case final editTarget?)
                                IconButton(
                                  tooltip: 'Block löschen',
                                  onPressed: () {
                                    final rid = editTarget.id;
                                    _recordUndoSnapshot();
                                    setState(() {
                                      _getBlocksForDay(
                                        _selectedDate,
                                      ).removeWhere((x) => x.id == rid);
                                      _selectedBlockIds.remove(rid);
                                      _expandedBlockIds.remove(rid);
                                    });
                                    _schedulePersistDayPlans();
                                    Navigator.pop(context);
                                  },
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: p.muted,
                                  ),
                                ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Abbrechen',
                                  style: TextStyle(color: p.muted),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 26,
                                    vertical: 14,
                                  ),
                                  shape: const StadiumBorder(),
                                  elevation: kIsWeb ? 0 : 2,
                                  backgroundColor: p.text,
                                  foregroundColor: p.bg,
                                ),
                                onPressed: () async {
                                  await commit(setSheet);
                                },
                                child: Text(
                                  editing == null
                                      ? 'Block anlegen'
                                      : 'Übernehmen',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      titleCtrl.dispose();
      notesCtrl.dispose();
      subtaskInputCtrl.dispose();
      for (final c in subtaskCtrlById.values) {
        c.dispose();
      }
    });
  }

  void _togglePin(TimeBlock block) {
    if (block.isOvernightSlot) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Über-Nacht-Blöcke können nicht fixiert werden.'),
        ),
      );
      return;
    }
    _recordUndoSnapshot();
    setState(() {
      block.pinned = !block.pinned;
    });
    _schedulePersistDayPlans();
  }

  TimeBlock _shiftAfterPin(TimeBlock movable, TimeBlock pin) {
    final durBase = movable.allDay ? 180 : movable.spanMinutes;
    final dur = durBase.clamp(15, 1440);
    final start = pin.endMin >= 1440 ? 0 : pin.endMin;
    final totalEnd = start + dur;
    final subCopy = movable.subtasks
        .map((s) => BlockSubtask(id: _nextId(), title: s.title, done: s.done))
        .toList();
    if (totalEnd <= 1440) {
      return movable.copyWith(
        id: _nextId(),
        startMin: start,
        endMin: totalEnd,
        allDay: false,
        pinned: false,
        subtasks: subCopy,
      );
    }
    final wrappedEnd = totalEnd - 1440;
    return movable.copyWith(
      id: _nextId(),
      startMin: start,
      endMin: wrappedEnd,
      allDay: false,
      pinned: false,
      subtasks: subCopy,
    );
  }

  /// Nach Verschiebung: nicht-fixierte Blöcke dürfen fixierte nicht überlagern —
  /// wird bei Bedarf vor/nach dem Pin gesplittet oder geschoben.
  void _repairOverlapsWithPins(List<TimeBlock> day) {
    const minDur = 15;
    void sortDay() => day.sort((a, b) => a.startMin.compareTo(b.startMin));

    for (var iteration = 0; iteration < 48; iteration++) {
      final pins = day.where((b) => b.pinned).toList()
        ..sort((a, b) => a.startMin.compareTo(b.startMin));
      if (pins.isEmpty) break;

      TimeBlock? movableConflict;
      TimeBlock? pinHit;

      outer:
      for (final b in day.where((x) => !x.pinned).toList()) {
        for (final p in pins) {
          if (_blocksOverlap(b, p)) {
            movableConflict = b;
            pinHit = p;
            break outer;
          }
        }
      }

      if (movableConflict == null || pinHit == null) break;

      final b = movableConflict;
      final p = pinHit;

      day.remove(b);

      // Über Mitternacht oder andere nicht-lineare Slots: ganzen Block nach Pin-Ende schieben.
      if (!b.isLinearSlot || !p.isLinearSlot) {
        day.add(_shiftAfterPin(b, p));
        sortDay();
        continue;
      }

      // Über die gesamte Pin-Zeit hinweg → zwei freie Segmente davor/danach
      if (b.startMin < p.startMin && b.endMin > p.endMin) {
        final leftDur = p.startMin - b.startMin;
        final rightDur = b.endMin - p.endMin;
        if (leftDur >= minDur) {
          day.add(b.copyWith(endMin: p.startMin));
        }
        if (rightDur >= minDur) {
          day.add(
            b.copyWith(
              id: _nextId(),
              title: '${b.title} · später',
              startMin: p.endMin,
              endMin: b.endMin,
              pinned: false,
              subtasks: [],
            ),
          );
        }
        sortDay();
        continue;
      }

      // Komplett innerhalb der Pin-Zeit → nach Pin-Ende schieben (gleiche Dauer)
      if (b.startMin >= p.startMin && b.endMin <= p.endMin) {
        final dur = b.spanMinutes;
        var start = p.endMin;
        var end = start + dur;
        if (end <= 1440 && end - start >= minDur) {
          day.add(
            TimeBlock(
              id: _nextId(),
              title: b.title,
              startMin: start,
              endMin: end,
              emoji: b.emoji,
              colorLabel: b.colorLabel,
              pinned: false,
              notes: b.notes,
              recurrence: b.recurrence,
              recurrenceWeekdayMask: b.recurrenceWeekdayMask,
              recurrenceMonthDay: b.recurrenceMonthDay,
              customIconCodePoint: b.customIconCodePoint,
              customStripeHex: b.customStripeHex,
              subtasks: [],
              completed: false,
              muteReminders: b.muteReminders,
              sessionSegments: const [],
            ),
          );
        } else if (end > 1440) {
          final endWrap = end - 1440;
          if (endWrap >= minDur && start < 1440) {
            day.add(
              TimeBlock(
                id: _nextId(),
                title: b.title,
                startMin: start,
                endMin: endWrap,
                emoji: b.emoji,
                colorLabel: b.colorLabel,
                pinned: false,
                notes: b.notes,
                recurrence: b.recurrence,
                recurrenceWeekdayMask: b.recurrenceWeekdayMask,
                recurrenceMonthDay: b.recurrenceMonthDay,
                customIconCodePoint: b.customIconCodePoint,
                customStripeHex: b.customStripeHex,
                subtasks: [],
                completed: false,
                muteReminders: b.muteReminders,
                sessionSegments: const [],
              ),
            );
          }
        }
        sortDay();
        continue;
      }

      // Ragt nur von links in den Pin → Teil vor dem Pin behalten
      if (b.startMin < p.startMin &&
          b.endMin > p.startMin &&
          b.endMin <= p.endMin) {
        if (p.startMin - b.startMin >= minDur) {
          day.add(b.copyWith(endMin: p.startMin));
        }
        sortDay();
        continue;
      }

      // Start liegt im Pin, Ende danach → nur Segment nach Pin-Ende
      if (b.startMin >= p.startMin &&
          b.startMin < p.endMin &&
          b.endMin > p.endMin) {
        if (b.endMin - p.endMin >= minDur) {
          day.add(b.copyWith(startMin: p.endMin, endMin: b.endMin));
        }
        sortDay();
        continue;
      }

      sortDay();
    }
    sortDay();
  }

  bool _canMergeSelection() {
    final unpinnedSel = _getBlocksForDay(
      _selectedDate,
    ).where((b) => _selectedBlockIds.contains(b.id) && !b.pinned).length;
    return unpinnedSel >= 2;
  }

  void _splitBlock(TimeBlock block) {
    if (!block.isLinearSlot || block.allDay) return;
    if (block.duration < 30) return;
    final half = block.startMin + (block.duration ~/ 2);
    _recordUndoSnapshot();
    setState(() {
      final blocks = _getBlocksForDay(_selectedDate);
      final i = blocks.indexWhere((b) => b.id == block.id);
      if (i < 0) return;
      final first = block.copyWith(endMin: half, sessionSegments: []);
      final second = _newBlock(
        '${block.title} (Teil 2)',
        half,
        block.endMin,
        block.colorLabel,
        '',
        pinned: block.pinned,
        recurrence: block.recurrence,
        recurrenceWeekdayMask: block.recurrenceWeekdayMask,
        recurrenceMonthDay: block.recurrenceMonthDay,
        customIconCodePoint: block.customIconCodePoint,
        customStripeHex: block.customStripeHex,
        notes: block.notes,
        muteReminders: block.muteReminders,
        sessionSegments: [],
      );
      blocks[i] = first;
      blocks.insert(i + 1, second);
    });
    _schedulePersistDayPlans();
  }

  void _duplicateBlock(TimeBlock block) {
    if (block.allDay || !block.isLinearSlot) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Duplizieren geht bei Ganztags- oder Über-Nacht-Blöcken nicht.',
          ),
        ),
      );
      return;
    }
    final start = (block.endMin + 15).clamp(0, 1410);
    final end = start + block.spanMinutes;
    if (end > 1440) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kopie würde den Tag überschreiten — Block kürzen oder später im Tag ansetzen.',
          ),
        ),
      );
      return;
    }
    _recordUndoSnapshot();
    setState(() {
      _getBlocksForDay(_selectedDate).add(
        _newBlock(
          '${block.title} (Kopie)',
          start,
          end,
          block.colorLabel,
          '',
          pinned: false,
          allDay: false,
          recurrence: block.recurrence,
          recurrenceWeekdayMask: block.recurrenceWeekdayMask,
          recurrenceMonthDay: block.recurrenceMonthDay,
          customIconCodePoint: block.customIconCodePoint,
          customStripeHex: block.customStripeHex,
          notes: block.notes,
          completed: false,
          muteReminders: block.muteReminders,
          subtasks: block.subtasks
              .map(
                (s) =>
                    BlockSubtask(id: _nextId(), title: s.title, done: s.done),
              )
              .toList(),
          sessionSegments: [
            for (final s in block.sessionSegments)
              BlockSessionSegment(
                id: _nextId(),
                durationMinutes: s.durationMinutes,
                isPause: s.isPause,
              ),
          ],
        ),
      );
    });
    _schedulePersistDayPlans();
  }

  void _moveToBacklog(TimeBlock block) {
    _recordUndoSnapshot();
    setState(() {
      _getBlocksForDay(_selectedDate).removeWhere((b) => b.id == block.id);
      _backlog.add(block.copyWith(id: _nextId()));
      _selectedBlockIds.remove(block.id);
    });
    _schedulePersistDayPlans();
  }

  /// Ablage-Item: Datum, ggf. manuelle Zeiten, ggf. vorhandenen Block ersetzen.
  Future<void> _placeBacklogItem(
    TimeBlock b, {
    required VoidCallback onPlaced,
  }) async {
    var targetDay = _onlyDay(_selectedDate);
    TimeBlock? blockToReplace;
    var useAblageTimes = true;
    var draftStart = b.startMin;
    var draftEnd = b.endMin;

    TimeOfDay t0(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);

    Future<void> pickDate(StateSetter setL) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: targetDay,
        firstDate: DateTime(2020),
        lastDate: DateTime(2040),
      );
      if (picked == null) return;
      setL(() {
        targetDay = _onlyDay(picked);
        blockToReplace = null;
      });
    }

    Future<void> pickStart(StateSetter setL) async {
      final t = await showTimePicker(
        context: context,
        initialTime: t0(draftStart),
      );
      if (t == null) return;
      setL(() {
        draftStart = t.hour * 60 + t.minute;
        if (draftStart < draftEnd) {
          if (draftEnd - draftStart < 15) {
            draftEnd = (draftStart + 15).clamp(0, 1440);
          }
        } else if (draftStart == draftEnd) {
          draftEnd = (draftStart + 15) % 1440;
        }
      });
    }

    Future<void> pickEnd(StateSetter setL) async {
      final t = await showTimePicker(
        context: context,
        initialTime: t0(draftEnd),
      );
      if (t == null) return;
      setL(() {
        draftEnd = t.hour * 60 + t.minute;
        if (draftStart == draftEnd) {
          draftStart = (draftEnd - 15 + 1440) % 1440;
        }
      });
    }

    if (!mounted) return;
    final p = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setL) {
            final canReplace =
                _getBlocksForDay(targetDay).where((x) => !x.pinned).toList()
                  ..sort((a, c) => a.startMin.compareTo(c.startMin));
            final basePad = MediaQuery.of(sheetCtx).viewInsets.bottom;

            void apply() {
              if (blockToReplace != null && blockToReplace!.pinned) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Fixierte Blöcke kannst du nicht ersetzen.'),
                  ),
                );
                return;
              }
              int sm;
              int em;
              bool ad;
              if (blockToReplace != null) {
                sm = blockToReplace!.startMin;
                em = blockToReplace!.endMin;
                ad = blockToReplace!.allDay;
              } else if (b.allDay) {
                sm = 0;
                em = 1440;
                ad = true;
              } else if (useAblageTimes) {
                sm = b.startMin;
                em = b.endMin;
                ad = b.allDay;
              } else {
                sm = draftStart;
                em = draftEnd;
                ad = false;
                if (sm == em) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Start und Ende dürfen nicht identisch sein.',
                      ),
                    ),
                  );
                  return;
                }
              }
              final idx = _backlog.indexWhere((x) => x.id == b.id);
              if (idx < 0) {
                Navigator.of(sheetCtx).pop();
                return;
              }
              _stashFreeformForCurrentDay();
              _recordUndoSnapshot();
              setState(() {
                final list = _getBlocksForDay(targetDay);
                if (blockToReplace != null) {
                  list.removeWhere((x) => x.id == blockToReplace!.id);
                }
                list.add(
                  b.copyWith(
                    id: _nextId(),
                    startMin: sm,
                    endMin: em,
                    allDay: ad,
                  ),
                );
                _backlog.removeAt(idx);
                _repairOverlapsWithPins(list);
                _ensureDayExists(targetDay);
                if (targetDay != _onlyDay(_selectedDate)) {
                  _selectedDate = targetDay;
                }
                _selectedBlockIds.clear();
              });
              _schedulePersistDayPlans();
              _loadFreeformForCurrentDay();
              onPlaced();
              Navigator.of(sheetCtx).pop();
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + basePad),
              child: SingleChildScrollView(
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
                          color: p.hairline,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Text(
                      'In Plan legen',
                      style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      b.title,
                      style: Theme.of(sheetCtx).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: p.muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.calendar_today_outlined,
                        color: p.muted,
                        size: 22,
                      ),
                      title: const Text('Datum'),
                      subtitle: Text(
                        _dateLabel(targetDay),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                      onTap: () => pickDate(setL),
                    ),
                    if (blockToReplace == null && !b.allDay) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Zeiten',
                              style: Theme.of(sheetCtx).textTheme.labelLarge
                                  ?.copyWith(
                                    color: p.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          FilterChip(
                            label: const Text('Ablage'),
                            selected: useAblageTimes,
                            onSelected: (v) {
                              if (v) {
                                setL(() {
                                  useAblageTimes = true;
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('Manuell'),
                            selected: !useAblageTimes,
                            onSelected: (v) {
                              if (v) {
                                setL(() {
                                  useAblageTimes = false;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      if (useAblageTimes) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_fmtMin(b.startMin)} – ${_fmtMin(b.endMin)}'
                          '${b.isOvernightSlot ? " (über Mitternacht)" : ""}',
                          style: Theme.of(sheetCtx).textTheme.bodyMedium
                              ?.copyWith(
                                color: p.text,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ] else ...[
                        const SizedBox(height: 10),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.schedule_rounded, color: p.muted),
                          title: const Text('Start'),
                          subtitle: Text(
                            _fmtMin(draftStart),
                            style: TextStyle(
                              color: p.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () => pickStart(setL),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.schedule_rounded, color: p.muted),
                          title: const Text('Ende'),
                          subtitle: Text(
                            _fmtMin(draftEnd),
                            style: TextStyle(
                              color: p.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () => pickEnd(setL),
                        ),
                      ],
                    ] else if (blockToReplace == null && b.allDay) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Ganztags (0:00 – 24:00)',
                        style: Theme.of(sheetCtx).textTheme.bodyMedium
                            ?.copyWith(
                              color: p.text,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Block ersetzen (optional)',
                      style: Theme.of(sheetCtx).textTheme.labelLarge?.copyWith(
                        color: p.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: p.bg.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.hairline),
                      ),
                      child: DropdownButton<String?>(
                        value:
                            blockToReplace != null &&
                                canReplace.any(
                                  (x) => x.id == blockToReplace!.id,
                                )
                            ? blockToReplace!.id
                            : null,
                        isExpanded: true,
                        hint: const Text('— keinen Block ersetzen'),
                        underline: const SizedBox.shrink(),
                        dropdownColor: p.surface,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('— keinen Block ersetzen'),
                          ),
                          ...canReplace.map(
                            (bl) => DropdownMenuItem<String?>(
                              value: bl.id,
                              child: Text(
                                '${_fmtBlockRange(bl)} · ${bl.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (id) {
                          setL(() {
                            if (id == null) {
                              blockToReplace = null;
                            } else {
                              blockToReplace = canReplace.firstWhere(
                                (x) => x.id == id,
                              );
                              useAblageTimes = true;
                            }
                          });
                        },
                      ),
                    ),
                    if (blockToReplace != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Der Eintrag aus der Ablage übernimmt den Zeitraum „${_fmtBlockRange(blockToReplace!)}“.',
                        style: Theme.of(
                          sheetCtx,
                        ).textTheme.bodySmall?.copyWith(color: p.muted),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: apply,
                      child: const Text('In Plan legen'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _addQuickBacklogItem(String title, String colorLabel) {
    final t = title.trim();
    _recordUndoSnapshot();
    setState(() {
      _backlog.add(
        _newBlock(t.isEmpty ? 'Neuer Block' : t, 540, 600, colorLabel, ''),
      );
    });
  }

  void _openBacklogSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.bg,
      builder: (sheetContext) {
        final p = context.palette;
        final h = MediaQuery.sizeOf(sheetContext).height * 0.56;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: SizedBox(
                    height: h.clamp(320, 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Ablage (später in Plan legen)',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: p.text,
                              ),
                        ),
                        const SizedBox(height: 10),
                        _BacklogQuickComposer(
                          palette: p,
                          categoryLabels: _categoryOrder
                              .where((k) => _categoryColors.containsKey(k))
                              .toList(),
                          fallbackCategory: _fallbackCategoryLabel(),
                          onSubmit: (title, cat) {
                            _addQuickBacklogItem(title, cat);
                            setModal(() {});
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: const Text('In Ablage gelegt'),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                                backgroundColor: p.surface,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Divider(
                          height: 1,
                          color: p.hairline.withValues(alpha: 0.85),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: _backlog.isEmpty
                              ? _freiraumBacklogArea(context)
                              : ListView.builder(
                                  itemCount: _backlog.length,
                                  itemBuilder: (context, i) {
                                    final b = _backlog[i];
                                    return Card(
                                      color: p.surface,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: BorderSide(color: p.hairline),
                                      ),
                                      child: ListTile(
                                        leading: Icon(
                                          _resolveBlockIcon(b),
                                          color: p.muted.withValues(
                                            alpha: 0.85,
                                          ),
                                        ),
                                        title: Text(
                                          b.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        subtitle: Text(
                                          '${_fmtMin(b.startMin)} - ${_fmtMin(b.endMin)}',
                                        ),
                                        trailing: Icon(
                                          Icons.add_circle_outline,
                                          color: p.text.withValues(alpha: 0.5),
                                        ),
                                        onTap: () async {
                                          await _placeBacklogItem(
                                            b,
                                            onPlaced: () => setModal(() {}),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openPlannerModeSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.bg,
      builder: (sheetContext) {
        final p = context.palette;
        final sw = MediaQuery.sizeOf(sheetContext).width;
        final maxH = MediaQuery.sizeOf(sheetContext).height * 0.58;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH.clamp(340, 620)),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: p.hairline,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Text(
                        'Preset & Flex',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: p.text,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Preset für den gewählten Tag',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: p.muted,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      _presetDropdownForHeadline(
                        sheetContext,
                        sw - 24,
                        compact: true,
                        dismissHostingOverlay: () {
                          Navigator.of(sheetContext).maybePop();
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hauptplan: ${_displayNameForPresetKey(_resolvedActivePresetKey())} (open end). '
                        'Andere Presets nur für diesen Tag, oder als neuer Hauptplan.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.muted,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Flex-Modus',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: p.muted,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: FilterChip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              showCheckmark: true,
                              selected: _flexMode,
                              onSelected: (v) {
                                setState(() {
                                  _flexMode = v;
                                  if (!v) {
                                    _flexReorderGhostRange = null;
                                    _selectedBlockIds.clear();
                                  }
                                });
                                if (v) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                              label: Text(
                                'Flex Modus',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Flex-Modus & Empfehlung',
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _showFlexModeInfo();
                            },
                            icon: Icon(
                              Icons.info_outline_rounded,
                              size: 22,
                              color: p.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetContext).pop();
                            await _openPresetTaskTemplatesSheet();
                          },
                          icon: Icon(
                            Icons.tune_rounded,
                            size: 20,
                            color: p.accent,
                          ),
                          label: Text(
                            'Preset-Raster bearbeiten',
                            style: TextStyle(
                              color: p.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFlexModeInfo() {
    final p = context.palette;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final bodyStyle = Theme.of(
          ctx,
        ).textTheme.bodyMedium?.copyWith(color: p.muted, height: 1.4);
        return AlertDialog(
          title: Text(
            'Flex-Modus',
            style: Theme.of(
              ctx,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: bodyStyle,
                    children: [
                      TextSpan(
                        text: 'Empfehlung: ',
                        style: bodyStyle?.copyWith(
                          color: p.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text:
                            'Plan Luft am Anfang und Ende ein — dann kannst du markierte Blöcke bündig verschieben. '
                            'Fixierte Blöcke bleiben stehen (⋯ → Block fixieren); andere rutschen drumherum '
                            'und werden bei Überlappung automatisch vorher/nachher gesplittet.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Im Flex-Modus wählst du Blöcke durch Tippen auf Karte, Streifen links, Uhrzeit rechts '
                  'oder den Auswahl-Kreis. Dann kannst du alle markierten normalen Zeitblöcke gemeinsam '
                  'nach vorne oder hinten schieben '
                  'über „Verschieben“ (Zifferblatt drehen) oder „+15“ / „−15“ (je 15 Minuten). '
                  'Zum neu sortieren: markierte Blöcke wählen (dazwischen liegende rutschen automatisch '
                  'in die Markierung) und an einem Griff rechts (Striche) '
                  'festhalten und verschieben — sie wandern zusammen; am Ende gibt es ein '
                  'kurzes leichtes Vibrieren (Haptik). '
                  'Kurz gedrückt halten auf einem Block öffnet die Bearbeitung (wie außerhalb des Flex-Modus). '
                  'So passt du den Tag an, wenn sich etwas verschiebt — ohne jeden Block einzeln zu öffnen.\n\n'
                  'Fixierte Blöcke, Ganztags- und Über-Nacht-Slots werden beim Schieben automatisch übersprungen. '
                  'Wenn etwas mit fixierten Stehblöcken kollidieren würde, wird der Plan danach bereinigt '
                  '(Teilen oder Verschieben an den Pin).\n\n'
                  'Mit „Merge“ kannst du mehrere ausgewählte Blöcke zusammenfassen. '
                  'Ist der Flex-Modus aus, haben „+15“ und „−15“ keine Wirkung; Auswahl und Bearbeiten gehen trotzdem.',
                  style: bodyStyle,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
  }

  void _shiftSelectedBlocks(int deltaMin) {
    if (!_flexMode) return;
    _recordUndoSnapshot();
    setState(() {
      final dayBlocks = _getBlocksForDay(_selectedDate);
      for (final b in dayBlocks) {
        if (!_selectedBlockIds.contains(b.id)) continue;
        if (b.pinned) continue;
        if (b.allDay || b.isOvernightSlot || !b.isLinearSlot) continue;
        final ns = (b.startMin + deltaMin).clamp(0, 1425);
        final nd = (b.endMin + deltaMin).clamp(ns + 15, 1440);
        b.startMin = ns;
        b.endMin = nd;
      }
      _sortBlocksChronologically(dayBlocks);
      _repairOverlapsWithPins(dayBlocks);
      _repairUnpinnedLinearOverlaps(dayBlocks);
      _repairOverlapsWithPins(dayBlocks);
    });
    _schedulePersistDayPlans();
    _offerUndoSnack(
      'Zeiten verschoben – „Rückgängig“ verwenden, wenn es dir nicht gefällt.',
    );
  }

  void _mergeSelectedBlocks() {
    final dayBlocks = _getBlocksForDay(_selectedDate);
    final selected = dayBlocks
        .where((b) => _selectedBlockIds.contains(b.id) && !b.pinned)
        .toList();
    if (selected.length < 2) return;

    selected.sort((a, b) => a.startMin.compareTo(b.startMin));
    final start = selected.first.startMin;
    final end = selected.map((b) => b.endMin).reduce((a, b) => a > b ? a : b);
    final mergedTitle = selected.map((b) => b.title).join(' + ');
    final colorLabel = selected.first.colorLabel;
    _recordUndoSnapshot();
    setState(() {
      dayBlocks.removeWhere(
        (b) => _selectedBlockIds.contains(b.id) && !b.pinned,
      );
      dayBlocks.add(
        _newBlock(
          mergedTitle.length > 70
              ? '${mergedTitle.substring(0, 70)}...'
              : mergedTitle,
          start,
          end,
          colorLabel,
          '',
          pinned: false,
          recurrence: selected.first.recurrence,
          recurrenceWeekdayMask: selected.first.recurrenceWeekdayMask,
          recurrenceMonthDay: selected.first.recurrenceMonthDay,
          customIconCodePoint: selected.first.customIconCodePoint,
          customStripeHex: selected.first.customStripeHex,
        ),
      );
      _selectedBlockIds.clear();
    });
    _schedulePersistDayPlans();
    _offerUndoSnack(
      'Blöcke zusammengeführt – kannst du hier oder oben rückgängig machen.',
    );
  }

  void _openPresetWindowDialog() {
    var selectedPresetKey = _resolvedActivePresetKey();
    var presetWeekdayMask = 0;
    var fromDate = _onlyDay(_selectedDate);
    var toDate = _onlyDay(_selectedDate.add(const Duration(days: 7)));
    var openEnd = false;

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            const dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
            final p = context.palette;

            Future<void> pickBound({required bool isFrom}) async {
              final initial = isFrom ? fromDate : toDate;
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2024),
                lastDate: DateTime(2035),
              );
              if (picked == null) return;
              setInnerState(() {
                if (isFrom) {
                  fromDate = _onlyDay(picked);
                  if (fromDate.isAfter(toDate)) toDate = fromDate;
                } else {
                  toDate = _onlyDay(picked);
                  if (toDate.isBefore(fromDate)) fromDate = toDate;
                }
              });
            }

            Widget dateRow({
              required String label,
              required DateTime value,
              required VoidCallback onTap,
            }) {
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: p.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _dateShortDe(value),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: p.text,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return AlertDialog(
              title: const Text('Preset-Zeitraum einstellen'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ignore: deprecated_member_use
                    DropdownButtonFormField<String>(
                      value: selectedPresetKey,
                      dropdownColor: context.palette.surface,
                      items: _presetMenuItems(),
                      onChanged: (v) {
                        if (v == null) return;
                        if (v == _kCreatePresetMenuValue) {
                          unawaited(() async {
                            final key = await _promptAndCreateUserPreset();
                            if (key == null) return;
                            setInnerState(() => selectedPresetKey = key);
                          }());
                          return;
                        }
                        if (v == _kHauptplanMenuValue) {
                          setInnerState(
                            () => selectedPresetKey =
                                _resolvedActivePresetKey(),
                          );
                          return;
                        }
                        setInnerState(() => selectedPresetKey = v);
                      },
                      decoration: const InputDecoration(labelText: 'Preset'),
                    ),
                    const SizedBox(height: 10),
                    dateRow(
                      label: 'Von',
                      value: fromDate,
                      onTap: () => pickBound(isFrom: true),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Open End (Hauptplan)'),
                      subtitle: const Text(
                        'Kein Endedatum — gilt ab „Von“ als Standard. '
                        'Zeitraum ohne Open End ist nur zwischenzeitlich.',
                      ),
                      value: openEnd,
                      onChanged: (v) => setInnerState(() => openEnd = v),
                    ),
                    if (!openEnd)
                      dateRow(
                        label: 'Bis',
                        value: toDate,
                        onTap: () => pickBound(isFrom: false),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Bis: Open End',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: p.text,
                              ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Wochentage im Zeitraum',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.palette.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: List.generate(7, (i) {
                        final on =
                            presetWeekdayMask == 0 ||
                            ((presetWeekdayMask >> i) & 1) != 0;
                        return FilterChip(
                          label: Text(dayNames[i]),
                          selected: on,
                          onSelected: (_) {
                            setInnerState(() {
                              presetWeekdayMask = _toggleWeekdayInMask(
                                presetWeekdayMask,
                                i,
                              );
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Leer = jeden Tag. Sonst nur markierte Wochentage.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () {
                    final from = fromDate;
                    final to = openEnd ? null : toDate;
                    if (to != null && from.isAfter(to)) return;
                    _recordUndoSnapshot(markSelectedDayAsIndividual: false);
                    setState(() {
                      if (openEnd) {
                        _presetWindows.removeWhere((w) => w.isOpenEnd);
                        _activePresetKey = selectedPresetKey;
                        _sanitizeActivePresetKeyIfStale();
                        unawaited(_saveActivePresetKey());
                      }
                      _presetWindows.add(
                        PresetWindow(
                          from: from,
                          to: to,
                          presetKey: selectedPresetKey,
                          weekdayMask: presetWeekdayMask,
                        ),
                      );
                      _applyPresetAcrossWindow(
                        from,
                        to,
                        selectedPresetKey,
                        presetWeekdayMask,
                      );
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Anwenden'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _applyPresetAcrossWindow(
    DateTime from,
    DateTime? to,
    String presetKey,
    int weekdayMask,
  ) {
    void applyDay(DateTime cursor) {
      if (!_weekdayMatchesPreset(cursor, weekdayMask)) return;
      _days[cursor] = _buildPresetBlocksForKey(presetKey);
      _dayPlanPresetKind[cursor] = presetKey;
    }

    if (to != null) {
      DateTime cursor = _onlyDay(from);
      final end = _onlyDay(to);
      while (!cursor.isAfter(end)) {
        applyDay(cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    } else {
      final start = _onlyDay(from);
      applyDay(_onlyDay(_selectedDate));
      for (final day in _days.keys.toList()) {
        if (day.isBefore(start)) continue;
        if (_dayPlanPresetKind[day] == _kIndividualDayPresetKey) continue;
        applyDay(day);
      }
    }
    _schedulePersistDayPlans();
    _ensureDayExists(_selectedDate);
  }

  PresetWindow? _presetForDate(DateTime day) {
    final d = _onlyDay(day);
    PresetWindow? openEnd;
    for (final w in _presetWindows.reversed) {
      if (!w.contains(d)) continue;
      if (!w.matchesWeekday(d)) continue;
      if (!w.isOpenEnd) return w;
      openEnd ??= w;
    }
    return openEnd;
  }

  void _clearSelection() {
    setState(_selectedBlockIds.clear);
  }

  void _exitFlexMode() {
    setState(() {
      _flexMode = false;
      _flexReorderGhostRange = null;
      _selectedBlockIds.clear();
    });
  }

  void _flexSelectAllReorderable(List<TimeBlock> blocks) {
    if (!_flexMode) return;
    final ids =
        blocks.where(_flexBlockAllowsDragReorder).map((b) => b.id).toList();
    if (ids.isEmpty) return;
    setState(() {
      _selectedBlockIds
        ..clear()
        ..addAll(ids);
    });
  }

  Future<void> _promptRenameCategoryDialog(String current) async {
    final ctrl = TextEditingController(text: current);
    try {
      final next = await showDialog<String>(
        context: context,
        builder: (dctx) {
          return AlertDialog(
            title: const Text('Kategorie umbenennen'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Neuer Name'),
              onSubmitted: (_) => Navigator.pop(dctx, ctrl.text.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      if (next == null || next.isEmpty || next == current) return;
      if (_categoryColors.containsKey(next)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dieser Name existiert bereits')),
        );
        return;
      }
      await _renameCategoryEverywhere(current, next);
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _promptAddCategoryDialog() async {
    final ctrl = TextEditingController();
    try {
      final added = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Neue Kategorie'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Name (z. B. Sport)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('Anlegen'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (added == null || added.trim().isEmpty) return;
      if (_categoryColors.containsKey(added.trim())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dieser Name existiert bereits')),
        );
        return;
      }
      await _addNewCategory(added.trim());
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _promptDeleteCategoryDialog(
    BuildContext dialogCtx,
    String name,
    void Function() onDeletedMatchesExpanded,
  ) async {
    if (kCanonicalDefaultCategoryOrder.contains(name)) return;
    final replacement = _replacementCategoryLabelBeforeRemove(name);
    final ok = await showDialog<bool>(
      context: dialogCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('Kategorie löschen?'),
        content: Text(
          'Alle Blöcke, Ablage-Einträge und Vorlagen mit dieser Kategorie werden '
          'auf „$replacement“ umgestellt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    _recordUndoSnapshot(markSelectedDayAsIndividual: false);
    await _deleteCategoryEverywhere(name, replacement);
    onDeletedMatchesExpanded();
  }

  Future<void> _openCategoryColorSettings() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final p = ctx.palette;
        String expandedCategory = '';
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: const Text('Kategorien & Farben'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ..._categoryOrder.map((name) {
                        final c =
                            _categoryColors[name] ?? const Color(0xFF6B7280);
                        final isOpen = expandedCategory == name;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: c,
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  color: p.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                kColorMeaning[name] ?? 'Eigene Kategorie',
                                style: TextStyle(color: p.muted, fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Umbenennen',
                                    onPressed: () async {
                                      await _promptRenameCategoryDialog(name);
                                      if (!mounted) return;
                                      setD(() {});
                                    },
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                      color: p.muted,
                                    ),
                                  ),
                                  if (!kCanonicalDefaultCategoryOrder.contains(
                                    name,
                                  ))
                                    IconButton(
                                      tooltip: 'Kategorie löschen',
                                      onPressed: () async {
                                        await _promptDeleteCategoryDialog(
                                          ctx,
                                          name,
                                          () {
                                            setD(() {
                                              if (expandedCategory == name) {
                                                expandedCategory = '';
                                              }
                                            });
                                          },
                                        );
                                        if (!mounted) return;
                                        setD(() {});
                                      },
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20,
                                        color: p.muted,
                                      ),
                                    ),
                                  TextButton(
                                    onPressed: () {
                                      setD(() {
                                        expandedCategory = isOpen ? '' : name;
                                      });
                                    },
                                    child: Text(isOpen ? 'Zu' : 'Farbe'),
                                  ),
                                ],
                              ),
                            ),
                            if (isOpen)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  52,
                                  0,
                                  10,
                                  10,
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final sw
                                        in _allCategoryPresetSwatches())
                                      GestureDetector(
                                        onTap: () async {
                                          if (!mounted) return;
                                          setState(() {
                                            _categoryColors[name] = sw;
                                          });
                                          setD(() {});
                                          await _saveCategoryColors();
                                        },
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: sw,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color:
                                                      c.toARGB32() ==
                                                          sw.toARGB32()
                                                      ? p.accent
                                                      : p.hairline,
                                                  width:
                                                      c.toARGB32() ==
                                                          sw.toARGB32()
                                                      ? 2.2
                                                      : 1.0,
                                                ),
                                              ),
                                            ),
                                            if (!_isBuiltinCategorySwatchColor(
                                              sw,
                                            ))
                                              Positioned(
                                                right: -5,
                                                top: -5,
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () async {
                                                    if (!mounted) return;
                                                    setState(() {
                                                      _customCategorySwatches
                                                          .removeWhere(
                                                            (x) =>
                                                                x.toARGB32() ==
                                                                sw.toARGB32(),
                                                          );
                                                      if (_categoryColors[name]
                                                              ?.toARGB32() ==
                                                          sw.toARGB32()) {
                                                        _categoryColors[name] =
                                                            kDefaultCategoryColors[name] ??
                                                            kCategoryColorSwatches
                                                                .first;
                                                      }
                                                    });
                                                    await _saveCustomCategorySwatches();
                                                    await _saveCategoryColors();
                                                    setD(() {});
                                                  },
                                                  child: Container(
                                                    width: 16,
                                                    height: 16,
                                                    decoration: BoxDecoration(
                                                      color: p.surface,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: p.hairline,
                                                      ),
                                                    ),
                                                    child: Icon(
                                                      Icons.close_rounded,
                                                      size: 11,
                                                      color: p.muted,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    IconButton(
                                      tooltip:
                                          'Eigene Farbe wählen — Farbplatte & Regenbogen',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () async {
                                        final cur = _categoryColors[name];
                                        final picked =
                                            await _pickCustomColorSheet(
                                              cur ?? c,
                                            );
                                        if (picked == null || !mounted) return;
                                        final addToPresets =
                                            !_isBuiltinCategorySwatchColor(
                                              picked,
                                            ) &&
                                            !_customCategorySwatches.any(
                                              (x) =>
                                                  x.toARGB32() ==
                                                  picked.toARGB32(),
                                            );
                                        setState(() {
                                          _categoryColors[name] = picked;
                                          if (addToPresets) {
                                            _customCategorySwatches.add(picked);
                                          }
                                        });
                                        setD(() {});
                                        await _saveCategoryColors();
                                        if (addToPresets) {
                                          await _saveCustomCategorySwatches();
                                        }
                                      },
                                      icon: Icon(
                                        Icons.add_circle_outline,
                                        color: p.accent,
                                        size: 24,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final def =
                                            kDefaultCategoryColors[name] ??
                                            kCategoryColorSwatches.first;
                                        if (!mounted) return;
                                        setState(() {
                                          _categoryColors[name] = def;
                                        });
                                        setD(() {});
                                        await _saveCategoryColors();
                                      },
                                      child: const Text('Standardfarbe'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      }),
                      TextButton.icon(
                        onPressed: () async {
                          await _promptAddCategoryDialog();
                          if (!mounted) return;
                          setD(() {});
                        },
                        icon: Icon(Icons.add_rounded, color: p.accent),
                        label: Text(
                          'Neue Kategorie hinzufügen',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: p.accent.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _showColorLegend();
                    });
                  },
                  child: const Text('Farb-Legende'),
                ),
                TextButton(
                  onPressed: () async {
                    setState(() {
                      _applyCategorySnapshot(
                        List<String>.from(kCanonicalDefaultCategoryOrder),
                        Map<String, Color>.from(kDefaultCategoryColors),
                      );
                    });
                    setD(() {});
                    await _saveCategoryColors();
                  },
                  child: const Text('Alles Standard'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fertig'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showColorLegend() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Farb-System'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _categoryOrder
                  .where((n) => _categoryColors.containsKey(n))
                  .map((name) {
                    final col = _categoryColors[name]!;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 8, backgroundColor: col),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$name: ${kColorMeaning[name] ?? 'Eigene Kategorie'}',
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
  }

  String _nextId() {
    _idCounter += 1;
    return 'b$_idCounter';
  }

  TimeBlock _newBlock(
    String title,
    int startMin,
    int endMin,
    String colorLabel,
    String emoji, {
    bool pinned = false,
    bool allDay = false,
    BlockRecurrence recurrence = BlockRecurrence.none,
    int recurrenceWeekdayMask = 0,
    int recurrenceMonthDay = 1,
    int? customIconCodePoint,
    String? customStripeHex,
    String notes = '',
    List<BlockSubtask>? subtasks,
    List<BlockSessionSegment>? sessionSegments,
    bool completed = false,
    bool muteReminders = false,
  }) {
    return TimeBlock(
      id: _nextId(),
      title: title,
      startMin: startMin,
      endMin: endMin,
      colorLabel: colorLabel,
      emoji: emoji,
      pinned: pinned,
      allDay: allDay,
      recurrence: recurrence,
      recurrenceWeekdayMask: recurrenceWeekdayMask,
      recurrenceMonthDay: recurrenceMonthDay,
      customIconCodePoint: customIconCodePoint,
      customStripeHex: customStripeHex,
      notes: notes,
      subtasks: subtasks,
      sessionSegments: sessionSegments,
      completed: completed,
      muteReminders: muteReminders,
    );
  }

  void _seedBacklog() {
    _backlog.addAll([
      _newBlock('Task Splitter bauen', 660, 720, 'Fokus', ''),
      _newBlock('Inbox zero', 930, 975, 'Fokus', ''),
      _newBlock('Abendroutine', 1260, 1320, 'Routine', ''),
    ]);
  }

  String _sessionLiveStorageKey(TimeBlock b) {
    final d = _onlyDay(_selectedDate);
    return '${d.year}-${d.month}-${d.day}_${b.id}';
  }

  _SessionLiveProgress _sessionLiveProgress(TimeBlock b) {
    final k = _sessionLiveStorageKey(b);
    return _sessionLiveByKey.putIfAbsent(
      k,
      () => _SessionLiveProgress(0, DateTime.now()),
    );
  }

  void _advanceSessionLive(TimeBlock b) {
    setState(() {
      final p = _sessionLiveProgress(b);
      p.segmentIndex += 1;
      p.phaseStartedAt = DateTime.now();
    });
  }

  void _resetSessionLive(TimeBlock b) {
    setState(() {
      _sessionLiveByKey[_sessionLiveStorageKey(b)] =
          _SessionLiveProgress(0, DateTime.now());
    });
  }

  void _pickDate(DateTime d) {
    final next = _onlyDay(d);
    if (next == _onlyDay(_selectedDate)) return;
    _stashFreeformForCurrentDay();
    _scheduleFreeformSave();
    setState(() {
      _selectedDate = next;
      _ensureDayExists(next);
      _selectedBlockIds.clear();
      _sessionLiveByKey.clear();
    });
    _loadFreeformForCurrentDay();
  }

  void _toggleBlockSelect(String blockId) {
    if (!_flexMode) return;
    setState(() {
      if (_selectedBlockIds.contains(blockId)) {
        _selectedBlockIds.remove(blockId);
      } else {
        _selectedBlockIds.add(blockId);
        _stretchFlexReorderSelectionInPlace(_getBlocksForDay(_selectedDate));
      }
    });
  }
}

/// Quick capture for the backlog sheet: title + category, then add via [onSubmit].
class _BacklogQuickComposer extends StatefulWidget {
  const _BacklogQuickComposer({
    required this.palette,
    required this.categoryLabels,
    required this.fallbackCategory,
    required this.onSubmit,
  });

  final AppPalette palette;
  final List<String> categoryLabels;
  final String fallbackCategory;
  final void Function(String title, String colorLabel) onSubmit;

  @override
  State<_BacklogQuickComposer> createState() => _BacklogQuickComposerState();
}

class _BacklogQuickComposerState extends State<_BacklogQuickComposer> {
  late final TextEditingController _titleController;
  late String _category;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    final labels = _effectiveLabels();
    _category = labels.contains(widget.fallbackCategory)
        ? widget.fallbackCategory
        : labels.first;
  }

  List<String> _effectiveLabels() {
    if (widget.categoryLabels.isNotEmpty) return widget.categoryLabels;
    return <String>[widget.fallbackCategory];
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _submit() {
    final labels = _effectiveLabels();
    final cat = labels.contains(_category) ? _category : labels.first;
    widget.onSubmit(_titleController.text, cat);
    _titleController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final labels = _effectiveLabels();
    final categoryValue = labels.contains(_category) ? _category : labels.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _titleController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          maxLines: 2,
          minLines: 1,
          decoration: InputDecoration(
            hintText: 'Was möchtest du ablegen?',
            filled: true,
            fillColor: p.bg.withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: p.hairline),
            ),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: categoryValue,
          dropdownColor: p.surface,
          decoration: InputDecoration(
            labelText: 'Kategorie',
            filled: true,
            fillColor: p.bg.withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: p.hairline),
            ),
          ),
          items: labels
              .map((k) => DropdownMenuItem(value: k, child: Text(k)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _category = v);
          },
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.inbox_outlined, size: 20),
          label: const Text('In Ablage legen'),
        ),
      ],
    );
  }
}

String _fmtMin(int min) {
  final h = (min ~/ 60).toString().padLeft(2, '0');
  final m = (min % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Human-readable duration for subtitles (handles overnight spans).
/// Unter 60 Minuten: `45 min`. Ab einer Stunde: `1:30h`.
String _humanDuration(int deltaMin) {
  var minutes = deltaMin;
  if (minutes < 0) minutes += 24 * 60;
  if (minutes <= 0) minutes = 1;
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '$h:${m.toString().padLeft(2, '0')}h';
}

int _spanMinutesRaw(int startMin, int endMin) {
  if (startMin < endMin) return endMin - startMin;
  if (startMin > endMin) return (1440 - startMin) + endMin;
  return 0;
}

bool _spanCrossesMidnight(int startMin, int endMin) =>
    startMin > endMin && !(startMin == 0 && endMin == 1440);

/// Mindesthöhe wie [TimeBlock]-Kartenliste (preset-Vorschau im Editor).
double _presetPreviewListCardMinHeight(int durationMin, {required bool tightPhone}) {
  const refMinDur = 15;
  const refMaxDur = 300;
  var d = durationMin;
  if (d <= 0) d = refMinDur;
  d = d.clamp(refMinDur, refMaxDur);
  final lin = ((d - refMinDur) / (refMaxDur - refMinDur)).clamp(0.0, 1.0);
  final t = sqrt(lin);
  final lo = tightPhone ? 52.0 : 58.0;
  final hi = tightPhone ? 128.0 : 146.0;
  return lo + t * (hi - lo);
}

/// Dieselbe Zeilen-Optik wie im Tagesplan, ohne Interaktion (Preset‑Editor/-Dialog).
class _PresetTimelinePreviewRow extends StatelessWidget {
  const _PresetTimelinePreviewRow({
    required this.title,
    required this.startMin,
    required this.endMin,
    required this.colorLabel,
    required this.categoryColors,
    this.notes = '',
  });

  final String title;
  final int startMin;
  final int endMin;
  final String colorLabel;
  final Map<String, Color> categoryColors;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tp = Theme.of(context).platform;
    final mobilePerf =
        tp == TargetPlatform.iOS || tp == TargetPlatform.android;
    final sw = MediaQuery.sizeOf(context).width;
    final tightPhone = sw < 405;
    final timeColW = tightPhone ? 30.0 : 34.0;
    final railW = tightPhone ? 25.0 : 29.0;
    final gapAfterRail = tightPhone ? 3.0 : 4.0;
    /// Wie beim Tagesplan: Zentrum der Zeiten liegt zwischen linker Kante (+2 px Nut) und Icon‑Rail.
    final timeBandW = timeColW + gapAfterRail;
    const presetLeadingTimeGutterPx = 2.0;
    final lineClr = p.hairline.withValues(alpha: p.isDark ? 0.65 : 0.85);
    final stripe = categoryColors[colorLabel] ?? const Color(0xFF6B7280);
    final mealVis = _categoryUsesMealVisual(colorLabel);
    final openFreizeitSlot =
        !mealVis && _isFreizeitOffenPlaceholderTitle(title);
    final fill = stripe.withValues(alpha: p.stripeFillAlpha);
    final glowBase = mealVis ? MealBlockTheme.shadowGlow : stripe;
    final borderLine = mealVis
        ? MealBlockTheme.outline.withValues(alpha: 0.52)
        : stripe.withValues(alpha: 0.66);
    final slotGreyFillPrev = Color.alphaBlend(
      p.muted.withValues(alpha: p.isDark ? 0.30 : 0.24),
      p.surface,
    );
    final slotGreyBorderPrev =
        p.muted.withValues(alpha: p.isDark ? 0.72 : 0.62);
    final cardFill = openFreizeitSlot
        ? slotGreyFillPrev
        : mealVis
        ? Color.alphaBlend(
            MealBlockTheme.fillBase.withValues(
              alpha: MealBlockTheme.cardFillAlpha,
            ),
            p.surface,
          )
        : Color.alphaBlend(fill, p.surface);
    final borderLineResolved =
        openFreizeitSlot ? slotGreyBorderPrev : borderLine;
    final rawDur = _spanMinutesRaw(startMin, endMin);
    final dur = rawDur > 0 ? rawDur : 15;
    final shadowList = openFreizeitSlot
        ? const <BoxShadow>[]
        : <BoxShadow>[
            if (mobilePerf)
              BoxShadow(
                color: glowBase.withValues(alpha: p.isDark ? 0.16 : 0.07),
                blurRadius: 5,
                offset: const Offset(0, 1.5),
              )
            else ...[
              BoxShadow(
                color: glowBase.withValues(alpha: p.isDark ? 0.32 : 0.12),
                blurRadius: 10,
                offset: Offset.zero,
              ),
              BoxShadow(
                color: glowBase.withValues(alpha: p.isDark ? 0.16 : 0.06),
                blurRadius: 18,
                spreadRadius: -1,
                offset: const Offset(0, 2),
              ),
            ],
            if (!mobilePerf && p.cardShadows != null) ...p.cardShadows!,
          ];
    final minH =
        _presetPreviewListCardMinHeight(dur, tightPhone: tightPhone);
    final displayTitle =
        title.trim().isEmpty ? 'Block' : title.trim();

    return IgnorePointer(
      child: Tooltip(
        message:
            'So erscheint dieser Block später im Tagesplan (gleiche Darstellung wie in der Liste).',
        waitDuration: const Duration(milliseconds: 500),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minH),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: presetLeadingTimeGutterPx + timeBandW + railW,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.only(top: 10, bottom: 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _fmtMin(startMin.clamp(0, 1439)),
                                  textAlign: TextAlign.left,
                                  style:
                                      Theme.of(context).textTheme.labelMedium
                                          ?.copyWith(
                                      fontSize: tightPhone ? 11 : 11.5,
                                      fontFeatures:
                                          [FontFeature.tabularFigures()],
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0,
                                      color: p.muted,
                                      height: 1,
                                    ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _fmtMin(endMin.clamp(0, 1440)),
                                  textAlign: TextAlign.left,
                                  style:
                                      Theme.of(context).textTheme.labelSmall
                                          ?.copyWith(
                                      fontSize: tightPhone ? 10 : 10.5,
                                      fontFeatures:
                                          [FontFeature.tabularFigures()],
                                      fontWeight: FontWeight.w500,
                                      color:
                                          p.muted.withValues(alpha: 0.75),
                                      height: 1,
                                    ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: railW,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 1.5,
                                decoration: BoxDecoration(
                                  color: openFreizeitSlot
                                      ? p.muted.withValues(alpha: 0.52)
                                      : lineClr,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Center(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: tightPhone ? 4 : 5,
                                ),
                                child: Container(
                                  constraints: BoxConstraints(
                                    minHeight: tightPhone ? 40 : 44,
                                    minWidth: tightPhone ? 32 : 36,
                                  ),
                                  decoration: BoxDecoration(
                                    color: openFreizeitSlot
                                        ? p.muted.withValues(alpha: 0.08)
                                        : p.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: openFreizeitSlot
                                          ? slotGreyBorderPrev
                                          : p.hairline.withValues(alpha: 0.95),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    _categoryIcon(colorLabel),
                                    size: tightPhone ? 18 : 20,
                                    color: openFreizeitSlot
                                        ? p.muted.withValues(alpha: 0.5)
                                        : stripe.withValues(
                                            alpha: mealVis ? 0.86 : 0.92,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: gapAfterRail),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: cardFill,
                      border: Border.all(
                        color: borderLineResolved,
                        width: openFreizeitSlot ? 2.02 : 1.4,
                      ),
                      boxShadow: shadowList,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        tightPhone ? 5 : 7,
                        tightPhone ? 9 : 10,
                        tightPhone ? 4 : 6,
                        tightPhone ? 9 : 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: openFreizeitSlot
                                        ? slotGreyBorderPrev
                                        : stripe,
                                    width: 2,
                                  ),
                                  color: openFreizeitSlot
                                      ? p.muted.withValues(alpha: 0.07)
                                      : stripe.withValues(alpha: 0.08),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.more_horiz, color: p.muted, size: 22),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontSize: tightPhone ? 15 : 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.25,
                                        color: openFreizeitSlot
                                            ? p.muted.withValues(alpha: 0.58)
                                            : p.text,
                                        height: 1.25,
                                      ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '$colorLabel · ${_humanDuration(dur)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: tightPhone ? 11.5 : 12,
                                        fontWeight: FontWeight.w500,
                                        color: openFreizeitSlot
                                            ? p.muted.withValues(alpha: 0.42)
                                            : p.muted,
                                        height: 1.25,
                                      ),
                                ),
                                if (notes.trim().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    notes.trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontSize: 12,
                                          height: 1.2,
                                          color:
                                              p.muted.withValues(alpha: 0.9),
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _dateSheetHeading(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];
  final today = _onlyDay(DateTime.now());
  final day = _onlyDay(d);
  if (day == today) {
    return 'Heute, ${d.day}. ${months[d.month - 1]} ${d.year}';
  }
  return _dateLabel(d);
}

String _fmtBlockRange(TimeBlock b) {
  if (b.allDay) return 'Ganztags';
  final a = _fmtMin(b.startMin);
  final e = _fmtMin(b.endMin);
  if (b.startMin < b.endMin) return '$a – $e';
  if (b.startMin > b.endMin) return '$a – $e (+1)';
  return '$a – $e';
}

String _dateShortDe(DateTime d) {
  const months = [
    'Jan.',
    'Feb.',
    'März',
    'Apr.',
    'Mai',
    'Juni',
    'Juli',
    'Aug.',
    'Sep.',
    'Okt.',
    'Nov.',
    'Dez.',
  ];
  return '${d.day}. ${months[d.month - 1]} ${d.year}';
}

String _dateLabel(DateTime d) {
  const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];
  final wd = days[(d.weekday + 6) % 7];
  final mo = months[d.month - 1];
  return '$wd, ${d.day}. $mo ${d.year}';
}

String _dateInput(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

DateTime? _parseDate(String raw) {
  final p = raw.trim().split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

DateTime _onlyDay(DateTime d) => DateTime(d.year, d.month, d.day);

String _presetLabel(PlannerPresetType p) {
  switch (p) {
    case PlannerPresetType.hustle:
      return 'Hustle Mode';
    case PlannerPresetType.hustle530:
      return '5:30AM Hustle';
    case PlannerPresetType.monk:
      return 'Monk Mode';
    case PlannerPresetType.alltag:
      return 'Alltag';
    case PlannerPresetType.wochenende:
      return 'Wochenende';
    case PlannerPresetType.urlaub:
      return 'Urlaub';
    case PlannerPresetType.dayOff:
      return 'Day Off';
  }
}

/// Vorschau-/Bestätigungsdialog: Preset-Zeilen vor dem Laden in den Tag anpassen.
class _PresetApplyResult {
  const _PresetApplyResult({required this.lines, required this.asHauptplan});

  final List<PresetTaskLine> lines;
  final bool asHauptplan;
}

class _PresetLoadPreviewDialog extends StatefulWidget {
  const _PresetLoadPreviewDialog({
    required this.title,
    required this.initialLines,
    required this.isTodayTarget,
    required this.fmtMin,
    required this.categoryColors,
    required this.hauptplanName,
  });

  final String title;
  final List<PresetTaskLine> initialLines;
  final bool isTodayTarget;
  final String Function(int minute) fmtMin;
  final Map<String, Color> categoryColors;
  final String hauptplanName;

  @override
  State<_PresetLoadPreviewDialog> createState() =>
      _PresetLoadPreviewDialogState();
}

class _PresetLoadPreviewDialogState extends State<_PresetLoadPreviewDialog> {
  late List<PresetTaskLine> _lines;
  late List<TextEditingController> _titles;

  /// Tagesstart laut Vorlage (Ende des Übernacht-Schlafblocks, sonst frühester Start).
  late int _presetDayStart;

  /// Bisher angewendete Verschiebung in Minuten (Tagesstart − Vorlagenstart).
  int _dayStartShift = 0;

  @override
  void initState() {
    super.initState();
    _lines = widget.initialLines.map((e) => e.copy()).toList();
    _titles = _lines.map((e) => TextEditingController(text: e.title)).toList();
    _presetDayStart = presetDayStartMinute(_lines);
  }

  int get _currentDayStart =>
      ((_presetDayStart + _dayStartShift) % 1440 + 1440) % 1440;

  Future<void> _pickDayStart() async {
    final cur = _currentDayStart;
    final t = await showTimePicker(
      context: context,
      helpText: 'Tagesstart (Aufstehen)',
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (t == null || !mounted) return;
    final target = t.hour * 60 + t.minute;
    var delta = target - cur;
    // Kürzesten Weg nehmen (z. B. 23:30 → 00:30 = +1 h, nicht −23 h).
    if (delta > 720) delta -= 1440;
    if (delta < -720) delta += 1440;
    if (delta == 0) return;
    setState(() {
      _lines = shiftPresetLines(_lines, delta);
      _dayStartShift += delta;
    });
  }

  void _resetDayStart() {
    if (_dayStartShift == 0) return;
    setState(() {
      _lines = shiftPresetLines(_lines, -_dayStartShift);
      _dayStartShift = 0;
    });
  }

  /// Blöcke, die durch die Verschiebung komplett nach Mitternacht rutschen
  /// (liegen dann vor dem neuen Tagesstart, ohne der Schlafblock zu sein).
  int get _afterMidnightCount {
    if (_dayStartShift <= 0) return 0;
    final ds = _currentDayStart;
    return _lines
        .where((l) => l.startMin < l.endMin && l.startMin < ds)
        .length;
  }

  String _fmtShift(int m) {
    final sign = m >= 0 ? '+' : '−';
    final a = m.abs();
    final h = a ~/ 60;
    final mm = a % 60;
    if (h == 0) return '$sign$mm Min';
    if (mm == 0) return '$sign$h h';
    return '$sign$h:${mm.toString().padLeft(2, '0')} h';
  }

  Widget _dayStartBar(BuildContext context) {
    final p = context.palette;
    final shifted = _dayStartShift != 0;
    return Material(
      color: p.accent.withValues(alpha: p.isDark ? 0.10 : 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _pickDayStart,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Icon(Icons.wb_twilight_rounded, size: 20, color: p.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tagesstart ${widget.fmtMin(_currentDayStart)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shifted
                          ? 'Alle Blöcke ${_fmtShift(_dayStartShift)} verschoben'
                                '${_afterMidnightCount > 0 ? ' · $_afterMidnightCount nach Mitternacht' : ''}'
                          : 'Tippen, um die Aufstehzeit zu ändern',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: shifted ? p.accent : p.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (shifted)
                IconButton(
                  tooltip: 'Zurück auf ${widget.fmtMin(_presetDayStart)}',
                  onPressed: _resetDayStart,
                  icon: Icon(Icons.restart_alt_rounded, color: p.muted),
                )
              else
                Icon(Icons.chevron_right_rounded, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _titles) {
      c.dispose();
    }
    super.dispose();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final l = _lines.removeAt(oldIndex);
      final t = _titles.removeAt(oldIndex);
      _lines.insert(newIndex, l);
      _titles.insert(newIndex, t);
    });
  }

  void _popApply({required bool asHauptplan}) {
    final out = <PresetTaskLine>[];
    for (var i = 0; i < _lines.length; i++) {
      out.add(_lines[i].copyWith(title: _titles[i].text));
    }
    if (out.any((e) => e.title.trim().isNotEmpty)) {
      Navigator.pop(
        context,
        _PresetApplyResult(
          asHauptplan: asHauptplan,
          lines: out
              .map(
                (e) => e.copyWith(
                  title: e.title.trim().isEmpty ? 'Block' : e.title.trim(),
                ),
              )
              .toList(),
        ),
      );
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Mindestens ein Titel eingeben')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = MediaQuery.sizeOf(context).height;
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      content: SizedBox(
        width: 440,
        height: h.clamp(360, 760) * 0.68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dayStartBar(context),
            const SizedBox(height: 10),
            Text(
              widget.isTodayTarget
                  ? 'Nur erledigte Blöcke bleiben stehen. Alles ab jetzt '
                        '(${widget.fmtMin(DateTime.now().hour * 60 + DateTime.now().minute)}) '
                        'wird durch die Vorlage ersetzt — auch der gerade laufende Slot wird '
                        'durch den passenden Preset-Block ab dieser Uhrzeit getauscht.'
                  : 'Der ganze Tag wird mit der Vorlage gefüllt (kein „jetzt“ beim Datumswechsel).',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: p.muted, height: 1.35),
            ),
            const SizedBox(height: 6),
            Text(
              '„Nur heute“ lässt den Hauptplan (${widget.hauptplanName}) unverändert. '
              '„Als Hauptplan“ gilt open end als neuer Standard.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: p.muted, height: 1.35),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _lines.length,
                onReorder: _reorder,
                itemBuilder: (context, i) {
                  final ln = _lines[i];
                  return Card(
                    key: ValueKey('_pln_${ln.startMin}_${ln.endMin}_$i'),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnimatedBuilder(
                            animation: _titles[i],
                            builder: (ctx, _) {
                              return _PresetTimelinePreviewRow(
                                title: _titles[i].text,
                                startMin: ln.startMin,
                                endMin: ln.endMin,
                                colorLabel: ln.colorLabel,
                                categoryColors: widget.categoryColors,
                                notes: ln.notes,
                              );
                            },
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ReorderableDragStartListener(
                                index: i,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    right: 4,
                                  ),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: p.muted.withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _titles[i],
                                  decoration: const InputDecoration(
                                    labelText: 'Titel',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${ln.colorLabel} · Zeit anpassen',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: p.muted),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(
                                      hour: _lines[i].startMin ~/ 60,
                                      minute: _lines[i].startMin % 60,
                                    ),
                                  );
                                  if (t == null || !mounted) return;
                                  setState(() {
                                    final cur = _lines[i];
                                    _lines[i] = cur.copyWith(
                                      startMin:
                                          (t.hour * 60 + t.minute).clamp(
                                        0,
                                        1439,
                                      ),
                                    );
                                  });
                                },
                                child: const Text('Start'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(
                                      hour: _lines[i].endMin ~/ 60,
                                      minute: _lines[i].endMin % 60,
                                    ),
                                  );
                                  if (t == null || !mounted) return;
                                  setState(() {
                                    final cur = _lines[i];
                                    _lines[i] = cur.copyWith(
                                      endMin:
                                          (t.hour * 60 + t.minute).clamp(
                                        1,
                                        1440,
                                      ),
                                    );
                                  });
                                },
                                child: const Text('Ende'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: () => _popApply(asHauptplan: false),
          child: const Text('Nur heute'),
        ),
        FilledButton(
          onPressed: () => _popApply(asHauptplan: true),
          child: const Text('Als Hauptplan'),
        ),
      ],
    );
  }
}

class _PresetRowCtrls {
  _PresetRowCtrls({
    required this.rowId,
    required this.titleCtrl,
    required this.notesCtrl,
    required this.startMin,
    required this.endMin,
    required this.colorLabel,
    required this.allowedCategories,
  });

  factory _PresetRowCtrls.fromLine(
    String rowId,
    PresetTaskLine ln,
    List<String> allowed,
  ) {
    final raw = ln.colorLabel.trim();
    final first = allowed.isNotEmpty ? allowed.first : 'Routine';
    final cat = allowed.contains(raw) ? raw : first;
    return _PresetRowCtrls(
      rowId: rowId,
      titleCtrl: TextEditingController(text: ln.title),
      notesCtrl: TextEditingController(text: ln.notes),
      startMin: ln.startMin.clamp(0, 1440),
      endMin: ln.endMin.clamp(0, 1440),
      colorLabel: cat,
      allowedCategories: allowed,
    );
  }

  final String rowId;
  final TextEditingController titleCtrl;
  final TextEditingController notesCtrl;
  int startMin;
  int endMin;
  String colorLabel;
  final List<String> allowedCategories;

  void dispose() {
    titleCtrl.dispose();
    notesCtrl.dispose();
  }

  PresetTaskLine toLine() {
    final first = allowedCategories.isNotEmpty
        ? allowedCategories.first
        : 'Routine';
    final cat = allowedCategories.contains(colorLabel) ? colorLabel : first;
    return PresetTaskLine(
      title: titleCtrl.text,
      startMin: startMin,
      endMin: endMin,
      colorLabel: cat,
      notes: notesCtrl.text,
    );
  }
}

class _PresetTemplatesEditorSheet extends StatefulWidget {
  const _PresetTemplatesEditorSheet({
    required this.initialKey,
    required this.overrides,
    required this.userPresets,
    required this.presetCategories,
    required this.builtinDisplayNames,
    required this.categoryColors,
    required this.onSaved,
  });

  final String initialKey;
  final Map<PlannerPresetType, List<PresetTaskLine>> overrides;
  final List<UserPresetDay> userPresets;
  final List<String> presetCategories;
  final Map<PlannerPresetType, String> builtinDisplayNames;
  final Map<String, Color> categoryColors;
  final Future<void> Function(
    Map<PlannerPresetType, List<PresetTaskLine>> merged,
    List<UserPresetDay> users,
    Map<PlannerPresetType, String> builtinDisplayOverrides,
  )
  onSaved;

  @override
  State<_PresetTemplatesEditorSheet> createState() =>
      _PresetTemplatesEditorSheetState();
}

class _PresetTemplatesEditorSheetState
    extends State<_PresetTemplatesEditorSheet> {
  late String _tabKey;
  late Map<String, List<PresetTaskLine>> _cache;
  final Map<String, TextEditingController> _nameCtrls = {};
  final Map<PlannerPresetType, TextEditingController> _builtinDisplayCtrls = {};
  final List<_PresetRowCtrls> _rows = [];
  int _rowNonce = 0;

  @override
  void initState() {
    super.initState();
    _cache = {};
    for (final t in PlannerPresetType.values) {
      final base = widget.overrides[t] ?? builtinPresetLinesFor(t);
      _cache[t.name] = base.map((e) => e.copy()).toList();
      final nm = widget.builtinDisplayNames[t] ?? '';
      _builtinDisplayCtrls[t] = TextEditingController(text: nm);
    }
    for (final u in widget.userPresets) {
      final k = 'u:${u.id}';
      _cache[k] = u.lines.map((e) => e.copy()).toList();
      _nameCtrls[u.id] = TextEditingController(text: u.name);
    }
    _tabKey = widget.initialKey;
    if (!_cache.containsKey(_tabKey)) {
      _tabKey = PlannerPresetType.hustle.name;
    }
    _reloadRowsFromCache();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    for (final c in _nameCtrls.values) {
      c.dispose();
    }
    for (final c in _builtinDisplayCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  PlannerPresetType? _builtinForKey(String key) {
    for (final t in PlannerPresetType.values) {
      if (t.name == key) return t;
    }
    return null;
  }

  String? _userIdFromTab(String tab) {
    if (!tab.startsWith('u:')) return null;
    final id = tab.substring(2).trim();
    return id.isEmpty ? null : id;
  }

  String _presetTitleForSnack(String tabKey) {
    final bt = _builtinForKey(tabKey);
    if (bt != null) {
      final nm = _builtinDisplayCtrls[bt]?.text.trim() ?? '';
      if (nm.isNotEmpty) return nm;
      return _presetLabel(bt);
    }
    final id = _userIdFromTab(tabKey);
    if (id != null && _nameCtrls.containsKey(id)) {
      final nm = _nameCtrls[id]!.text.trim();
      if (nm.isNotEmpty) return nm;
    }
    return 'Preset ($tabKey)';
  }

  List<String> _categoryPickList() {
    final p = widget.presetCategories;
    if (p.isNotEmpty) return List<String>.from(p);
    return List<String>.from(kCanonicalDefaultCategoryOrder);
  }

  String _pickDefaultPresetRowColorLabel() {
    final c = _categoryPickList();
    if (c.contains('Fokus')) return 'Fokus';
    return c.first;
  }

  void _flushRowsToCache() {
    _cache[_tabKey] = _rows.map((r) => r.toLine()).toList();
  }

  void _reloadRowsFromCache() {
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    var lines = _cache[_tabKey];
    final defCat = _pickDefaultPresetRowColorLabel();
    if (lines == null || lines.isEmpty) {
      lines = [
        PresetTaskLine(
          title: 'Neuer Block',
          startMin: 540,
          endMin: 600,
          colorLabel: defCat,
        ),
      ];
      _cache[_tabKey] = lines;
    }
    final allowed = _categoryPickList();
    for (final ln in lines) {
      _rows.add(
        _PresetRowCtrls.fromLine('${_tabKey}_${_rowNonce++}', ln, allowed),
      );
    }
  }

  void _switchTab(String next) {
    if (next == _tabKey) return;
    _flushRowsToCache();
    setState(() {
      _tabKey = next;
      _reloadRowsFromCache();
    });
  }

  Map<PlannerPresetType, String> _mergeBuiltinDisplayNames() {
    final out = <PlannerPresetType, String>{};
    for (final t in PlannerPresetType.values) {
      final raw = _builtinDisplayCtrls[t]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      if (raw == _presetLabel(t)) continue;
      out[t] = raw;
    }
    return out;
  }

  Map<PlannerPresetType, List<PresetTaskLine>> _mergeBuiltin() {
    _flushRowsToCache();
    final out = <PlannerPresetType, List<PresetTaskLine>>{};
    for (final t in PlannerPresetType.values) {
      final list = (_cache[t.name] ?? []).map((e) => e.copy()).toList();
      if (!_presetLinesEqual(list, builtinPresetLinesFor(t))) {
        out[t] = list;
      }
    }
    return out;
  }

  List<UserPresetDay> _mergeUsers() {
    _flushRowsToCache();
    final out = <UserPresetDay>[];
    for (final id in _nameCtrls.keys) {
      final tab = 'u:$id';
      final lines = (_cache[tab] ?? []).map((e) => e.copy()).toList();
      final rawName = _nameCtrls[id]!.text.trim();
      out.add(
        UserPresetDay(
          id: id,
          name: rawName.isEmpty ? 'Preset' : rawName,
          lines: lines,
        ),
      );
    }
    return out;
  }

  bool _validateBeforeSave(BuildContext snackCtx) {
    _flushRowsToCache();
    final keysToCheck = <String>[
      ...PlannerPresetType.values.map((e) => e.name),
      ..._nameCtrls.keys.map((id) => 'u:$id'),
    ];
    for (final key in keysToCheck) {
      final lines = _cache[key];
      if (lines == null) continue;
      for (var i = 0; i < lines.length; i++) {
        final ln = lines[i];
        if (ln.startMin == ln.endMin) {
          final title = _presetTitleForSnack(key);
          ScaffoldMessenger.of(snackCtx).showSnackBar(
            SnackBar(
              content: Text(
                '$title, Block ${i + 1}: Start und Ende dürfen nicht gleich sein.',
              ),
            ),
          );
          return false;
        }
      }
    }
    return true;
  }

  void _createUserPreset() {
    _flushRowsToCache();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final tab = 'u:$id';
    _nameCtrls[id] = TextEditingController(text: 'Mein Preset-Tag');
    _cache[tab] = builtinPresetLinesFor(
      PlannerPresetType.alltag,
    ).map((e) => e.copy()).toList();
    setState(() {
      _tabKey = tab;
      _reloadRowsFromCache();
    });
  }

  void _deleteCurrentUserPreset() {
    final id = _userIdFromTab(_tabKey);
    if (id == null) return;
    _flushRowsToCache();
    _cache.remove(_tabKey);
    _nameCtrls[id]?.dispose();
    _nameCtrls.remove(id);
    final fallback = PlannerPresetType.hustle.name;
    setState(() {
      _tabKey = fallback;
      _reloadRowsFromCache();
    });
  }

  Future<void> _pickStart(_PresetRowCtrls r) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: r.startMin ~/ 60, minute: r.startMin % 60),
    );
    if (t == null || !mounted) return;
    setState(() {
      r.startMin = (t.hour * 60 + t.minute).clamp(0, 1440);
    });
  }

  Future<void> _pickEnd(_PresetRowCtrls r) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: r.endMin ~/ 60, minute: r.endMin % 60),
    );
    if (t == null || !mounted) return;
    setState(() {
      r.endMin = (t.hour * 60 + t.minute).clamp(0, 1440);
    });
  }

  void _addRow() {
    final allowed = _categoryPickList();
    final dc = _pickDefaultPresetRowColorLabel();
    setState(() {
      _rows.add(
        _PresetRowCtrls.fromLine(
          '${_tabKey}_add_${_rowNonce++}',
          PresetTaskLine(
            title: 'Neuer Block',
            startMin: 540,
            endMin: 600,
            colorLabel: dc,
          ),
          allowed,
        ),
      );
      _cache[_tabKey] = _rows.map((x) => x.toLine()).toList();
    });
  }

  void _removeRowAt(int index) {
    setState(() {
      final r = _rows.removeAt(index);
      r.dispose();
      _cache[_tabKey] = _rows.map((x) => x.toLine()).toList();
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final r = _rows.removeAt(oldIndex);
      _rows.insert(newIndex, r);
      _cache[_tabKey] = _rows.map((x) => x.toLine()).toList();
    });
  }

  void _resetCurrentToBuiltin() {
    final bt = _builtinForKey(_tabKey);
    if (bt == null) return;
    _flushRowsToCache();
    setState(() {
      _cache[_tabKey] = builtinPresetLinesFor(bt).map((e) => e.copy()).toList();
      _reloadRowsFromCache();
    });
  }

  Future<void> _submit() async {
    if (!_validateBeforeSave(context)) return;
    await widget.onSaved(
      _mergeBuiltin(),
      _mergeUsers(),
      _mergeBuiltinDisplayNames(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = MediaQuery.of(context).size.height * 0.91;
    final categories = _categoryPickList();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Material(
        color: p.surface,
        child: SafeArea(
          top: true,
          bottom: false,
          child: SizedBox(
            height: h,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Preset-Vorlagen',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: p.text,
                              ),
                        ),
                      ),
                      Tooltip(
                        message: 'Eigenen Preset-Tag hinzufügen',
                        child: IconButton(
                          icon: Icon(
                            Icons.library_add_rounded,
                            color: p.accent,
                          ),
                          onPressed: _createUserPreset,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: p.muted),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  // ignore: deprecated_member_use
                  child: DropdownButtonFormField<String>(
                    value: _tabKey,
                    dropdownColor: p.surface,
                    decoration: InputDecoration(
                      labelText: 'Preset',
                      filled: true,
                      fillColor: p.bg.withValues(alpha: 0.35),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.hairline),
                      ),
                    ),
                    items: [
                      ...PlannerPresetType.values.map(
                        (pt) => DropdownMenuItem(
                          value: pt.name,
                          child: Text(
                            (_builtinDisplayCtrls[pt]?.text.trim().isEmpty ??
                                    true)
                                ? _presetLabel(pt)
                                : _builtinDisplayCtrls[pt]!.text.trim(),
                          ),
                        ),
                      ),
                      ..._nameCtrls.entries.map(
                        (e) => DropdownMenuItem(
                          value: 'u:${e.key}',
                          child: Text(
                            e.value.text.trim().isEmpty
                                ? 'Eigenes Preset'
                                : e.value.text.trim(),
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: _kCreatePresetMenuValue,
                        child: Text(
                          '+ Neues Preset erstellen',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      if (v == _kCreatePresetMenuValue) {
                        _createUserPreset();
                        return;
                      }
                      _switchTab(v);
                    },
                  ),
                ),
                if (_builtinForKey(_tabKey) != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller:
                          _builtinDisplayCtrls[_builtinForKey(_tabKey)!],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Anzeigename (oben & in der Liste)',
                        filled: true,
                        fillColor: p.bg.withValues(alpha: 0.35),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: p.hairline),
                        ),
                      ),
                    ),
                  ),
                if (_userIdFromTab(_tabKey) != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameCtrls[_userIdFromTab(_tabKey)],
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Name (in der Liste)',
                              filled: true,
                              fillColor: p.bg.withValues(alpha: 0.35),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: p.hairline),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dieses Preset löschen',
                          onPressed: _deleteCurrentUserPreset,
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: p.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Eingebaute Modus‑Vorlagen und eigene Preset‑Tage. Unter jeder Zeile siehst du die gleiche Darstellung wie im Tagesplan. Das Raster gilt für '
                    'Oben neben „Heute“ wählst du den Preset‑Modus; leere/neue Tage und Preset‑Zeiträume nutzen dieselben Vorlagen. Kategorie = Farbe im Plan.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: p.muted,
                      height: 1.35,
                    ),
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(
                          child: Text(
                            'Noch keine Blöcke',
                            style: TextStyle(color: p.muted),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          buildDefaultDragHandles: false,
                          itemCount: _rows.length,
                          onReorder: _onReorder,
                          itemBuilder: (context, index) {
                            final r = _rows[index];
                            return Card(
                              key: ValueKey<String>(r.rowId),
                              margin: const EdgeInsets.only(bottom: 10),
                              color: p.bg.withValues(alpha: 0.25),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: p.hairline),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AnimatedBuilder(
                                      animation: Listenable.merge([
                                        r.titleCtrl,
                                        r.notesCtrl,
                                      ]),
                                      builder: (ctx, _) {
                                        final ln = PresetTaskLine(
                                          title: r.titleCtrl.text,
                                          startMin: r.startMin,
                                          endMin: r.endMin,
                                          colorLabel: r.colorLabel,
                                          notes: r.notesCtrl.text,
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            left: 2,
                                            right: 4,
                                            top: 2,
                                          ),
                                          child: _PresetTimelinePreviewRow(
                                            title: ln.title,
                                            startMin: ln.startMin,
                                            endMin: ln.endMin,
                                            colorLabel: ln.colorLabel,
                                            categoryColors: widget.categoryColors,
                                            notes: ln.notes,
                                          ),
                                        );
                                      },
                                    ),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                              left: 2,
                                            ),
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                              color: p.muted.withValues(
                                                alpha: 0.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: TextField(
                                            controller: r.titleCtrl,
                                            style: TextStyle(
                                              color: p.text,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              labelText: 'Titel',
                                              labelStyle: TextStyle(
                                                color: p.muted,
                                              ),
                                              border: InputBorder.none,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _removeRowAt(index),
                                          icon: Icon(
                                            Icons.close_rounded,
                                            size: 20,
                                            color: p.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => _pickStart(r),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 8,
                                                    horizontal: 4,
                                                  ),
                                              child: Text(
                                                'Start ${_fmtMin(r.startMin)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: p.text,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => _pickEnd(r),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 8,
                                                    horizontal: 4,
                                                  ),
                                              child: Text(
                                                'Ende ${_fmtMin(r.endMin)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: p.text,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: DropdownButtonFormField<String>(
                                        initialValue:
                                            categories.contains(r.colorLabel)
                                            ? r.colorLabel
                                            : categories.first,
                                        dropdownColor: p.surface,
                                        decoration: InputDecoration(
                                          labelText: 'Kategorie',
                                          isDense: true,
                                          filled: true,
                                          fillColor: p.surface.withValues(
                                            alpha: 0.5,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: p.hairline,
                                            ),
                                          ),
                                        ),
                                        items: categories
                                            .map(
                                              (k) => DropdownMenuItem(
                                                value: k,
                                                child: Text(k),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) {
                                          if (v == null) return;
                                          setState(() => r.colorLabel = v);
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        4,
                                        10,
                                        0,
                                      ),
                                      child: TextField(
                                        controller: r.notesCtrl,
                                        maxLines: 2,
                                        style: TextStyle(
                                          color: p.muted,
                                          height: 1.25,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText:
                                              'Optionale Notiz zur Vorlage …',
                                          hintStyle: TextStyle(
                                            color: p.muted.withValues(
                                              alpha: 0.75,
                                            ),
                                          ),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    6,
                    14,
                    12 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton.icon(
                        onPressed: _addRow,
                        icon: Icon(
                          Icons.add_rounded,
                          color: p.accent.withValues(alpha: 0.9),
                        ),
                        label: Text(
                          'Block hinzufügen',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: p.accent.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _builtinForKey(_tabKey) != null
                                  ? _resetCurrentToBuiltin
                                  : null,
                              child: const Text('Modus auf Standard'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _submit,
                              child: const Text('Speichern'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
