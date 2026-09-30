import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/clinical_theme.dart';
import '../../home/data/favorite_medication_repository.dart';
import '../../medication/data/medication_models.dart';
import '../../medication/data/medication_repository.dart';

class GlobalClinicalSearchScreen extends StatefulWidget {
  const GlobalClinicalSearchScreen({required this.repository, super.key});

  final MedicationRepository repository;

  @override
  State<GlobalClinicalSearchScreen> createState() =>
      _GlobalClinicalSearchScreenState();
}

enum _GlobalSearchFilter { all, medications, tools, study }

class _GlobalClinicalSearchScreenState
    extends State<GlobalClinicalSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  _GlobalSearchFilter _filter = _GlobalSearchFilter.all;
  List<MedicationSearchResult> _medications = const <MedicationSearchResult>[];
  List<String> _history = const <String>[];
  bool _loading = false;
  String? _error;

  static const _actions = <_SearchAction>[
    _SearchAction(
      'Bulas profissionais',
      'Textos em português offline',
      Icons.menu_book_outlined,
      '/leaflets',
      _GlobalSearchFilter.medications,
    ),
    _SearchAction(
      'Calculadoras & escores',
      'Ferramenta',
      Icons.calculate_outlined,
      '/calculators',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Interações medicamentosas',
      'Ferramenta',
      Icons.hub_outlined,
      '/interactions',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Administração de medicamentos',
      'Conteúdo',
      Icons.vaccines_outlined,
      '/catalog/administration',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Procedimentos de enfermagem',
      'Conteúdo',
      Icons.fact_check_outlined,
      '/catalog/procedures',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Escalas & instrumentos',
      'Conteúdo',
      Icons.rule_outlined,
      '/catalog/scales',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Protocolos & fluxogramas',
      'Conteúdo',
      Icons.account_tree_outlined,
      '/catalog/protocols',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Prescrição e preparo',
      'Conteúdo',
      Icons.receipt_long_outlined,
      '/areas/prescription',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Emergência & UTI',
      'Conteúdo',
      Icons.monitor_heart_outlined,
      '/areas/emergency',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Pediatria',
      'Conteúdo',
      Icons.child_care_outlined,
      '/areas/pediatrics',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Saúde da mulher & obstetrícia',
      'Conteúdo',
      Icons.pregnant_woman_outlined,
      '/areas/obgyn',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Cirurgia & perioperatório',
      'Conteúdo',
      Icons.medical_services_outlined,
      '/areas/surgery',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Antimicrobianos',
      'Conteúdo',
      Icons.science_outlined,
      '/areas/antimicrobials',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Vacinação',
      'Conteúdo',
      Icons.vaccines_outlined,
      '/areas/vaccination',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Laboratório & exames',
      'Conteúdo',
      Icons.biotech_outlined,
      '/areas/labs',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Raciocínio diferencial',
      'Ferramenta',
      Icons.psychology_alt_outlined,
      '/differential',
      _GlobalSearchFilter.tools,
    ),
    _SearchAction(
      'Flashcards',
      'Estudo',
      Icons.style_outlined,
      '/flashcards',
      _GlobalSearchFilter.study,
    ),
    _SearchAction(
      'Quizzes',
      'Estudo',
      Icons.quiz_outlined,
      '/quizzes',
      _GlobalSearchFilter.study,
    ),
    _SearchAction(
      'Anotações',
      'Pessoal',
      Icons.note_alt_outlined,
      '/notes',
      _GlobalSearchFilter.study,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history =
        prefs.getStringList('global_search_history_v1') ?? const <String>[];
    if (mounted) {
      setState(() => _history = history.take(8).toList(growable: false));
    }
  }

  Future<void> _saveHistory(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) {
      return;
    }
    final next = <String>[
      normalized,
      ..._history.where(
        (item) => item.toLowerCase() != normalized.toLowerCase(),
      ),
    ].take(8).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('global_search_history_v1', next);
    if (mounted) {
      setState(() => _history = next);
    }
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('global_search_history_v1');
    if (mounted) {
      setState(() => _history = const <String>[]);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _medications = const <MedicationSearchResult>[];
        _error = null;
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(query));
  }

  Future<void> _run(String query) async {
    try {
      final response = await widget.repository.searchMedications(query);
      await _saveHistory(query);
      if (!mounted || _controller.text.trim() != query) {
        return;
      }
      setState(() {
        _medications = response.items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Não foi possível consultar a base clínica local.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final actions = _actions
        .where((item) {
          final matchesFilter =
              _filter == _GlobalSearchFilter.all || item.filter == _filter;
          final matchesText =
              query.isEmpty || item.title.toLowerCase().contains(query);
          return matchesFilter && matchesText;
        })
        .toList(growable: false);
    final showMedications =
        _filter == _GlobalSearchFilter.all ||
        _filter == _GlobalSearchFilter.medications;

    return Scaffold(
      appBar: AppBar(title: const Text('Pesquisa global')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (value) {
                _onChanged(value);
                setState(() {});
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Medicamento, ferramenta ou conteúdo',
              ),
            ),
            if (showMedications)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Pesquisar nas bulas profissionais'),
                subtitle: const Text(
                  'Textos do fabricante em português, disponíveis offline',
                ),
                onTap: () => context.push(
                  Uri(
                    path: '/leaflets',
                    queryParameters: {'q': _controller.text.trim()},
                  ).toString(),
                ),
              ),
            if (_controller.text.trim().isEmpty && _history.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pesquisas recentes',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _clearHistory,
                    child: const Text('Limpar'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _history
                    .map(
                      (item) => ActionChip(
                        label: Text(item),
                        onPressed: () {
                          _controller.text = item;
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: item.length),
                          );
                          _onChanged(item);
                          setState(() {});
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Tudo'),
                  selected: _filter == _GlobalSearchFilter.all,
                  onSelected: (_) =>
                      setState(() => _filter = _GlobalSearchFilter.all),
                ),
                FilterChip(
                  label: const Text('Medicamentos'),
                  selected: _filter == _GlobalSearchFilter.medications,
                  onSelected: (_) =>
                      setState(() => _filter = _GlobalSearchFilter.medications),
                ),
                FilterChip(
                  label: const Text('Ferramentas'),
                  selected: _filter == _GlobalSearchFilter.tools,
                  onSelected: (_) =>
                      setState(() => _filter = _GlobalSearchFilter.tools),
                ),
                FilterChip(
                  label: const Text('Estudo'),
                  selected: _filter == _GlobalSearchFilter.study,
                  onSelected: (_) =>
                      setState(() => _filter = _GlobalSearchFilter.study),
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[const SizedBox(height: 14), Text(_error!)],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Módulos', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              ...actions.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(item.icon),
                  title: Text(item.title),
                  subtitle: Text(item.type),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(item.route),
                ),
              ),
            ],
            if (showMedications && _medications.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Medicamentos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              ..._medications.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.isMedicationProduct
                        ? Icons.medication_outlined
                        : Icons.science_outlined,
                  ),
                  title: Text(item.displayName),
                  subtitle: Text(
                    item.secondaryName ??
                        (item.isApproximate
                            ? 'Resultado aproximado / nome semelhante'
                            : 'Princípio ativo'),
                  ),
                  trailing: item.isMedicationProduct
                      ? const Icon(Icons.chevron_right_rounded)
                      : null,
                  onTap: item.isMedicationProduct
                      ? () => context.push('/medications/${item.id}')
                      : null,
                ),
              ),
            ],
            if (query.length >= 2 &&
                !_loading &&
                actions.isEmpty &&
                (!showMedications || _medications.isEmpty))
              const _QuietState(
                icon: Icons.search_off_rounded,
                text: 'Nenhum resultado encontrado nesta base local.',
              ),
          ],
        ),
      ),
    );
  }
}

