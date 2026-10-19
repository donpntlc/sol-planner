// Einmaliges Freischalten-Quiz für die Einleitungs-Texte (separat von Lern-Stufen 1–3).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sol/education_quiz.dart';

class IntroUnlockQuiz {
  static Future<bool> run(
    BuildContext context, {
    required String Function(String) t,
    required String title,
    required String wrongMsg,
  }) async {
    if (!context.mounted) return false;
    final r = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) {
        return _IntroUnlockScaffold(
          title: title,
          questions: kIntroUnlockQuestions,
          t: t,
          wrongMsg: wrongMsg,
        );
      },
    );
    return r == true;
  }
}

class _IntroUnlockScaffold extends StatefulWidget {
  const _IntroUnlockScaffold({
    required this.title,
    required this.questions,
    required this.t,
    required this.wrongMsg,
  });
  final String title;
  final List<EducationQuestion> questions;
  final String Function(String) t;
  final String wrongMsg;

  @override
  State<_IntroUnlockScaffold> createState() => _IntroUnlockScaffoldState();
}

class _IntroUnlockScaffoldState extends State<_IntroUnlockScaffold> {
  var _i = 0;

  int get _total => widget.questions.length;
  int get _step => _i + 1;
  EducationQuestion get _q => widget.questions[_i];

  void _onPick(int optionIndex) {
    if (optionIndex == _q.correctIndex) {
      HapticFeedback.mediumImpact();
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
                      widget.title,
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
