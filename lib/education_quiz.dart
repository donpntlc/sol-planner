import 'package:sol/dev_refresh_entry.dart';

/// Kurze, spielerische Lern-Checks (3 Stufen, freischaltbar; Texte in [t] in main).
class EducationQuestion {
  const EducationQuestion({
    required this.id,
    required this.level,
    required this.qKey,
    required this.oKeys,
    required this.correctIndex,
  });
  final String id;
  final int level;
  final String qKey;
  final List<String> oKeys;
  final int correctIndex;
}

const List<EducationQuestion> kEducationQuestions = [
  // Stufe 1
  EducationQuestion(
    id: 'l1q1',
    level: 1,
    qKey: 'edu_l1q1',
    oKeys: ['edu_l1q1_o0', 'edu_l1q1_o1', 'edu_l1q1_o2'],
    correctIndex: 1,
  ),
  EducationQuestion(
    id: 'l1q2',
    level: 1,
    qKey: 'edu_l1q2',
    oKeys: ['edu_l1q2_o0', 'edu_l1q2_o1', 'edu_l1q2_o2'],
    correctIndex: 0,
  ),
  EducationQuestion(
    id: 'l1q3',
    level: 1,
    qKey: 'edu_l1q3',
    oKeys: ['edu_l1q3_o0', 'edu_l1q3_o1', 'edu_l1q3_o2'],
    correctIndex: 0,
  ),
  // Stufe 2
  EducationQuestion(
    id: 'l2q1',
    level: 2,
    qKey: 'edu_l2q1',
    oKeys: ['edu_l2q1_o0', 'edu_l2q1_o1', 'edu_l2q1_o2'],
    correctIndex: 1,
  ),
  EducationQuestion(
    id: 'l2q2',
    level: 2,
    qKey: 'edu_l2q2',
    oKeys: ['edu_l2q2_o0', 'edu_l2q2_o1', 'edu_l2q2_o2'],
    correctIndex: 1,
  ),
  // Stufe 3
  EducationQuestion(
    id: 'l3q1',
    level: 3,
    qKey: 'edu_l3q1',
    oKeys: ['edu_l3q1_o0', 'edu_l3q1_o1', 'edu_l3q1_o2'],
    correctIndex: 1,
  ),
  EducationQuestion(
    id: 'l3q2',
    level: 3,
    qKey: 'edu_l3q2',
    oKeys: ['edu_l3q2_o0', 'edu_l3q2_o1', 'edu_l3q2_o2'],
    correctIndex: 0,
  ),
];

/// Freischalten-Quiz: Einleitungs-Texte (kcal-Band & Co.); [level: 0] = nur intro unlock.
const List<EducationQuestion> kIntroUnlockQuestions = [
  EducationQuestion(
    id: 'iu1',
    level: 0,
    qKey: 'intro_unlock_q1',
    oKeys: ['intro_unlock_q1_o0', 'intro_unlock_q1_o1', 'intro_unlock_q1_o2'],
    correctIndex: 0,
  ),
  EducationQuestion(
    id: 'iu2',
    level: 0,
    qKey: 'intro_unlock_q2',
    oKeys: ['intro_unlock_q2_o0', 'intro_unlock_q2_o1', 'intro_unlock_q2_o2'],
    correctIndex: 0,
  ),
  EducationQuestion(
    id: 'iu3',
    level: 0,
    qKey: 'intro_unlock_q3',
    oKeys: ['intro_unlock_q3_o0', 'intro_unlock_q3_o1', 'intro_unlock_q3_o2'],
    correctIndex: 1,
  ),
];

/// Feste Reihenfolge für die Einstufungs-Prüfung (eine Frage pro Lern-Baustein / Stufe).
const List<String> kPlacementQuestionIds = [
  'l1q1',
  'l1q2',
  'l1q3',
  'l2q1',
  'l2q2',
  'l3q1',
  'l3q2',
];

List<EducationQuestion> get kPlacementQuestions => kPlacementQuestionIds
    .map((id) => kEducationQuestions.firstWhere((e) => e.id == id))
    .toList();

/// Aus 0–6 richtigen Antworten: empfohlene Einstiegs-Stufe 1…3.
int levelFromPlacementCorrectCount(int correct) {
  if (correct <= 2) return 1;
  if (correct <= 4) return 2;
  return 3;
}

bool educationLevelFullyPassed(int level, Set<String> done) {
  final need = kEducationQuestions.where((q) => q.level == level).map((e) => e.id);
  return need.isNotEmpty && need.every(done.contains);
}

/// Stufe 2+ erst, wenn alle Fragen der vorherigen Stufe richtig beantwortet.
bool educationLevelAccessible(int level, Set<String> done) {
  if (level <= 1) return true;
  if (level == 2) return educationLevelFullyPassed(1, done);
  if (level == 3) {
    return educationLevelFullyPassed(1, done) && educationLevelFullyPassed(2, done);
  }
  return false;
}
