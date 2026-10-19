// KI-Illustration für Rezept-Dialog: Imagen (gleicher API-Key wie Gemini).
// Cache nur im Speicher (Web-sicher, kein dart:io).

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const _imagenModels = <String>[
  'imagen-4.0-fast-generate-001',
  'imagen-4.0-generate-001',
];

final Map<String, Uint8List> _memoryRecipePng = {};

Future<Uint8List?> readCachedRecipeImage(String foodName) async {
  return _memoryRecipePng[foodName];
}

Future<void> writeCachedRecipeImage(String foodName, Uint8List png) async {
  _memoryRecipePng[foodName] = png;
}

String buildImagenFoodPrompt({
  required String dishName,
  String? portionHint,
  String? firstInstruction,
}) {
  final buf = StringBuffer()
    ..write('Professional food photography, appetizing, soft natural light, '
        '85mm macro, shallow depth of field, on a clean plate, European home-cooking. ')
    ..write('Dish: $dishName. ');
  if (portionHint != null && portionHint.trim().isNotEmpty) {
    buf.write('Note: ${portionHint.trim()}. ');
  }
  if (firstInstruction != null && firstInstruction.trim().isNotEmpty) {
    final t = firstInstruction.trim();
    buf.write('Look and texture hint: ${t.length > 160 ? t.substring(0, 160) : t}. ');
  }
  buf.write('No people, no text, no watermark overlay, no cutlery in frame if possible.');
  return buf.toString();
}

Uint8List? _decodeB64(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return base64Decode(
      s.replaceAll('-', '+').replaceAll('_', '/'),
    );
  } catch (_) {
    return null;
  }
}

dynamic _firstGeneratedImageB64(Map<String, dynamic> o) {
  for (final key in const ['generatedImages', 'images', 'predictions']) {
    final g = o[key];
    if (g is! List || g.isEmpty) continue;
    final first = g[0];
    if (first is! Map) continue;
    final m = Map<String, dynamic>.from(first);
    if (m['image'] is Map) {
      final im = Map<String, dynamic>.from(m['image']! as Map);
      for (final k in const ['imageBytes', 'bytesBase64Encoded', 'data']) {
        if (im[k] != null) return im[k];
      }
    }
    for (final k in const ['imageBytes', 'bytesBase64Encoded', 'bytes']) {
      if (m[k] != null) return m[k];
    }
  }
  return null;
}

/// Liefert PNG-Bytes. Wirft [Exception] bei API-/Parse-Fehlern.
Future<Uint8List> requestImagenRecipeImagePng({
  required String apiKey,
  required String prompt,
}) async {
  final k = apiKey.trim();
  if (k.isEmpty) throw Exception('no_api_key');

  Exception? lastErr;
  for (final model in _imagenModels) {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:predict?key=${Uri.encodeComponent(k)}',
    );
    final body = <String, dynamic>{
      'instances': [
        {'prompt': prompt},
      ],
      'parameters': {
        'sampleCount': 1,
        'aspectRatio': '4:3',
      },
    };
    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 120),
            onTimeout: () => throw Exception('timeout'),
          );
      if (res.statusCode == 404) {
        lastErr = Exception('model_404');
        continue;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        var e = res.body;
        if (e.length > 500) e = e.substring(0, 500);
        throw Exception('HTTP ${res.statusCode}: $e');
      }
      final outer = jsonDecode(res.body) as Map<String, dynamic>;
      final rawB64 = _firstGeneratedImageB64(outer);
      String? s;
      if (rawB64 is String) s = rawB64;
      if (s == null) {
        lastErr = Exception('parse: no image in response');
        continue;
      }
      final bytes = _decodeB64(s);
      if (bytes == null || bytes.isEmpty) {
        lastErr = Exception('parse: b64');
        continue;
      }
      return bytes;
    } catch (e) {
      lastErr = e is Exception ? e : Exception(e.toString());
    }
  }
  if (lastErr != null) throw lastErr;
  throw Exception('imagen_unavailable');
}
