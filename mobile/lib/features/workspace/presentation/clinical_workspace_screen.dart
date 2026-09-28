import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sync/sync_service.dart';
import '../../../theme/clinical_theme.dart';
import '../../home/data/favorite_medication_repository.dart';
import '../../home/data/recent_medication_repository.dart';

class ClinicalWorkspaceScreen extends StatefulWidget {
  const ClinicalWorkspaceScreen({
    required this.recentRepository,
    required this.favoriteRepository,
    required this.syncCoordinator,
    super.key,
  });

  final RecentMedicationRepository recentRepository;
  final FavoriteMedicationRepository favoriteRepository;
  final ClinicalSyncCoordinator syncCoordinator;

  @override
  State<ClinicalWorkspaceScreen> createState() =>
      _ClinicalWorkspaceScreenState();
}

class _ClinicalWorkspaceScreenState extends State<ClinicalWorkspaceScreen> {
  int _index = 0;
  List<FavoriteMedication> _favorites = const <FavoriteMedication>[];
  List<RecentMedication> _recent = const <RecentMedication>[];
  ClinicalSyncStatus? _syncStatus;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final favorites = await widget.favoriteRepository.loadFavorites();
      final recent = await widget.recentRepository.loadRecent();
      final status = await widget.syncCoordinator.localStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _favorites = favorites;
        _recent = recent;
        _syncStatus = status;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncStatus ??= const ClinicalSyncStatus(
          state: ClinicalSyncState.unavailable,
          hasLocalContent: false,
        );
      });
    }

    try {
      final status = await widget.syncCoordinator.syncIfNeeded(
        onStatus: (value) {
          if (mounted) {
            setState(() => _syncStatus = value);
          }
        },
      );
      if (mounted) {
        setState(() => _syncStatus = status);
      }
    } catch (_) {
      // Offline content remains usable when refresh fails.
    }
  }

  Future<void> _open(String route) async {
    await context.push(route);
    if (!mounted) {
      return;
    }
    try {
      final favorites = await widget.favoriteRepository.loadFavorites();
      final recent = await widget.recentRepository.loadRecent();
      if (!mounted) {
        return;
      }
      setState(() {
        _favorites = favorites;
        _recent = recent;
      });
    } catch (_) {
      // Convenience lists never block clinical content.
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = <String>['Nursing', 'Explorar', 'Estudar', 'Perfil'];
    final pages = <Widget>[
      _WorkspaceHome(
        favorites: _favorites,
        recent: _recent,
        syncStatus: _syncStatus,
        onOpen: _open,
      ),
      _ExplorePage(onOpen: _open),
      _StudyPage(onOpen: _open),
      _ProfilePage(
        favorites: _favorites,
        recent: _recent,
        syncStatus: _syncStatus,
        onOpen: _open,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Busca global',
            onPressed: () => _open('/global-search'),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Assistente clínico',
            onPressed: () => _open('/assistant'),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Explorar',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: 'Estudar',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

class _WorkspaceHome extends StatelessWidget {
  const _WorkspaceHome({
    required this.favorites,
    required this.recent,
    required this.syncStatus,
    required this.onOpen,
  });

  final List<FavoriteMedication> favorites;
  final List<RecentMedication> recent;
  final ClinicalSyncStatus? syncStatus;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Text(
          'O que você precisa fazer agora?',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        _SyncPill(status: syncStatus),
        const SizedBox(height: 16),
        InkWell(
          key: const ValueKey<String>('workspace-global-search'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => onOpen('/global-search'),
          child: Container(
            height: ClinicalTheme.searchHeight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Buscar medicamentos, ferramentas e conteúdos'),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Acesso rápido', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 650 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            _ModuleTile(
              icon: Icons.medication_outlined,
              label: 'Medicamentos',
              onTap: () => onOpen('/search'),
            ),
            _ModuleTile(
              icon: Icons.calculate_outlined,
              label: 'Calculadoras',
              onTap: () => onOpen('/calculators'),
            ),
            _ModuleTile(
              icon: Icons.auto_awesome_outlined,
              label: 'Assistente',
              onTap: () => onOpen('/assistant'),
            ),
            _ModuleTile(
              icon: Icons.hub_outlined,
              label: 'Interações',
              onTap: () => onOpen('/interactions'),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _SectionHeader(
          title: 'Favoritos',
          actionLabel: 'Ver todos',
          onAction: () => onOpen('/favorites'),
        ),
        if (favorites.isEmpty)
          const _EmptyLine(
            icon: Icons.star_border_rounded,
            text: 'Seus conteúdos favoritos aparecerão aqui.',
          )
        else
          ...favorites
              .take(3)
              .map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.medication)),
                  title: Text(item.displayName),
                  subtitle: Text(item.genericName),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onOpen('/medications/${item.id}'),
                ),
              ),
        const SizedBox(height: 18),
        const _SectionHeader(title: 'Recentes'),
        if (recent.isEmpty)
          const _EmptyLine(
            icon: Icons.history_rounded,
            text: 'As fichas consultadas recentemente aparecerão aqui.',
          )
        else
          ...recent
              .take(4)
              .map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.history_rounded),
                  ),
                  title: Text(item.displayName),
                  subtitle: Text(item.genericName),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onOpen('/medications/${item.id}'),
                ),
              ),
      ],
    );
  }
}

