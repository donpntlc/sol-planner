// Vollbild-Quiz pro Stufe: Fortschritt, überspringt erledigte Fragen, klares UI.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sol/education_quiz.dart';

class EducationLevelQuiz {
  /// Zeigt nacheinander alle noch nicht bestandenen Fragen der Stufe.
  /// [onMastered] pro richtig beantworteter Frage (für setState + Speichern).
  /// Rückgabe: `true` = alle Fragen der Session gemeistert oder schon davor
  /// erledigt; `false` = abgebrochen.
  static Future<bool> run(
    BuildContext context, {
    required int level,
    required Set<String> passedIds,
    required void Function(String id) onMastered,
    required String Function(String) t,
    required String levelTitle,
    required String wrongMsg,
  }) async {
    if (!context.mounted) return false;
    final all = kEducationQuestions.where((e) => e.level == level).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final remaining = all.where((e) => !passedIds.contains(e.id)).toList();
    if (remaining.isEmpty) {
      return true;
    }
    final r = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) {
        return _EduLevelQuizScaffold(
          levelTitle: levelTitle,
          questions: remaining,
          t: t,
          onMastered: onMastered,
          wrongMsg: wrongMsg,
        );
      },
    );
    return r == true;
  }
}

class _EduLevelQuizScaffold extends StatefulWidget {
  const _EduLevelQuizScaffold({
    required this.levelTitle,
    required this.questions,
    required this.t,
    required this.onMastered,
    required this.wrongMsg,
  });
  final String levelTitle;
  final List<EducationQuestion> questions;
  final String Function(String) t;
  final void Function(String id) onMastered;
  final String wrongMsg;

  @override
  State<_EduLevelQuizScaffold> createState() => _EduLevelQuizScaffoldState();
}

class _EduLevelQuizScaffoldState extends State<_EduLevelQuizScaffold> {
  var _i = 0;

  int get _total => widget.questions.length;
  int get _step => _i + 1;
  EducationQuestion get _q => widget.questions[_i];

  void _onPick(int optionIndex) {
    if (optionIndex == _q.correctIndex) {
      HapticFeedback.mediumImpact();
      widget.onMastered(_q.id);
      if (!mounted) return;
      if (_i + 1 >= _total) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _i++);
      }
    } else {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.wrongMsg),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final on = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: widget.t("cancel"),
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close, color: on),
                  ),
                  Expanded(
                    child: Text(
                      widget.levelTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: on,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      "$_step / $_total",
                      style: TextStyle(
                        color: on.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _step / _total,
                  minHeight: 5,
                  backgroundColor: on.withValues(alpha: 0.1),
                  color: const Color(0xFFD4AF37),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.t(_q.qKey),
                      style: TextStyle(
                        color: on,
                        fontSize: 17.2,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    for (int o = 0; o < _q.oKeys.length; o++) ...[
                      if (o > 0) const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () => _onPick(o),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2620),
                          foregroundColor: on,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Color(0xFF4A4338),
                            ),
                          ),
                        ),
                        child: Text(
                          widget.t(_q.oKeys[o]),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
