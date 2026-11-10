import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

export 'macro_plan_stub.dart' if (dart.library.js_interop) 'macro_plan_web.dart';

/// SharedPreferences-Keys (werden per Cloud-Sync übertragen).
const String kMacroPlanPrefKey = 'planner_macro_plan_v1';
const String kMacroMealByTitlePrefKey = 'planner_macro_meal_by_title_v1';
const String kMacroSplitsPrefKey = 'planner_macro_splits_v1';

/// Teil einer Mahlzeit, der in einem anderen Block gegessen wird
/// (z. B. 30 g Protein direkt nach dem Aufstehen).
class MacroSplit {
  const MacroSplit({
    required this.title,
    this.carbs = 0,
    this.protein = 0,
    this.fat = 0,
  });

  /// Block, in dem dieser Teil gegessen wird (Titel wie angezeigt).
  final String title;
  final int carbs;
  final int protein;
  final int fat;

  int get kcal => carbs * 4 + protein * 4 + fat * 9;

  String get shortLabel {
    final parts = <String>[
      if (protein > 0) '$protein g Protein',
      if (carbs > 0) '$carbs g Carbs',
      if (fat > 0) '$fat g Fett',
    ];
    return parts.isEmpty ? 'nichts' : parts.join(', ');
  }

  static MacroSplit? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = (j['title'] ?? '').toString();
    if (t.trim().isEmpty) return null;
    int v(String k) => (j[k] as num?)?.round() ?? 0;
    return MacroSplit(
      title: t,
      carbs: v('carbs'),
      protein: v('protein'),
      fat: v('fat'),
    );
  }

  Map<String, Object> toJson() => {
    'title': title,
    'carbs': carbs,
    'protein': protein,
    'fat': fat,
  };
}

/// Was ein Block anzeigt: ganze Mahlzeit, abgespaltener Teil oder Rest.
enum MacroShare { full, part, rest }

class BlockMacros {
  const BlockMacros({
    required this.meal,
    required this.share,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.kcalMin,
    required this.kcalMax,
    this.split,
  });

  final MealMacros meal;
  final MacroShare share;
  final String carbs;
  final String protein;
  final String fat;
  final int kcalMin;
  final int kcalMax;
  final MacroSplit? split;
}

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
    Map<String, MacroSplit>? splits,
  }) : meals = meals ?? [],
       mealByTitle = mealByTitle ?? {},
       splits = splits ?? {};

  /// Mahlzeit-ID → abgespaltener Teil.
  final Map<String, MacroSplit> splits;

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

  MacroSplit? splitFor(String mealId) => splits[mealId];

  void setSplit(String mealId, MacroSplit? split) {
    if (split == null) {
      splits.remove(mealId);
    } else {
      splits[mealId] = split;
    }
  }

  /// Makros, die dieser Block zeigt (inkl. Aufteilung).
  BlockMacros? blockMacros(String title) {
    final m = mealFor(title);
    if (m == null) return null;
    final sp = splits[m.id];
    if (sp == null) {
      return BlockMacros(
        meal: m,
        share: MacroShare.full,
        carbs: m.carbs.label,
        protein: m.protein.label,
        fat: m.fat.label,
        kcalMin: m.kcalMin,
        kcalMax: m.kcalMax,
      );
    }
    if (_key(sp.title) == _key(title)) {
      String g(int v) => v <= 0 ? '–' : '$v g';
      return BlockMacros(
        meal: m,
        share: MacroShare.part,
        carbs: g(sp.carbs),
        protein: g(sp.protein),
        fat: g(sp.fat),
        kcalMin: sp.kcal,
        kcalMax: sp.kcal,
        split: sp,
      );
    }
    String rest(MacroRange r, int used) {
      final a = (r.minG - used).clamp(0, 9999);
      final b = (r.maxG - used).clamp(0, 9999);
      if (b <= 0) return '–';
      return a == b ? '$a g' : '$a–$b g';
    }
    return BlockMacros(
      meal: m,
      share: MacroShare.rest,
      carbs: rest(m.carbs, sp.carbs),
      protein: rest(m.protein, sp.protein),
      fat: rest(m.fat, sp.fat),
      kcalMin: (m.kcalMin - sp.kcal).clamp(0, 99999),
      kcalMax: (m.kcalMax - sp.kcal).clamp(0, 99999),
      split: sp,
    );
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
  static MacroPlan parseExport(
    String text, {
    Map<String, String>? keepMapping,
    Map<String, MacroSplit>? keepSplits,
  }) {
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
      splits: keepSplits,
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
      final splits = <String, MacroSplit>{};
      final rawSp = prefs.getString(kMacroSplitsPrefKey);
      if (rawSp != null && rawSp.isNotEmpty) {
        final d = jsonDecode(rawSp);
        if (d is Map) {
          d.forEach((k, v) {
            final sp = MacroSplit.fromJson(v);
            if (k is String && sp != null) splits[k] = sp;
          });
        }
      }
      final raw = prefs.getString(kMacroPlanPrefKey);
      if (raw == null || raw.isEmpty) {
        return MacroPlan(mealByTitle: map, splits: splits);
      }
      final d = jsonDecode(raw);
      if (d is! Map) return MacroPlan(mealByTitle: map, splits: splits);
      return MacroPlan(
        meals: [
          for (final m in (d['meals'] as List? ?? const []))
            if (m is Map) MealMacros.fromJson(m),
        ],
        created: DateTime.tryParse((d['created'] ?? '').toString()),
        mealByTitle: map,
        splits: splits,
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
      await prefs.setString(
        kMacroSplitsPrefKey,
        jsonEncode(splits.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (_) {}
  }
}