class CalculatorsHubScreen extends StatelessWidget {
  const CalculatorsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const tools = <_HubTool>[
      _HubTool(
        'Dose por apresentação',
        'Selecione um medicamento com concentração estruturada',
        Icons.medication_outlined,
        '/search',
      ),
      _HubTool(
        'Velocidade de infusão',
        'Volume em mL e tempo em horas/minutos',
        Icons.water_drop_outlined,
        '/calculators/infusion',
      ),
      _HubTool(
        'Gotejamento',
        'Macro e microgotas com memória de cálculo',
        Icons.opacity_outlined,
        '/calculators/drip',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Calculadoras & escores')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const _SafetyBanner(
            text:
                'As ferramentas calculam somente fórmulas instaladas e '
                'validadas. Não há sugestão automática de dose ou '
                'arredondamento clínico.',
          ),
          const SizedBox(height: 12),
          ...tools.map(
            (tool) => Card(
              child: ListTile(
                minTileHeight: 76,
                leading: CircleAvatar(child: Icon(tool.icon)),
                title: Text(tool.title),
                subtitle: Text(tool.subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(tool.route),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _ContentPackCard(
            title: 'Escores adicionais',
            message:
                'O motor e a navegação estão prontos para novos escores. '
                'Cada ferramenta permanece bloqueada até receber fórmula, '
                'unidades, interpretação e referência clínica versionadas.',
          ),
        ],
      ),
    );
  }
}

class ClinicalAssistantScreen extends StatefulWidget {
  const ClinicalAssistantScreen({required this.repository, super.key});

