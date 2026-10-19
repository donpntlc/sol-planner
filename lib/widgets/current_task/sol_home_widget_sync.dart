import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:home_widget/home_widget.dart';

import 'models.dart';
import 'resolver.dart';

/// Synchronisiert Daten mit nativen Homescreen‑/Lockscreen‑Widgets (iOS/Android).
/// Benötigt [HomeWidget.setAppGroupId] (iOS) und ein Widget‑Target in Xcode sowie
/// [CurrentTaskHomeWidget] unter Android — siehe [native_widgets/README.md].
abstract final class SolHomeWidgetSync {
  static const androidQualifiedName =
      'com.example.sol_day_planner.CurrentTaskHomeWidget';


  static const iosWidgetKind = 'SolCurrentTaskWidget';

  /// Alle WidgetKit-[kind]-Strings der Extension — nach Datenupdate neu laden.
  static const iosWidgetKinds = <String>[
    'SolCurrentTaskWidget',
    'SolLockRectangularWidget',
    'SolLockInlineWidget',
    'SolLockCircularWidget',
  ];

  static const appGroup =
      'group.com.dean.solDayPlanner.widgets';

  static Future<void> ensureConfigured() async {
    if (kIsWeb) return;
    if (!(Platform.isIOS || Platform.isAndroid)) return;
    try {
      await HomeWidget.setAppGroupId(appGroup);
    } catch (e, st) {
      assert(() {
        debugPrint('SolHomeWidgetSync.ensureConfigured failed: $e\n$st');
        return true;
      }());
    }
  }

  /// Schreibt Titel/Unterzeile und löst Aktualisierung aus.
  static Future<void> publish(CurrentTaskViewModel vm) async {
    if (kIsWeb) return;
    if (!(Platform.isIOS || Platform.isAndroid)) return;
    try {
      await ensureConfigured();

      /// Flache Schlüssel (ohne Parser in Kotlin/Swift lesbar).
      final title =
          vm.isIdle ? '' : vm.title.trim();
      final subtitle = vm.isIdle ? '' : vm.subtitle.trim();
      final range =
          vm.isIdle ? '' : vm.rangeLabel.trim();

      await Future.wait([
        HomeWidget.saveWidgetData<String>(
          'sol_w_title',
          title.isEmpty && !vm.isIdle ? '(Block)' : (title.isEmpty ? 'SOL Planer' : title),
        ),
        HomeWidget.saveWidgetData<String>(
          'sol_w_subtitle',
          vm.isIdle ? 'Kein Block in dieser Minute' : subtitle,
        ),
        HomeWidget.saveWidgetData<String>('sol_w_range', range),
        HomeWidget.saveWidgetData<String>('sol_w_idle', vm.isIdle ? '1' : '0'),
        HomeWidget.saveWidgetData<String>('sol_w_remain', '${vm.remainingMinutes ?? ''}'),
        HomeWidget.saveWidgetData<String>('sol_w_payload', jsonPayloadForBridge(vm)),
        HomeWidget.saveWidgetData<String>('sol_w_accent', '${vm.accentArgb}'),
      ]);

      if (Platform.isIOS) {
        for (final kind in iosWidgetKinds) {
          await HomeWidget.updateWidget(
            iOSName: kind,
            name: 'CurrentTaskHomeWidget',
          );
        }
      } else {
        await HomeWidget.updateWidget(
          qualifiedAndroidName: androidQualifiedName,
          name: 'CurrentTaskHomeWidget',
        );
      }
    } catch (_) {
      /// Fehlen der nativen Targets darf den Planer nicht brechen.
    }
  }
}