class _ExplorePage extends StatelessWidget {
  const _ExplorePage({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    const items = <_ExploreItem>[
      _ExploreItem(
        'Medicamentos',
        'Bulário, apresentações e cálculo seguro',
        Icons.medication_outlined,
        '/search',
      ),
      _ExploreItem(
        'Administração de medicamentos',
        'Consulta por medicamento, forma e via',
        Icons.vaccines_outlined,
        '/catalog/administration',
      ),
      _ExploreItem(
        'Calculadoras & escores',
        'Ferramentas com memória de cálculo',
        Icons.calculate_outlined,
        '/calculators',
      ),
      _ExploreItem(
        'Interações medicamentosas',
        'Verificação com bloqueio seguro sem evidência instalada',
        Icons.hub_outlined,
        '/interactions',
      ),
      _ExploreItem(
        'Procedimentos de enfermagem',
        'Catálogo editorial por procedimento',
        Icons.fact_check_outlined,
        '/catalog/procedures',
      ),
      _ExploreItem(
        'Escalas & instrumentos',
        'Catálogo de escalas e instrumentos',
        Icons.rule_outlined,
        '/catalog/scales',
      ),
      _ExploreItem(
        'Protocolos & fluxogramas',
        'Organização de condutas e fluxos',
        Icons.account_tree_outlined,
        '/catalog/protocols',
      ),
      _ExploreItem(
        'Códigos e tabelas',
        'Estrutura para CID, SUS, TUSS e catálogos locais',
        Icons.code_outlined,
        '/catalog/codes',
      ),
      _ExploreItem(
        'Prescrição e preparo',
        'Guias, conferência e conteúdo editorial versionado',
        Icons.receipt_long_outlined,
        '/areas/prescription',
      ),
      _ExploreItem(
        'Emergência & UTI',
        'Conteúdos por contexto crítico e monitorização',
        Icons.monitor_heart_outlined,
        '/areas/emergency',
      ),
      _ExploreItem(
        'Pediatria',
        'Conteúdo clínico por faixa etária e contexto',
        Icons.child_care_outlined,
        '/areas/pediatrics',
      ),
      _ExploreItem(
        'Saúde da mulher & obstetrícia',
        'Conteúdos de GO, gestação e assistência',
        Icons.pregnant_woman_outlined,
        '/areas/obgyn',
      ),
      _ExploreItem(
        'Cirurgia & perioperatório',
        'Pré, intra e pós-operatório em estrutura editorial',
        Icons.medical_services_outlined,
        '/areas/surgery',
      ),
      _ExploreItem(
        'Antimicrobianos',
        'Consulta estruturada e stewardship',
        Icons.science_outlined,
        '/areas/antimicrobials',
      ),
      _ExploreItem(
        'Vacinação',
        'Imunização, calendários e administração',
        Icons.vaccines_outlined,
        '/areas/vaccination',
      ),
      _ExploreItem(
        'Laboratório & exames',
        'Exames, unidades, coleta e interpretação referenciada',
        Icons.biotech_outlined,
        '/areas/labs',
      ),
      _ExploreItem(
        'Raciocínio diferencial',
        'Jornada estruturada sem inferência sem fonte',
        Icons.psychology_alt_outlined,
        '/differential',
      ),
      _ExploreItem(
        'Assistente clínico',
        'Busca conversacional com fontes locais',
        Icons.auto_awesome_outlined,
        '/assistant',
      ),
      _ExploreItem(
        'Anotações',
        'Notas locais para estudo e organização',
        Icons.note_alt_outlined,
        '/notes',
      ),
    ];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            minTileHeight: 72,
            leading: CircleAvatar(child: Icon(item.icon)),
            title: Text(item.title),
            subtitle: Text(item.subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onOpen(item.route),
          ),
        );
      },
    );
  }
}

