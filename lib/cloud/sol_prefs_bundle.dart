import 'package:shared_preferences/shared_preferences.dart';

import 'package:sol/cloud/sol_sync_pref_keys.dart';

Future<Map<String, String>> solReadSyncedStringPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final out = <String, String>{};
  for (final k in kSolSyncedPlannerStringPrefKeys) {
    final v = prefs.getString(k);
    if (v != null) out[k] = v;
  }
  return out;
}

/// Writes string prefs; [null] values remove the key.
Future<void> solWriteSyncedStringPrefs(Map<String, String?> data) async {
  final prefs = await SharedPreferences.getInstance();
  for (final e in data.entries) {
    if (e.value == null) {
      await prefs.remove(e.key);
    } else {
      await prefs.setString(e.key, e.value!);
    }
  }
}
