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

  Future<void> _sendOtp() async {
    setState(() {
      _error = null;
      _info = null;
      _otpHint = null;
    });
    final mail = _emailCtrl.text.trim();
    if (!SolCloudConfig.isConfigured) return;
    if (mail.isEmpty) {
      setState(() => _error = 'Bitte gib deine E-Mail ein.');
      return;
    }

    await _setBusy(true);
    try {
      await SolPlannerCloudCoordinator.instance.requestEmailOtp(mail);
      setState(() {
        _otpHint =
            'Wenn das Projekt OTP nutzt: Code aus der E-Mail hier einfügen.';
        _info = 'E-Mail wurde geschickt (Supabase SMTP).';
      });
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      await _setBusy(false);
    }
  }

  Future<void> _verifyOtp() async {
    final mail = _emailCtrl.text.trim();
    final code = _otpCtrl.text.trim();
    setState(() {
      _error = null;
      _info = null;
    });

    if (mail.isEmpty) {
      setState(() => _error = 'Bitte erst E-Mail angeben.');
      return;
    }
    if (code.isEmpty || code.length < 4) {
      setState(() => _error = 'Bitte den Code aus der E-Mail eintragen.');
      return;
    }

    await _setBusy(true);
    try {
      await SolPlannerCloudCoordinator.instance.verifyEmailOtp(
        email: mail,
        token: code,
      );
      await SolPlannerCloudCoordinator.instance.setSyncEnabled(true);
      if (mounted) {
        setState(() {
          _syncOn = true;
          _info = 'Angemeldet. Nutze dieselbe E-Mail auf jedem Gerät.';
          _otpCtrl.clear();
        });
      }
      SolPlannerCloudCoordinator.instance.schedulePushDebounced();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
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
      setState(() => _error = 'Erst mit E-Mail anmelden.');
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
      setState(() => _error = 'Erst mit E-Mail anmelden.');
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
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'E-Mail',
              hintText: 'dieselbe Adresse auf jedem Gerät',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _sendOtp,
              child: const Text('Code anfordern'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otpCtrl,
            autocorrect: false,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: 'Einmalcode (OTP)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: _busy ? null : _verifyOtp,
              child: const Text('Anmelden'),
            ),
          ),
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
