// KI-gestützte Mahlzeiten-Erkennung: Foto → Gemini, Namen nachträglich in main.dart matchen.
// API-Key: Einstellungen (Google AI Studio).

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const String _kGeminiGenerate =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

/// Kompakter Katalog als Maps (n, p, c, f, k, cat) für den Prompt.
List<Map<String, dynamic>> buildAiFoodCatalog(
  List<Map<String, dynamic>> fromFoods, {
  int maxItems = 3000,
}) {
  if (fromFoods.length <= maxItems) return fromFoods;
  return fromFoods.sublist(0, maxItems);
}

class AiLineRaw {
  AiLineRaw({required this.catalogName, required this.grams});
  final String catalogName;
  final double grams;
}

class AiMealRaw {
  AiMealRaw({required this.dish, required this.items});
  final String dish;
  final List<AiLineRaw> items;
}

/// Nur HTTP + JSON, kein Food-Typ.
Future<AiMealRaw> requestGeminiMealEstimate({
  required String apiKey,
  required Uint8List imageBytes,
  required String mimeType,
  required List<Map<String, dynamic>> catalog,
  String languageHint = 'de',
}) async {
  final catJson = jsonEncode(catalog);
  final system = StringBuffer()
    ..write(
      'You are a meal recognition assistant. The user image shows a meal. ',
    )
    ..write(
      'You are given a JSON array "catalog" of allowed foods. Each item has: ',
    )
    ..write('n=exact name (unique string), p=protein g/100g, c=carbs g/100g, '
        'f=fat g/100g, k=kcal/100g, cat=category. ')
    ..write('Task: 1) Identify which foods from "catalog" best match what is visible. ')
    ..write('2) In each item, set "name" to the EXACT string "n" of one catalog entry. ')
    ..write('3) Estimate portion size in grams for what is on the plate (visible amount). ')
    ..write('4) dish: 2-4 sentences describing the whole plate in language "$languageHint". ')
    ..write('Return ONLY valid JSON, no markdown: '
        '{"dish":"...","items":[{"name":"<exact n>","grams":123.0}]} '
        'If you cannot map a visible food, omit it. Prefer several specific items over one vague item. '
        'Do not invent foods that are not in the catalog under "n".');

  final body = {
    'contents': [
      {
        'role': 'user',
        'parts': [
          {'text': '${system.toString()}\n\ncatalog=$catJson'},
          {
            'inline_data': {
              'mime_type': mimeType,
              'data': base64Encode(imageBytes),
            },
          },
        ],
      },
    ],
    'generationConfig': {
      'temperature': 0.25,
      'response_mime_type': 'application/json',
    },
  };

  final uri = Uri.parse('$_kGeminiGenerate?key=${Uri.encodeComponent(apiKey.trim())}');
  final res = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw Exception('timeout'),
      );

  if (res.statusCode != 200) {
    var err = res.body;
    if (err.length > 300) err = err.substring(0, 300);
    throw Exception('HTTP ${res.statusCode}: $err');
  }
  final outer = jsonDecode(res.body) as Map<String, dynamic>;
  final candidates = outer['candidates'] as List<dynamic>?;
  if (candidates == null || candidates.isEmpty) {
    throw Exception('no_candidates');
  }
  final content = candidates[0] as Map<String, dynamic>?;
  final blockReason = content?['finishReason'] as String? ??
      (outer['promptFeedback'] as Map?)?['blockReason'] as String?;
  if (blockReason == 'SAFETY' || blockReason == 'PROHIBITED_CONTENT') {
    throw Exception('blocked');
  }
  final parts = (content?['content'] as Map?)?['parts'] as List<dynamic>?;
  if (parts == null || parts.isEmpty) throw Exception('no_parts');
  final text = (parts[0] as Map)['text'] as String? ?? '';
  if (text.isEmpty) throw Exception('empty_text');
  final data = jsonDecode(_stripJsonFences(text)) as Map<String, dynamic>;
  final dish = (data['dish'] ?? data['dish_description'] ?? '') as String;
  final raw = data['items'];
  final items = <AiLineRaw>[];
  if (raw is List) {
    for (final e in raw) {
      if (e is! Map) continue;
      final name = (e['name'] ?? e['name_from_catalog'] ?? e['n']) as String? ?? '';
      final g = e['grams'] ?? e['g'] ?? 0;
      final grams = g is num ? g.toDouble() : double.tryParse(g.toString()) ?? 0;
      if (name.trim().isEmpty || grams <= 0) continue;
      items.add(AiLineRaw(catalogName: name.trim(), grams: grams));
    }
  }
  return AiMealRaw(dish: dish, items: items);
}

String _stripJsonFences(String s) {
  var t = s.trim();
  if (t.startsWith('```')) {
    t = t.replaceFirst(RegExp(r'^```\w*'), '').trim();
    if (t.endsWith('```')) {
      t = t.substring(0, t.length - 3).trim();
    }
  }
  return t;
}

/// Sucht [Food] per Name — wird von main mit der echten [Food]-Liste aufgerufen.
F? matchFoodByAiName<F>(List<F> db, String aiName, String Function(F) nameOf) {
  final t = aiName.trim();
  if (t.isEmpty) return null;
  for (final f in db) {
    if (nameOf(f) == t) return f;
  }
  final lower = t.toLowerCase();
  for (final f in db) {
    if (nameOf(f).toLowerCase() == lower) return f;
  }
  for (final f in db) {
    final n = nameOf(f).toLowerCase();
    if (n.contains(lower) || lower.contains(n)) {
      if (n.length > 2 && lower.length > 2) return f;
    }
  }
  F? best;
  var bestD = 10000;
  for (final f in db) {
    final d = _levenshtein(nameOf(f).toLowerCase(), lower);
    if (d < bestD) {
      bestD = d;
      best = f;
    }
  }
  final th = 3 + (t.length / 5).floor();
  if (best != null && bestD <= th) return best;
  return null;
}

int _levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  if (a.length > 200) a = a.substring(0, 200);
  if (b.length > 200) b = b.substring(0, 200);
  final m = a.length, n = b.length;
  var row0 = List<int>.generate(n + 1, (i) => i);
  var row1 = List<int>.filled(n + 1, 0);
  for (var i = 0; i < m; i++) {
    row1[0] = i + 1;
    for (var j = 0; j < n; j++) {
      final c = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      var min = row0[j] + c;
      if (row1[j] + 1 < min) min = row1[j] + 1;
      if (row0[j + 1] + 1 < min) min = row0[j + 1] + 1;
      row1[j + 1] = min;
    }
    final tmp = row0;
    row0 = row1;
    row1 = tmp;
  }
  return row0[n];
}
