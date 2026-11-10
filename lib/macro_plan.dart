import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

export 'macro_plan_stub.dart' if (dart.library.js_interop) 'macro_plan_web.dart';

/// SharedPreferences-Keys (werden per Cloud-Sync übertragen).
const String kMacroPlanPrefKey = 'planner_macro_plan_v1';
const String kMacroMealByTitlePrefKey = 'planner_macro_meal_by_title_v1';

/// Bereich eines Makros für eine Mahlzeit (aus PREPIT).
class MacroRange {
  const MacroRange(this.minPct, this.maxPct, this.minG, this.maxG);

  final int minPct;
  final int maxPct;
  final int minG;
  final int maxG;

  static MacroRange fromJson(Object? j) {
    final m = j is Map ? j : const {};
    int v(String k) => (m[k] as num?)?.round() ?? 0;
    return MacroRange(v('minPct'), v('maxPct'), v('minG'), v('maxG'));
  }

  Map<String, int> toJson() => {
    'minPct': minPct,
    'maxPct': maxPct,
    'minG': minG,
    'maxG': maxG,
  };

  String get label {
    String r(int a, int b) => a == b ? '$a' : '$a–$b';
    return '${r(minPct, maxPct)} % / ${r(minG, maxG)} g';
  }
}

class MealMacros {
  const MealMacros({
    required this.id,
    required this.name,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.kcalMin,
    required this.kcalMax,
  });

  final String id;
  final String name;
  final MacroRange carbs;
  final MacroRange protein;
  final MacroRange fat;
  final int kcalMin;
  final int kcalMax;

  static MealMacros fromJson(Map j) {
    final k = j['kcal'] is Map ? j['kcal'] as Map : const {};
    return MealMacros(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? j['id'] ?? '').toString(),
      carbs: MacroRange.fromJson(j['carbs']),
      protein: MacroRange.fromJson(j['protein']),
      fat: MacroRange.fromJson(j['fat']),
      kcalMin: (k['min'] as num?)?.round() ?? 0,
      kcalMax: (k['max'] as num?)?.round() ?? 0,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'carbs': carbs.toJson(),
    'protein': protein.toJson(),
    'fat': fat.toJson(),
    'kcal': {'min': kcalMin, 'max': kcalMax},
  };

  String get kcalLabel =>
      kcalMin == kcalMax ? '$kcalMin kcal' : '$kcalMin–$kcalMax kcal';
}

/// Makroplan aus PREPIT + Zuordnung Block-Titel → Mahlzeit.
class MacroPlan {
  MacroPlan({
    List<MealMacros>? meals,
    this.created,
    Map<String, String>? mealByTitle,
  }) : meals = meals ?? [],
       mealByTitle = mealByTitle ?? {};

  final List<MealMacros> meals;
  final DateTime? created;

  /// Kleingeschriebener Block-Titel → Mahlzeit-ID ('' = bewusst keine).
  final Map<String, String> mealByTitle;

  bool get isEmpty => meals.isEmpty;

  MealMacros? byId(String id) {
    for (final m in meals) {
      if (m.id == id) return m;
    }
    return null;
  }

  static String _key(String title) => title.trim().toLowerCase();

  /// Mahlzeit für einen Block: gespeicherte Wahl, sonst Vorschlag aus dem Titel.
  MealMacros? mealFor(String title) {
    if (meals.isEmpty || title.trim().isEmpty) return null;
    final saved = mealByTitle[_key(title)];
    if (saved != null) return saved.isEmpty ? null : byId(saved);
    return byId(guessMealId(title) ?? '');
  }

  void setMeal(String title, String? mealId) {
    if (title.trim().isEmpty) return;
    mealByTitle[_key(title)] = mealId ?? '';
  }

  static String? guessMealId(String title) {
    final t = title.toLowerCase();
    if (t.contains('pre-workout') || t.contains('pre workout')) {
      return 'Pre-Workout';
    }
    if (t.contains('post-workout') || t.contains('post workout')) {
      return 'Post-Workout';
    }
    if (t.contains('main meal') || t.contains('hauptmahlzeit')) {
      return 'Main Meal';
    }
    if (t.contains('evening meal') ||
        t.contains('abendessen') ||
        t.contains('abendmahlzeit')) {
      return 'Evening Meal';
    }
    return null;
  }

  /// Liest eine PREPIT-Exportdatei. Wirft bei falschem Format.
  static MacroPlan parseExport(String text, {Map<String, String>? keepMapping}) {
    final j = jsonDecode(text);
    if (j is! Map || j['app'] != 'prepit-macroplan' || j['meals'] is! List) {
      throw const FormatException('kein PREPIT-Makroplan');
    }
    final meals = <MealMacros>[
      for (final m in j['meals'] as List)
        if (m is Map) MealMacros.fromJson(m),
    ];
    return MacroPlan(
      meals: meals,
      created: DateTime.tryParse((j['created'] ?? '').toString()),
      mealByTitle: keepMapping,
    );
  }

  static Future<MacroPlan> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, String>{};
      final rawMap = prefs.getString(kMacroMealByTitlePrefKey);
      if (rawMap != null && rawMap.isNotEmpty) {
        final d = jsonDecode(rawMap);
        if (d is Map) {
          d.forEach((k, v) {
            if (k is String && v is String) map[k] = v;
          });
        }
      }
      final raw = prefs.getString(kMacroPlanPrefKey);
      if (raw == null || raw.isEmpty) return MacroPlan(mealByTitle: map);
      final d = jsonDecode(raw);
      if (d is! Map) return MacroPlan(mealByTitle: map);
      return MacroPlan(
        meals: [
          for (final m in (d['meals'] as List? ?? const []))
            if (m is Map) MealMacros.fromJson(m),
        ],
        created: DateTime.tryParse((d['created'] ?? '').toString()),
        mealByTitle: map,
      );
    } catch (_) {
      return MacroPlan();
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kMacroPlanPrefKey,
        jsonEncode({
          'created': created?.toIso8601String(),
          'meals': meals.map((m) => m.toJson()).toList(),
        }),
      );
      await prefs.setString(kMacroMealByTitlePrefKey, jsonEncode(mealByTitle));
    } catch (_) {}
  }
}
