import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String clinicalAccessPreviewKey = 'nursing_access_full_preview_v1';

class ClinicalAreaHubScreen extends StatefulWidget {
  const ClinicalAreaHubScreen({
    required this.title,
    required this.description,
    required this.groups,
    this.restricted = false,
    super.key,
  });

  final String title;
  final String description;
  final Map<String, List<String>> groups;
  final bool restricted;

  @override
  State<ClinicalAreaHubScreen> createState() => _ClinicalAreaHubScreenState();
}

class _ClinicalAreaHubScreenState extends State<ClinicalAreaHubScreen> {
  final TextEditingController _search = TextEditingController();
  String? _selectedGroup;
  bool _fullAccessPreview = false;

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.groups.keys.firstOrNull;
    _loadAccess();
  }

  Future<void> _loadAccess() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _fullAccessPreview = prefs.getBool(clinicalAccessPreviewKey) ?? false;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final groups = widget.groups.entries.where((entry) {
      if (query.isEmpty) {
        return true;
      }
      return entry.key.toLowerCase().contains(query) ||
          entry.value.any((topic) => topic.toLowerCase().contains(query));
    }).toList(growable: false);

    final selectedGroup = _selectedGroup;
    final visibleGroups = query.isNotEmpty
        ? groups
        : groups.where((entry) => entry.key == selectedGroup).toList();

    final locked = widget.restricted && !_fullAccessPreview;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.restricted)
            Icon(
              locked ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(widget.description),
          const SizedBox(height: 12),
          _EditorialBanner(restricted: widget.restricted, locked: locked),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Pesquisar nesta área',
            ),
          ),
          const SizedBox(height: 12),
          if (query.isEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.groups.keys
                    .map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(group),
                          selected: group == _selectedGroup,
                          onSelected: (_) =>
                              setState(() => _selectedGroup = group),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          const SizedBox(height: 16),
          for (final entry in visibleGroups) ...[
            Text(entry.key, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final topic in entry.value)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(topic),
                  subtitle: Text(
                    locked
                        ? 'Conteúdo restrito • modo de teste disponível no Perfil'
                        : 'Ficha estruturada por abas, fonte e revisão editorial',
                  ),
                  trailing: Icon(
                    locked
                        ? Icons.lock_outline_rounded
                        : Icons.chevron_right_rounded,
                  ),
                  onTap: locked
                      ? () => _showLocked(context)
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (context) => ClinicalTopicShellScreen(
                              title: topic,
                              area: widget.title,
                            ),
                          ),
                        ),
                ),
              ),
            const SizedBox(height: 12),
          ],
          if (visibleGroups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: Text('Nenhum conteúdo encontrado.')),
            ),
        ],
      ),
    );
  }

  void _showLocked(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conteúdo restrito'),
        content: const Text(
          'A regra de controle de acesso está ativa. Para testar a jornada '
          'completa sem cobrança, habilite o modo de acesso completo em '
          'Perfil > Acesso e conteúdo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class ClinicalTopicShellScreen extends StatelessWidget {
  const ClinicalTopicShellScreen({
    required this.title,
    required this.area,
    super.key,
  });

  final String title;
  final String area;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Resumo'),
              Tab(text: 'Aplicação'),
              Tab(text: 'Alertas'),
              Tab(text: 'Fontes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TopicTab(
              icon: Icons.description_outlined,
              title: 'Resumo editorial',
              text:
                  'Estrutura pronta para conteúdo clínico revisado do módulo '
                  '$area. O Nursing não preenche informação clínica sem uma '
                  'fonte aprovada e versionada.',
            ),
            const _TopicTab(
              icon: Icons.fact_check_outlined,
              title: 'Aplicação clínica',
              text:
                  'Esta aba suporta população, contexto, via, pré-requisitos, '
                  'passos e documentação. O pacote clínico ainda não está '
                  'instalado para este item.',
            ),
            const _TopicTab(
              icon: Icons.warning_amber_rounded,
              title: 'Alertas e segurança',
              text:
                  'Área preparada para contraindicações, sinais de alarme, '
                  'limites e checagens. Nenhum alerta é inferido sem evidência '
                  'editorial instalada.',
            ),
            const _SourcesTab(),
          ],
        ),
      ),
    );
  }
}