class _StudyPage extends StatelessWidget {
  const _StudyPage({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Text('Aprendizagem', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          'Revise conteúdos em sessões curtas e retome seu progresso.',
        ),
        const SizedBox(height: 20),
        _StudyCard(
          icon: Icons.style_outlined,
          title: 'Flashcards',
          subtitle: 'Frente, resposta, acerto/erro e progresso persistente',
          onTap: () => onOpen('/flashcards'),
        ),
        const SizedBox(height: 12),
        _StudyCard(
          icon: Icons.quiz_outlined,
          title: 'Quizzes',
          subtitle: 'Questões com feedback imediato',
          onTap: () => onOpen('/quizzes'),
        ),
        const SizedBox(height: 12),
        _StudyCard(
          icon: Icons.note_alt_outlined,
          title: 'Minhas anotações',
          subtitle: 'Notas salvas somente neste dispositivo',
          onTap: () => onOpen('/notes'),
        ),
      ],
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.favorites,
    required this.recent,
    required this.syncStatus,
    required this.onOpen,
  });

  final List<FavoriteMedication> favorites;
  final List<RecentMedication> recent;
  final ClinicalSyncStatus? syncStatus;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.local_hospital_outlined,
            size: 34,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Espaço clínico local',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        const Text(
          'Conteúdo offline, preferências e estudo neste dispositivo.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        _SyncPill(status: syncStatus),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: const Text('Favoritos'),
                subtitle: Text('${favorites.length} salvos'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onOpen('/favorites'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('Histórico recente'),
                subtitle: Text('${recent.length} itens neste dispositivo'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.note_alt_outlined),
                title: const Text('Minhas anotações'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onOpen('/notes'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Acesso e conteúdo'),
                subtitle: const Text('Gratuito/restrito • modo de teste'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onOpen('/access'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('Nursing 1.5.0'),
            subtitle: Text(
              'Apoio à decisão. Não substitui prescrição, protocolo '
              'institucional ou julgamento clínico.',
            ),
          ),
        ),
      ],
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minTileHeight: 82,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.status});

  final ClinicalSyncStatus? status;

  @override
  Widget build(BuildContext context) {
    final current = status;
    final busy = current?.isBusy ?? true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              current?.hasLocalContent ?? false
                  ? Icons.offline_pin_outlined
                  : Icons.cloud_off_outlined,
              size: 20,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              current?.displayText ?? 'Verificando base clínica',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.icon, required this.text});

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
            size: 34,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ExploreItem {
  const _ExploreItem(this.title, this.subtitle, this.icon, this.route);

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}
