import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sol/cloud/sol_cloud_config.dart';
import 'package:sol/cloud/sol_planner_cloud_sync.dart';

/// Cloud sync sheet: Supabase OTP login + sync controls.
///
/// Caller should pass [onAppliedRemotePayload] after a successful „Aus Cloud laden“ so
/// the planner reloads SharedPreferences state.
Future<void> showSolCloudSyncSheet(
  BuildContext context, {
  required Future<void> Function() onAppliedRemotePayload,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: _SolCloudSyncBody(
          onAppliedRemotePayload: onAppliedRemotePayload,
        ),
      );
    },
  );
}

class _SolCloudSyncBody extends StatefulWidget {
  const _SolCloudSyncBody({required this.onAppliedRemotePayload});

  final Future<void> Function() onAppliedRemotePayload;

  @override
  State<_SolCloudSyncBody> createState() => _SolCloudSyncBodyState();
}

class _SolCloudSyncBodyState extends State<_SolCloudSyncBody> {
  StreamSubscription<AuthState>? _authSub;

  late TextEditingController _emailCtrl;
  late TextEditingController _otpCtrl;
  late bool _syncOn;
  String? _otpHint;
  String? _error;
  String? _info;
  bool _busy = false;

  bool get _hasSession =>
      SolPlannerCloudCoordinator.instance.currentUser != null;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController();
    _otpCtrl = TextEditingController();
    _busy = false;
    _syncOn = false;
    if (SolCloudConfig.isConfigured) {
      SolPlannerCloudCoordinator.instance.syncEnabledPrefs().then((v) {
        if (mounted) setState(() => _syncOn = v);
      });

      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _setBusy(bool v) async {
    if (mounted) setState(() => _busy = v);
  }

  Future<void> _afterLogin() async {
    await SolPlannerCloudCoordinator.instance.setSyncEnabled(true);
    // Gibt es schon einen Cloud-Stand (anderes Gerät)? Dann holen, sonst hochladen.
    final applied = await SolPlannerCloudCoordinator.instance
        .pullAndApplyIfNewer(forceIgnoreMarker: true);
    if (applied) {
      await widget.onAppliedRemotePayload();
    } else {
      await SolPlannerCloudCoordinator.instance.pushNow();
    }
    if (mounted) {
      setState(() {
        _syncOn = true;
        _info = applied
            ? 'Angemeldet – Stand aus der Cloud geladen.'
            : 'Angemeldet – dein Stand ist jetzt in der Cloud.';
        _otpCtrl.clear();
      });
    }
  }

  Future<void> _login({required bool create}) async {
    final mail = _emailCtrl.text.trim();
    final pw = _otpCtrl.text;
    setState(() {
      _error = null;
      _info = null;
      _otpHint = null;
    });
    if (mail.isEmpty || !mail.contains('@')) {
      setState(() => _error = 'Bitte gib deine E-Mail ein.');
      return;
    }
    if (pw.length < 6) {
      setState(() => _error = 'Passwort: mindestens 6 Zeichen.');
      return;
    }
    await _setBusy(true);
    try {
      if (create) {
        final direct =
            await SolPlannerCloudCoordinator.instance.signUpPassword(mail, pw);
        if (!direct) {
          setState(() => _otpHint =
              'Bestätigungs-Mail ist unterwegs. Link in der Mail antippen, danach hier mit E-Mail + Passwort anmelden.');
          return;
        }
      } else {
        await SolPlannerCloudCoordinator.instance.signInPassword(mail, pw);
      }
      await _afterLogin();
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      setState(() => _error = m.contains('invalid login')
          ? 'E-Mail oder Passwort stimmt nicht (oder Konto noch nicht bestätigt).'
          : m.contains('not confirmed')
              ? 'Bitte erst den Link in der Bestätigungs-Mail antippen.'
              : m.contains('already registered')
                  ? 'Konto gibt es schon – einfach anmelden.'
                  : e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      await _setBusy(false);
    }
  }

  Future<void> _upload() async {
    setState(() {
      _error = null;
      _info = null;
    });
    if (!_hasSession) {
      setState(() => _error = 'Erst anmelden.');
      return;
    }
    await SolPlannerCloudCoordinator.instance.setSyncEnabled(true);
    await _setBusy(true);
    await SolPlannerCloudCoordinator.instance.pushNow();
    await _setBusy(false);
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Lokaler Stand nach Cloud hochgeladen.')),
      );
      setState(() => _syncOn = true);
    }
  }

  Future<void> _pull() async {
    setState(() {
      _error = null;
      _info = null;
    });
    if (!_hasSession) {
      setState(() => _error = 'Erst anmelden.');
      return;
    }
    await SolPlannerCloudCoordinator.instance.setSyncEnabled(true);
    await _setBusy(true);
    try {
      final applied =
          await SolPlannerCloudCoordinator.instance.pullAndApplyIfNewer(
            forceIgnoreMarker: true,
          );
      if (applied) {
        await widget.onAppliedRemotePayload();
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Cloud-Stand eingespielt.'),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Kein neuer Stand in der Cloud (oder noch keine Daten dort).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      await _setBusy(false);
    }
  }

  Future<void> _signOut() async {
    await _setBusy(true);
    await SolPlannerCloudCoordinator.instance.setSyncEnabled(false);
    await SolPlannerCloudCoordinator.instance.signOut();
    await _setBusy(false);
    if (mounted) {
      setState(() => _syncOn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!SolCloudConfig.isConfigured) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Cloud-Sync',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            'Supabase ist nicht konfiguriert. Beim Build URL und anon key mitgeben:\n\n'
            '--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…\n\n'
            'Anleitung: supabase/README_SYNC.md',
            style:
                textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      );
    }

    final uidShort = SolPlannerCloudCoordinator.instance.currentUser?.id;
    final sessionLine = !_hasSession
        ? 'Nicht angemeldet.'
        : 'Angemeldet${uidShort != null ? ' (…${uidShort.substring(uidShort.length - 6)})' : ''}';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cloud-Sync',
            style:
                textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            sessionLine,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (_otpHint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _otpHint!,
                style: textTheme.bodySmall?.copyWith(color: cs.primary),
              ),
            ),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_info!, style: textTheme.bodyMedium),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: textTheme.bodyMedium?.copyWith(color: cs.error),
              ),
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Automatischen Abgleich', style: textTheme.titleSmall),
            subtitle: Text(
              'Änderungen mit Verzögerung hochladen; beim Start ggf. neuer Cloud-Stand.',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            value: _syncOn,
            onChanged: _busy || !_hasSession
                ? null
                : (v) async {
                    setState(() => _syncOn = v);
                    await SolPlannerCloudCoordinator.instance.setSyncEnabled(v);
                  },
          ),
          if (!_hasSession) ...[
            const SizedBox(height: 12),
            Text(
              'Mit demselben Konto auf jedem Gerät anmelden – dann sind Plan, Presets und Zeiten überall gleich.',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'E-Mail',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _otpCtrl,
              autocorrect: false,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Passwort',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onSubmitted: (_) => _login(create: false),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _login(create: false),
                    child: const Text('Anmelden'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _busy ? null : () => _login(create: true),
                    child: const Text('Konto erstellen'),
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _upload,
                  child: const Text('Hochladen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _pull,
                  child: const Text('Aus Cloud'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ablage-Inbox und Willkommens-Dialog werden nicht synchronisiert.',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _busy ? null : _signOut,
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
  }
}