  final MedicationRepository repository;

  @override
  State<ClinicalAssistantScreen> createState() =>
      _ClinicalAssistantScreenState();
}

class _ClinicalAssistantScreenState extends State<ClinicalAssistantScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_AssistantTurn> _turns = <_AssistantTurn>[];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final query = _controller.text.trim();
    if (query.length < 2 || _loading) {
      return;
    }

    setState(() {
      _turns.add(_AssistantTurn.user(query));
      _controller.clear();
      _loading = true;
    });

    try {
      final response = await widget.repository.searchMedications(query);
      if (!mounted) {
        return;
      }
      final products = response.items
          .where((item) => item.isMedicationProduct)
          .take(6)
          .toList(growable: false);
      final answer = products.isEmpty
          ? 'Não encontrei medicamento correspondente na base clínica '
                'instalada. Não vou inferir uma resposta sem fonte local.'
          : 'Encontrei ${products.length} resultado(s) na base offline. Abra a ficha para conferir apresentações, registro e recursos de cálculo.';
      setState(() {
        _turns.add(_AssistantTurn.assistant(answer, results: products));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _turns.add(
          _AssistantTurn.assistant(
            'A consulta local falhou. Nenhuma orientação clínica foi gerada.',
          ),
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assistente clínico')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SafetyBanner(
                text:
                    'Modo local rastreável: o assistente consulta somente a '
                    'base instalada e não inventa condutas quando não há fonte.',
              ),
            ),
            Expanded(
              child: _turns.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: _QuietState(
                          icon: Icons.auto_awesome_outlined,
                          text:
                              'Digite um medicamento ou princípio ativo para '
                              'consultar a base clínica local.',
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _turns.length,
                      itemBuilder: (context, index) =>
                          _AssistantBubble(turn: _turns[index]),
                    ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Pergunte pela base clínica...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Enviar',
                    onPressed: _loading ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InteractionCheckerScreen extends StatefulWidget {
  const InteractionCheckerScreen({required this.repository, super.key});

  final MedicationRepository repository;

  @override
  State<InteractionCheckerScreen> createState() =>
      _InteractionCheckerScreenState();
}

class _InteractionCheckerScreenState extends State<InteractionCheckerScreen> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  MedicationSearchResult? _firstMatch;
  MedicationSearchResult? _secondMatch;
  bool _loading = false;
  bool _checked = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<MedicationSearchResult?> _findProduct(String query) async {
    final response = await widget.repository.searchMedications(query);
    for (final item in response.items) {
      if (item.isMedicationProduct) {
        return item;
      }
    }
    return null;
  }

  Future<void> _check() async {
    final firstQuery = _first.text.trim();
    final secondQuery = _second.text.trim();
    if (firstQuery.length < 2 || secondQuery.length < 2 || _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _checked = false;
    });

    try {
      final results = await Future.wait<MedicationSearchResult?>([
        _findProduct(firstQuery),
        _findProduct(secondQuery),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _firstMatch = results[0];
        _secondMatch = results[1];
        _loading = false;
        _checked = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _firstMatch = null;
        _secondMatch = null;
        _loading = false;
        _checked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<ClinicalSemanticColors>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Interações medicamentosas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          TextField(
            controller: _first,
            decoration: const InputDecoration(
              labelText: 'Primeiro medicamento',
              prefixIcon: Icon(Icons.medication_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _second,
            decoration: const InputDecoration(
              labelText: 'Segundo medicamento',
              prefixIcon: Icon(Icons.medication_outlined),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _check,
            icon: const Icon(Icons.hub_outlined),
            label: const Text('VERIFICAR'),
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_checked) ...[
            const SizedBox(height: 18),
            if (_firstMatch == null || _secondMatch == null)
              const _ContentPackCard(
                title: 'Não foi possível identificar os dois medicamentos',
                message:
                    'Refine os nomes e tente novamente. Nenhuma conclusão '
                    'sobre interação foi produzida.',
              )
            else ...[
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.looks_one_outlined),
                      title: Text(_firstMatch!.displayName),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          context.push('/medications/${_firstMatch!.id}'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.looks_two_outlined),
                      title: Text(_secondMatch!.displayName),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          context.push('/medications/${_secondMatch!.id}'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: semantic.warningContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Base de evidências de interação ainda não está instalada. '
                  'Por segurança, o Nursing não interpreta ausência de dados '
                  'como ausência de interação. Consulte uma fonte institucional '
                  'validada antes de administrar.',
                  style: TextStyle(
                    color: semantic.onWarningContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({required this.repository, super.key});

  final FavoriteMedicationRepository repository;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<FavoriteMedication>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.loadFavorites();
      if (mounted) {
        setState(() => _items = items);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _items = const <FavoriteMedication>[]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: _QuietState(
                  icon: Icons.star_border_rounded,
                  text: 'Nenhum conteúdo favoritado neste dispositivo.',
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: const Icon(Icons.star_rounded),
                  title: Text(item.displayName),
                  subtitle: Text(item.genericName),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await context.push('/medications/${item.id}');
                    if (mounted) {
                      await _load();
                    }
                  },
                );
              },
            ),
    );
  }
}

class ClinicalCatalogScreen extends StatefulWidget {
  const ClinicalCatalogScreen({
    required this.title,
    required this.description,
    required this.topics,
    super.key,
  });

  final String title;
  final String description;
  final List<String> topics;

  @override
  State<ClinicalCatalogScreen> createState() => _ClinicalCatalogScreenState();
}

class _ClinicalCatalogScreenState extends State<ClinicalCatalogScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final topics = widget.topics
        .where((topic) => query.isEmpty || topic.toLowerCase().contains(query))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(widget.description),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Pesquisar neste catálogo',
            ),
          ),
          const SizedBox(height: 14),
          for (final topic in topics)
            Card(
              child: ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(topic),
                subtitle: const Text('Pacote editorial ainda não instalado'),
                trailing: const Icon(Icons.lock_outline_rounded),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(topic),
                    content: const Text(
                      'A navegação deste módulo está pronta, mas o Nursing '
                      'mantém o conteúdo bloqueado até que a ficha clínica '
                      'tenha fonte, revisão e versionamento aprovados.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (topics.isEmpty)
            const _QuietState(
              icon: Icons.search_off_rounded,
              text: 'Nenhum item corresponde ao filtro.',
            ),
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.turn});

  final _AssistantTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alignment = turn.isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final background = turn.isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final textColor = turn.isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(turn.text, style: TextStyle(color: textColor)),
            for (final item in turn.results) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/medications/${item.id}'),
                icon: const Icon(Icons.medication_outlined),
                label: Text(item.displayName),
              ),
            ],
            if (!turn.isUser) ...[
              const SizedBox(height: 6),
              Text(
                'Fonte: base clínica local Anvisa/CMED.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<ClinicalSemanticColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: semantic.informationContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: semantic.onInformationContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: semantic.onInformationContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentPackCard extends StatelessWidget {
  const _ContentPackCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _QuietState extends StatelessWidget {
  const _QuietState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(
            icon,
            size: 36,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _SearchAction {
  const _SearchAction(
    this.title,
    this.type,
    this.icon,
    this.route,
    this.filter,
  );

  final String title;
  final String type;
  final IconData icon;
  final String route;
  final _GlobalSearchFilter filter;
}

class _HubTool {
  const _HubTool(this.title, this.subtitle, this.icon, this.route);

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}

class _AssistantTurn {
  const _AssistantTurn._({
    required this.isUser,
    required this.text,
    this.results = const <MedicationSearchResult>[],
  });

  factory _AssistantTurn.user(String text) =>
      _AssistantTurn._(isUser: true, text: text);

  factory _AssistantTurn.assistant(
    String text, {
    List<MedicationSearchResult> results = const <MedicationSearchResult>[],
  }) => _AssistantTurn._(isUser: false, text: text, results: results);

  final bool isUser;
  final String text;
  final List<MedicationSearchResult> results;
}
