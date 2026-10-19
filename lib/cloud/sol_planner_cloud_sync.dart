import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sol/cloud/sol_cloud_config.dart';
import 'package:sol/cloud/sol_planner_sync_hook.dart';
import 'package:sol/cloud/sol_prefs_bundle.dart';
import 'package:sol/cloud/sol_sync_pref_keys.dart';

class SolPlannerCloudCoordinator {
  SolPlannerCloudCoordinator._();
  static final SolPlannerCloudCoordinator instance =
      SolPlannerCloudCoordinator._();

  Timer? _pushDebounce;
  DateTime? _suppressPushUntil;

  bool get isPushSuppressed =>
      _suppressPushUntil != null &&
      DateTime.now().isBefore(_suppressPushUntil!);

  static Future<void> initIfConfigured() async {
    if (!SolCloudConfig.isConfigured) return;
    await Supabase.initialize(
      url: SolCloudConfig.supabaseUrl.trim(),
      anonKey: SolCloudConfig.supabaseAnonKey.trim(),
    );
    instance._wireHook();
  }

  void _wireHook() {
    solOnPlannerDiskDataChanged = schedulePushDebounced;
  }

  User? get currentUser {
    if (!SolCloudConfig.isConfigured) return null;
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<bool> syncEnabledPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kSolCloudSyncEnabledPrefKey) ?? false;
  }

  Future<void> setSyncEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSolCloudSyncEnabledPrefKey, v);
    if (v) schedulePushDebounced();
  }

  void schedulePushDebounced() {
    if (!SolCloudConfig.isConfigured) return;
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 2400), () {
      unawaited(pushNow());
    });
  }

  /// After applying remote snapshot, avoid immediately overwriting the server.
  void suppressPushFor(Duration d) {
    _suppressPushUntil = DateTime.now().add(d);
  }

  Future<void> pushNow() async {
    if (!SolCloudConfig.isConfigured) return;
    if (isPushSuppressed) return;
    if (!await syncEnabledPrefs()) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final map = await solReadSyncedStringPrefs();
    final json = <String, dynamic>{};
    for (final e in map.entries) {
      json[e.key] = e.value;
    }

    try {
      await Supabase.instance.client.from('sol_planner_state').upsert(
        <String, dynamic>{
          'user_id': user.id,
          'prefs': json,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
    } catch (e, st) {
      assert(() {
        // ignore: avoid_print
        print('SolPlannerCloudCoordinator.pushNow failed: $e\n$st');
        return true;
      }());
    }
  }

  /// Returns true if remote data was applied (caller should rehydrate UI).
  ///
  /// [forceIgnoreMarker]: manueller „Aus Cloud“ — auch wenn der Zeitstempel
  /// gleich wirkt oder die Cloud neuer ohne veränderte millis (Recovery).
  Future<bool> pullAndApplyIfNewer({bool forceIgnoreMarker = false}) async {
    if (!SolCloudConfig.isConfigured) return false;
    if (!await syncEnabledPrefs()) return false;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

    final row =
        await Supabase.instance.client
            .from('sol_planner_state')
            .select('prefs, updated_at')
            .eq('user_id', user.id)
            .maybeSingle();

    if (row == null) return false;

    final updatedRaw = row['updated_at'];
    DateTime remoteAt;
    if (updatedRaw is DateTime) {
      remoteAt = updatedRaw.toUtc();
    } else if (updatedRaw is String) {
      remoteAt = DateTime.tryParse(updatedRaw)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!forceIgnoreMarker) {
      final marker = prefs.getString(kSolCloudLastAppliedRemoteAtKey);
      var localKnown = DateTime.fromMillisecondsSinceEpoch(0);
      if (marker != null && marker.isNotEmpty) {
        localKnown = DateTime.tryParse(marker)?.toUtc() ?? localKnown;
      }

      if (!remoteAt.isAfter(localKnown)) return false;
    }

    final rawPrefs = row['prefs'];
    if (rawPrefs is! Map) return false;
    final toWrite = <String, String?>{};
    for (final e in rawPrefs.entries) {
      final k = e.key.toString();
      if (!kSolSyncedPlannerStringPrefKeys.contains(k)) continue;
      final v = e.value;
      if (v == null) {
        toWrite[k] = null;
      } else       if (v is String) {
        toWrite[k] = v;
      } else {
        toWrite[k] = jsonEncode(v);
      }
    }
    if (toWrite.isEmpty) return false;
    await solWriteSyncedStringPrefs(toWrite);
    await prefs.setString(
      kSolCloudLastAppliedRemoteAtKey,
      remoteAt.toUtc().toIso8601String(),
    );
    suppressPushFor(const Duration(seconds: 4));
    return true;
  }

  Future<void> signOut() async {
    if (!SolCloudConfig.isConfigured) return;
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> requestEmailOtp(String email) async {
    if (!SolCloudConfig.isConfigured) return;
    await Supabase.instance.client.auth.signInWithOtp(email: email.trim());
  }

  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) {
    if (!SolCloudConfig.isConfigured) {
      throw StateError('Supabase not configured');
    }
    return Supabase.instance.client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
  }
}
