import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalNotesScreen extends StatefulWidget {
  const LocalNotesScreen({super.key});

  @override
  State<LocalNotesScreen> createState() => _LocalNotesScreenState();
}

class _LocalNotesScreenState extends State<LocalNotesScreen> {
  static const _storageKey = 'clinical_notes_v1';
  List<_LocalNote> _notes = const <_LocalNote>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return;
      }
      final notes =
          decoded
              .whereType<Map>()
              .map(
                (item) => _LocalNote.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList(growable: false)
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (mounted) {
        setState(() => _notes = notes);
      }
    } catch (_) {
      // Personal notes never affect clinical content availability.
    }
  }

  Future<void> _save(List<_LocalNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(notes.map((item) => item.toJson()).toList(growable: false)),
    );
    if (mounted) {
      setState(() => _notes = notes);
    }
  }

  Future<void> _edit({_LocalNote? note}) async {
    final title = TextEditingController(text: note?.title ?? '');
    final body = TextEditingController(text: note?.body ?? '');

    final result = await showModalBottomSheet<_LocalNote>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              note == null ? 'Nova anotação' : 'Editar anotação',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: body,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(labelText: 'Anotação'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final noteTitle = title.text.trim();
                final noteBody = body.text.trim();
                if (noteTitle.isEmpty && noteBody.isEmpty) {
                  return;
                }
                Navigator.pop(
                  context,
                  _LocalNote(
                    id:
                        note?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    title: noteTitle.isEmpty ? 'Sem título' : noteTitle,
                    body: noteBody,
                    updatedAt: DateTime.now().toUtc(),
                  ),
                );
              },
              child: const Text('SALVAR'),
            ),
          ],
        ),
      ),
    );

    title.dispose();
    body.dispose();

    if (result == null) {
      return;
    }
    final next = <_LocalNote>[
      result,
      ..._notes.where((item) => item.id != result.id),
    ];
    await _save(next);
  }

  Future<void> _delete(_LocalNote note) async {
    await _save(
      _notes.where((item) => item.id != note.id).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minhas anotações')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova nota'),
      ),
      body: _notes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: _EmptyState(
                  icon: Icons.note_alt_outlined,
                  text: 'Crie uma anotação para estudo ou organização pessoal.',
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: _notes.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final note = _notes[index];
                return Card(
                  child: ListTile(
                    title: Text(note.title),
                    subtitle: Text(
                      note.body.isEmpty ? 'Sem texto' : note.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _edit(note: note),
                    trailing: IconButton(
                      tooltip: 'Excluir',
                      onPressed: () => _delete(note),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  static const _storageKey = 'flashcard_progress_v1';
  static const _cards = <_Flashcard>[
    _Flashcard(
      'O que significa um resultado LASA no Nursing?',
      'Um resultado aproximado por nome semelhante. A seleção deve ser '
          'confirmada pelo profissional antes de abrir ou calcular.',
    ),
    _Flashcard(
      'Quando o cálculo de dose fica disponível?',
      'Somente quando a apresentação possui concentração estruturada e '
          'marcada como validada para cálculo.',
    ),
    _Flashcard(
      'O que acontece quando um cálculo exige arredondamento não aprovado?',
      'O cálculo é interrompido. O aplicativo não aplica arredondamento '
          'clínico implícito.',
    ),
    _Flashcard(
      'A ausência de dado de interação significa ausência de interação?',
      'Não. O módulo bloqueia a conclusão quando a base de evidências não está '
          'instalada.',
    ),
    _Flashcard(
      'Qual é a função da memória de cálculo?',
      'Mostrar a fórmula aplicada, os valores e as unidades para conferência.',
    ),
    _Flashcard(
      'O assistente pode inventar uma conduta quando não encontra fonte?',
      'Não. No modo local ele informa a ausência de evidência e não produz '
          'orientação clínica inferida.',
    ),
  ];

  int _index = 0;
  int _correct = 0;
  int _incorrect = 0;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      return;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) {
        return;
      }
      setState(() {
        _index = (json['index'] as num?)?.toInt() ?? 0;
        _correct = (json['correct'] as num?)?.toInt() ?? 0;
        _incorrect = (json['incorrect'] as num?)?.toInt() ?? 0;
        if (_index >= _cards.length) {
          _index = 0;
        }
      });
    } catch (_) {
      // Invalid study state is reset silently.
    }
  }

  Future<void> _answer(bool correct) async {
    setState(() {
      if (correct) {
        _correct++;
      } else {
        _incorrect++;
      }
      _index = (_index + 1) % _cards.length;
      _revealed = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(<String, int>{
        'index': _index,
        'correct': _correct,
        'incorrect': _incorrect,
      }),
    );
  }

  Future<void> _reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    if (mounted) {
      setState(() {
        _index = 0;
        _correct = 0;
        _incorrect = 0;
        _revealed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _cards[_index];
    final total = _correct + _incorrect;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flashcards'),
        actions: [
          IconButton(
            tooltip: 'Reiniciar',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'Uso seguro do Nursing',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text('Revisões acumuladas: ' + total.toString()),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: (_index + 1) / _cards.length),
          const SizedBox(height: 24),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _revealed = true),
            child: Container(
              constraints: const BoxConstraints(minHeight: 260),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  _revealed ? card.back : card.front,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (!_revealed)
            FilledButton(
              onPressed: () => setState(() => _revealed = true),
              child: const Text('MOSTRAR RESPOSTA'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _answer(false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Errei'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _answer(true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Acertei'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Text(
            'Acertos: ' +
                _correct.toString() +
                ' • Erros: ' +
                _incorrect.toString(),
          ),
        ],
      ),
    );
  }
}

class QuizzesScreen extends StatefulWidget {
  const QuizzesScreen({super.key});

  @override
  State<QuizzesScreen> createState() => _QuizzesScreenState();
}

class _QuizzesScreenState extends State<QuizzesScreen> {
  static const _questions = <_QuizQuestion>[
    _QuizQuestion(
      'Um nome digitado retorna um resultado aproximado/LASA. Qual ação é segura?',
      <String>[
        'Confirmar a identidade do medicamento antes de prosseguir',
        'Assumir que é o medicamento correto',
        'Calcular automaticamente',
      ],
      0,
      'Resultados por nomes semelhantes exigem confirmação explícita.',
    ),
    _QuizQuestion(
      'A apresentação não possui concentração estruturada. O que o Nursing faz?',
      <String>[
        'Estima a concentração',
        'Bloqueia o cálculo automático',
        'Usa a primeira apresentação disponível',
      ],
      1,
      'O cálculo fica bloqueado para evitar inferência de concentração.',
    ),
    _QuizQuestion(
      'O módulo de interação não possui base de evidências instalada. O resultado correto é:',
      <String>[
        'Sem interação',
        'Interação leve',
        'Sem conclusão; consultar fonte validada',
      ],
      2,
      'Ausência de dados não é evidência de ausência de interação.',
    ),
    _QuizQuestion(
      'Quando um resultado exige arredondamento clínico não configurado, o motor:',
      <String>[
        'Arredonda automaticamente',
        'Interrompe o cálculo',
        'Sempre arredonda para cima',
      ],
      1,
      'O motor fail-closed evita arredondamento implícito.',
    ),
  ];

  int _index = 0;
  int? _selected;
  int _score = 0;

  void _select(int value) {
    if (_selected != null) {
      return;
    }
    setState(() {
      _selected = value;
      if (value == _questions[_index].correctIndex) {
        _score++;
      }
    });
  }

  void _next() {
    setState(() {
      if (_index == _questions.length - 1) {
        _index = 0;
        _score = 0;
      } else {
        _index++;
      }
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final question = _questions[_index];
    return Scaffold(
      appBar: AppBar(title: const Text('Quizzes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'Questão ' +
                (_index + 1).toString() +
                ' de ' +
                _questions.length.toString(),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (_index + 1) / _questions.length),
          const SizedBox(height: 22),
          Text(question.prompt, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          for (var i = 0; i < question.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RadioListTile<int>(
                value: i,
                groupValue: _selected,
                onChanged: _selected == null
                    ? (value) {
                        if (value != null) {
                          _select(value);
                        }
                      }
                    : null,
                title: Text(question.options[i]),
              ),
            ),
          if (_selected != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _selected == question.correctIndex
                      ? 'Correto. ' + question.explanation
                      : 'Resposta: ' +
                            question.options[question.correctIndex] +
                            '. ' +
                            question.explanation,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _next,
              child: Text(
                _index == _questions.length - 1
                    ? 'REINICIAR QUIZ'
                    : 'PRÓXIMA QUESTÃO',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text('Pontuação atual: ' + _score.toString()),
        ],
      ),
    );
  }
}

class _LocalNote {
  const _LocalNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  factory _LocalNote.fromJson(Map<String, dynamic> json) {
    final rawDate = json['updated_at'];
    return _LocalNote(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Sem título',
      body: json['body']?.toString() ?? '',
      updatedAt:
          DateTime.tryParse(rawDate?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'body': body,
    'updated_at': updatedAt.toIso8601String(),
  };
}

class _Flashcard {
  const _Flashcard(this.front, this.back);

  final String front;
  final String back;
}

class _QuizQuestion {
  const _QuizQuestion(
    this.prompt,
    this.options,
    this.correctIndex,
    this.explanation,
  );

  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 42,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center),
      ],
    );
  }
}
