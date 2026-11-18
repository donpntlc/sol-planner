// Einrichtung beim ersten Start: Aufstehen/Schlafen, Morgen- und Abendroutine,
// feste Termine, Fokus-Blöcke → daraus entsteht ein eigenes Preset „Mein Tag“.
import 'package:flutter/material.dart';

import 'package:sol/main.dart' show PlanningPaletteX;

class OnboardingFixed {
  OnboardingFixed({
    required this.title,
    required this.start,
    required this.end,
    this.must = true,
  });
  String title;
  int start;
  int end;
  bool must;
}

class OnboardingResult {
  OnboardingResult({
    required this.wake,
    required this.sleep,
    required this.morningItems,
    required this.morningMin,
    required this.eveningItems,
    required this.eveningMin,
    required this.fixed,
    required this.focusBlocks,
  });
  final int wake;
  final int sleep;
  final List<String> morningItems;
  final int morningMin;
  final List<String> eveningItems;
  final int eveningMin;
  final List<OnboardingFixed> fixed;
  final int focusBlocks;
}

String _hm(int m) {
  final x = ((m % 1440) + 1440) % 1440;
  return '${(x ~/ 60).toString().padLeft(2, '0')}:${(x % 60).toString().padLeft(2, '0')}';
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  var _page = 0;
  var _wake = 6 * 60 + 30;
  var _sleep = 22 * 60 + 30;
  final _morning = <String>{};
  final _evening = <String>{};
  var _morningMin = 45;
  var _eveningMin = 45;
  final _fixed = <OnboardingFixed>[];
  var _focus = 2;
  final _customM = TextEditingController();
  final _customE = TextEditingController();

  static const _morningSugg = [
    'Gebet / Bibel',
    'Meditation',
    'Journal',
    'Lesen',
    'Dehnen',
    'Spaziergang',
    'Kalt duschen',
    'Frühstück',
  ];
  static const _eveningSugg = [
    'Gebet / Bibel',
    'Lesen',
    'Journal',
    'Tag reflektieren',
    'Wohnung aufräumen',
    'Sachen für morgen',
    'Dehnen',
    'Handy weg',
  ];

  static const _pages = 6;

  @override
  void dispose() {
    _pc.dispose();
    _customM.dispose();
    _customE.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i >= _pages) {
      Navigator.of(context).pop(
        OnboardingResult(
          wake: _wake,
          sleep: _sleep,
          morningItems: _morning.toList(),
          morningMin: _morningMin,
          eveningItems: _evening.toList(),
          eveningMin: _eveningMin,
          fixed: _fixed,
          focusBlocks: _focus,
        ),
      );
      return;
    }
    setState(() => _page = i);
    _pc.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<int?> _pickTime(int initial) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return null;
    return t.hour * 60 + t.minute;
  }

  Widget _title(String t, String sub) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t,
          style: TextStyle(
            color: p.text,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(sub, style: TextStyle(color: p.muted, fontSize: 15, height: 1.4)),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _timeTile(String label, int v, ValueChanged<int> set) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.hairline),
      ),
      child: ListTile(
        title: Text(label, style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
        trailing: Text(
          _hm(v),
          style: TextStyle(color: p.accent, fontSize: 22, fontWeight: FontWeight.w800),
        ),
        onTap: () async {
          final t = await _pickTime(v);
          if (t != null) setState(() => set(t));
        },
      ),
    );
  }

  Widget _durChips(int v, ValueChanged<int> set) {
    final p = context.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in const [15, 30, 45, 60, 90])
          ChoiceChip(
            label: Text('$m min'),
            selected: v == m,
            showCheckmark: false,
            selectedColor: p.accent.withValues(alpha: 0.25),
            side: BorderSide(color: v == m ? p.accent : p.hairline),
            onSelected: (_) => setState(() => set(m)),
          ),
      ],
    );
  }

  Widget _routinePage({
    required String title,
    required String sub,
    required List<String> sugg,
    required Set<String> sel,
    required TextEditingController custom,
    required int minutes,
    required ValueChanged<int> setMin,
  }) {
    final p = context.palette;
    final all = {...sugg, ...sel}.toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      children: [
        _title(title, sub),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in all)
              FilterChip(
                label: Text(s),
                selected: sel.contains(s),
                showCheckmark: false,
                selectedColor: p.accent.withValues(alpha: 0.25),
                side: BorderSide(color: sel.contains(s) ? p.accent : p.hairline),
                onSelected: (v) => setState(() => v ? sel.add(s) : sel.remove(s)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: custom,
          style: TextStyle(color: p.text),
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Eigenes hinzufügen …',
            hintStyle: TextStyle(color: p.muted),
            suffixIcon: IconButton(
              icon: Icon(Icons.add_rounded, color: p.accent),
              onPressed: () {
                final t = custom.text.trim();
                if (t.isEmpty) return;
                setState(() => sel.add(t));
                custom.clear();
              },
            ),
          ),
          onSubmitted: (t) {
            if (t.trim().isEmpty) return;
            setState(() => sel.add(t.trim()));
            custom.clear();
          },
        ),
        const SizedBox(height: 24),
        Text('Wie lange ungefähr?', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _durChips(minutes, setMin),
      ],
    );
  }

  Future<void> _addFixed([String? preset]) async {
    final p = context.palette;
    final nameCtrl = TextEditingController(text: preset ?? '');
    var start = 9 * 60;
    var end = 17 * 60;
    if (preset == 'Training') {
      start = 17 * 60 + 30;
      end = 19 * 60;
    }
    var must = true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: preset == null,
                style: TextStyle(color: p.text, fontSize: 18),
                decoration: const InputDecoration(labelText: 'Was? (z. B. Arbeit, Training)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await _pickTime(start);
                        if (t != null) setS(() => start = t);
                      },
                      child: Text('Von ${_hm(start)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await _pickTime(end);
                        if (t != null) setS(() => end = t);
                      },
                      child: Text('Bis ${_hm(end)}'),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: must,
                activeColor: p.accent,
                title: Text('Must-Do', style: TextStyle(color: p.text)),
                subtitle: Text(
                  'Muss an dem Tag passieren',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                onChanged: (v) => setS(() => must = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Hinzufügen'),
              ),
            ],
          ),
        ),
      ),
    );
    final t = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok == true && t.isNotEmpty && end > start) {
      setState(() => _fixed.add(OnboardingFixed(title: t, start: start, end: end, must: must)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pages = <Widget>[
      ListView(
        padding: const EdgeInsets.fromLTRB(22, 40, 22, 24),
        children: [
          _title(
            'Willkommen 👋',
            'In ein paar Schritten bauen wir deinen Tag:\n\n'
                '• Morgen- & Abendroutine – deine ruhige Zeit am Anfang und Ende des Tages\n'
                '• Feste Termine – Arbeit, Training, alles mit fester Uhrzeit\n'
                '• Fokus-Blöcke – flexibel, du startest sie, wenn es passt\n\n'
                'Alles lässt sich später jederzeit ändern.',
          ),
        ],
      ),
      ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        children: [
          _title('Dein Rhythmus', 'Wann stehst du ungefähr auf – und wann gehst du schlafen?'),
          _timeTile('Aufstehen', _wake, (v) => _wake = v),
          const SizedBox(height: 10),
          _timeTile('Schlafen gehen', _sleep, (v) => _sleep = v),
        ],
      ),
      _routinePage(
        title: 'Morgenroutine',
        sub: 'Wie startest du in den Tag? Wähle, was dazugehört – das ist deine Zeit, bevor die Arbeit beginnt.',
        sugg: _morningSugg,
        sel: _morning,
        custom: _customM,
        minutes: _morningMin,
        setMin: (v) => _morningMin = v,
      ),
      _routinePage(
        title: 'Abendroutine',
        sub: 'Wie fährst du runter? Das kommt am Ende des Tages, vor dem Schlafen.',
        sugg: _eveningSugg,
        sel: _evening,
        custom: _customE,
        minutes: _eveningMin,
        setMin: (v) => _eveningMin = v,
      ),
      ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        children: [
          _title('Feste Termine', 'Was hat bei dir eine feste Uhrzeit? Diese Blöcke bleiben, wo sie sind.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in const ['Arbeit', 'Training', 'Schule / Uni'])
                ActionChip(
                  label: Text('+ $s'),
                  side: BorderSide(color: p.hairline),
                  onPressed: () => _addFixed(s),
                ),
              ActionChip(
                label: const Text('+ Eigenes'),
                side: BorderSide(color: p.hairline),
                onPressed: () => _addFixed(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final f in _fixed)
            Card(
              color: p.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: p.hairline),
              ),
              child: ListTile(
                title: Text(f.title, style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${_hm(f.start)}–${_hm(f.end)}${f.must ? ' · Must-Do' : ''}',
                  style: TextStyle(color: p.muted),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.close_rounded, color: p.muted),
                  onPressed: () => setState(() => _fixed.remove(f)),
                ),
              ),
            ),
          if (_fixed.isEmpty)
            Text('Noch nichts – du kannst das auch überspringen.', style: TextStyle(color: p.muted)),
        ],
      ),
      ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        children: [
          _title(
            'Fokus-Blöcke',
            'Wie viele konzentrierte Arbeitsblöcke willst du am Tag? Sie sind flexibel (60–120 min) – du startest sie in freier Zeit, wann es passt.',
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final n in const [0, 1, 2, 3])
                ChoiceChip(
                  label: Text(n == 0 ? 'Keine' : '$n'),
                  selected: _focus == n,
                  showCheckmark: false,
                  selectedColor: p.accent.withValues(alpha: 0.25),
                  side: BorderSide(color: _focus == n ? p.accent : p.hairline),
                  onSelected: (_) => setState(() => _focus = n),
                ),
            ],
          ),
        ],
      ),
    ];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  if (_page > 0)
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: p.text),
                      onPressed: () => _go(_page - 1),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages; i++)
                          Container(
                            width: i == _page ? 18 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: i == _page ? p.accent : p.hairline,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Später', style: TextStyle(color: p.muted)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pc,
                physics: const NeverScrollableScrollPhysics(),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: p.accent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _go(_page + 1),
                child: Text(
                  _page == 0
                      ? 'Los geht\'s'
                      : _page == _pages - 1
                          ? 'Meinen Tag erstellen'
                          : 'Weiter',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