class DifferentialReasoningScreen extends StatefulWidget {
  const DifferentialReasoningScreen({super.key});

  @override
  State<DifferentialReasoningScreen> createState() =>
      _DifferentialReasoningScreenState();
}

class _DifferentialReasoningScreenState
    extends State<DifferentialReasoningScreen> {
  final TextEditingController _complaint = TextEditingController();
  final TextEditingController _context = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _complaint.dispose();
    _context.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Raciocínio diferencial')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const _SafetyCard(
            text:
                'O Nursing organiza a consulta, mas não gera diagnósticos sem '
                'uma base clínica rastreável. Esta versão testa a jornada e '
                'mantém o resultado bloqueado na ausência de conteúdo validado.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _complaint,
            decoration: const InputDecoration(
              labelText: 'Queixa principal',
              prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _context,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Contexto e achados relevantes',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => setState(() => _submitted = true),
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('ORGANIZAR HIPÓTESES'),
          ),
          if (_submitted) ...[
            const SizedBox(height: 18),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Base diferencial não instalada',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'A interface registrou a queixa e o contexto, mas não '
                      'produziu hipóteses diagnósticas. O comportamento é '
                      'intencional e fail-closed até a instalação de conteúdo '
                      'clínico revisado e versionado.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AccessAndContentScreen extends StatefulWidget {
  const AccessAndContentScreen({super.key});

  @override
  State<AccessAndContentScreen> createState() => _AccessAndContentScreenState();
}

class _AccessAndContentScreenState extends State<AccessAndContentScreen> {
  bool _fullPreview = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _fullPreview = prefs.getBool(clinicalAccessPreviewKey) ?? false;
      });
    }
  }

  Future<void> _setPreview(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(clinicalAccessPreviewKey, value);
    if (mounted) {
      setState(() => _fullPreview = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acesso e conteúdo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const _SafetyCard(
            text:
                'Este controle simula as regras de conteúdo gratuito/restrito '
                'para teste do produto. Não há cobrança, assinatura ou '
                'processamento de pagamento nesta versão.',
          ),
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              value: _fullPreview,
              onChanged: _setPreview,
              title: const Text('Acesso completo — modo de teste'),
              subtitle: Text(
                _fullPreview
                    ? 'Conteúdos restritos ficam navegáveis em modo estrutural.'
                    : 'Conteúdos restritos exibem a jornada de bloqueio.',
              ),
              secondary: Icon(
                _fullPreview
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.public_rounded),
                  title: Text('Conteúdo básico'),
                  subtitle: Text(
                    'Medicamentos, busca, favoritos e ferramentas já '
                    'instaladas permanecem acessíveis.',
                  ),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.workspace_premium_outlined),
                  title: Text('Conteúdo restrito'),
                  subtitle: Text(
                    'Módulos editoriais podem exigir perfil de acesso quando '
                    'forem publicados em produção.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorialBanner extends StatelessWidget {
  const _EditorialBanner({
    required this.restricted,
    required this.locked,
  });

  final bool restricted;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final text = restricted
        ? locked
              ? 'Área com controle de acesso ativo. Conteúdo clínico só é '
                    'publicado com fonte e revisão.'
              : 'Modo de teste completo ativo. As fichas permanecem sem '
                    'conteúdo clínico não validado.'
        : 'Cada ficha exige fonte, data de revisão, contexto e versionamento.';
    return _SafetyCard(text: text);
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _TopicTab extends StatelessWidget {
  const _TopicTab({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(icon, size: 40),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(text),
      ],
    );
  }
}

class _SourcesTab extends StatelessWidget {
  const _SourcesTab();

  @override
  Widget build(BuildContext context) {
    return const ListView(
      padding: EdgeInsets.all(20),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.source_outlined),
          title: Text('Fonte clínica'),
          subtitle: Text('Pendente de pacote editorial validado'),
        ),
        Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.event_available_outlined),
          title: Text('Data de revisão'),
          subtitle: Text('Não publicada'),
        ),
        Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.people_outline_rounded),
          title: Text('População / contexto'),
          subtitle: Text('Deve ser explicitado pelo conteúdo versionado'),
        ),
        Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.history_rounded),
          title: Text('Versionamento'),
          subtitle: Text('Aguardando release clínico'),
        ),
      ],
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
