import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sync/sync_service.dart';
import '../../../theme/clinical_theme.dart';
import '../data/favorite_medication_repository.dart';
import '../data/recent_medication_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.recentRepository,
    required this.favoriteRepository,
    required this.syncCoordinator,
    super.key,
  });

  static const Key searchKey = ValueKey<String>('home-search');
  static const Key doseActionKey = ValueKey<String>('quick-action-dose');
  static const Key infusionActionKey = ValueKey<String>(
    'quick-action-infusion',
  );
  static const Key dropsActionKey = ValueKey<String>('quick-action-drops');
  static const Key syncStatusKey = ValueKey<String>('clinical-sync-status');

  final RecentMedicationRepository recentRepository;
  final FavoriteMedicationRepository favoriteRepository;
  final ClinicalSyncCoordinator syncCoordinator;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RecentMedication> _recent = const <RecentMedication>[];
  List<FavoriteMedication> _favorites = const <FavoriteMedication>[];
  ClinicalSyncStatus? _syncStatus;
  bool _loadingLocalLists = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadLocalLists();

    ClinicalSyncStatus localStatus;
    try {
      localStatus = await widget.syncCoordinator.localStatus();
    } catch (_) {
      localStatus = const ClinicalSyncStatus(
        state: ClinicalSyncState.unavailable,
        hasLocalContent: false,
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _syncStatus = ClinicalSyncStatus(
        state: ClinicalSyncState.syncing,
        hasLocalContent: localStatus.hasLocalContent,
        contentVersion: localStatus.contentVersion,
        lastSyncAt: localStatus.lastSyncAt,
      );
    });

    ClinicalSyncStatus syncStatus;
    try {
      syncStatus = await widget.syncCoordinator.syncIfNeeded();
    } catch (_) {
      syncStatus = ClinicalSyncStatus(
        state: localStatus.hasLocalContent
            ? ClinicalSyncState.offlineAvailable
            : ClinicalSyncState.unavailable,
        hasLocalContent: localStatus.hasLocalContent,
        contentVersion: localStatus.contentVersion,
        lastSyncAt: localStatus.lastSyncAt,
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _syncStatus = syncStatus;
    });

    if (syncStatus.state == ClinicalSyncState.updated) {
      await _loadLocalLists();
    }
  }

  Future<void> _loadLocalLists() async {
    List<RecentMedication> recent;
    List<FavoriteMedication> favorites;

    try {
      recent = await widget.recentRepository.loadRecent();
    } catch (_) {
      recent = const <RecentMedication>[];
    }

    try {
      favorites = await widget.favoriteRepository.loadFavorites();
    } catch (_) {
      favorites = const <FavoriteMedication>[];
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _recent = recent;
      _favorites = favorites;
      _loadingLocalLists = false;
    });
  }

  Future<void> _openAndRefresh(String route) async {
    await context.push(route);
    if (mounted) {
      await _loadLocalLists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Nursing'), centerTitle: false),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Text(
                  'O que você precisa fazer agora?',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: 'Buscar medicamento ou princípio ativo',
                  child: InkWell(
                    key: HomeScreen.searchKey,
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openAndRefresh('/search'),
                    child: Container(
                      height: ClinicalTheme.searchHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 28,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Buscar medicamento ou princípio ativo',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const _SectionTitle(
                  title: 'Calculadoras',
                  subtitle: 'Ações rápidas',
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 12.0;
                    final width = constraints.maxWidth >= 520
                        ? (constraints.maxWidth - gap) / 2
                        : constraints.maxWidth;

                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: width,
                          child: _QuickAction(
                            key: HomeScreen.doseActionKey,
                            icon: Icons.medication_outlined,
                            label: 'Calcular dose',
                            onPressed: () => context.push('/calculators/dose'),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _QuickAction(
                            key: HomeScreen.infusionActionKey,
                            icon: Icons.water_drop_outlined,
                            label: 'Infusão',
                            onPressed: () =>
                                context.push('/calculators/infusion'),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _QuickAction(
                            key: HomeScreen.dropsActionKey,
                            icon: Icons.opacity_outlined,
                            label: 'Gotejamento',
                            onPressed: () => context.push('/calculators/drip'),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _QuickAction(
                            icon: Icons.monitor_weight_outlined,
                            label: 'mg/kg',
                            onPressed: () => context.push('/calculators/mg-kg'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                const _SectionTitle(
                  title: 'Favoritos',
                  subtitle: 'Acesso rápido offline',
                ),
                const SizedBox(height: 12),
                if (_loadingLocalLists)
                  const _ListLoadingState()
                else if (_favorites.isEmpty)
                  const _FavoriteEmptyState()
                else
                  ..._favorites.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FavoriteMedicationCard(
                        item: item,
                        onTap: () =>
                            _openAndRefresh('/medications/${item.id}'),
                      ),
                    ),
                  ),
                const SizedBox(height: 26),
                const _SectionTitle(
                  title: 'Recentes',
                  subtitle: 'Medicamentos visualizados neste dispositivo',
                ),
                const SizedBox(height: 12),
                if (_loadingLocalLists)
                  const _ListLoadingState()
                else if (_recent.isEmpty)
                  const _RecentEmptyState()
                else
                  ..._recent.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RecentMedicationCard(
                        item: item,
                        onTap: () =>
                            _openAndRefresh('/medications/${item.id}'),
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                _SyncStatusCard(status: _syncStatus),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Favoritos e recentes ficam somente neste dispositivo. '
                        'Nenhum dado de paciente é armazenado.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({required this.status});

  final ClinicalSyncStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = status;

    final icon = switch (current?.state) {
      ClinicalSyncState.current || ClinicalSyncState.updated =>
        Icons.offline_pin_outlined,
      ClinicalSyncState.syncing => Icons.sync_rounded,
      ClinicalSyncState.offlineAvailable => Icons.cloud_off_outlined,
      ClinicalSyncState.notDownloaded || ClinicalSyncState.unavailable =>
        Icons.warning_amber_rounded,
      null => Icons.sync_rounded,
    };

    return Semantics(
      label: current?.displayText ?? 'Verificando base clínica',
      child: Container(
        key: HomeScreen.syncStatusKey,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                current?.displayText ?? 'Verificando base clínica',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(subtitle, style: textTheme.bodyMedium),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 24),
      label: Align(alignment: Alignment.centerLeft, child: Text(label)),
      style: FilledButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size(
          ClinicalTheme.minimumTouchTarget,
          ClinicalTheme.primaryActionHeight,
        ),
      ),
    );
  }
}

class _FavoriteMedicationCard extends StatelessWidget {
  const _FavoriteMedicationCard({
    required this.item,
    required this.onTap,
  });

  final FavoriteMedication item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey<String>('favorite-${item.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: ClinicalTheme.primaryActionHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.star_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: _MedicationLabel(
                    displayName: item.displayName,
                    genericName: item.genericName,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentMedicationCard extends StatelessWidget {
  const _RecentMedicationCard({required this.item, required this.onTap});

  final RecentMedication item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey<String>('recent-${item.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: ClinicalTheme.primaryActionHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: _MedicationLabel(
                    displayName: item.displayName,
                    genericName: item.genericName,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MedicationLabel extends StatelessWidget {
  const _MedicationLabel({
    required this.displayName,
    required this.genericName,
  });

  final String displayName;
  final String genericName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(displayName, style: theme.textTheme.titleMedium),
        if (genericName != displayName) ...[
          const SizedBox(height: 3),
          Text(
            genericName,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ListLoadingState extends StatelessWidget {
  const _ListLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 72,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _FavoriteEmptyState extends StatelessWidget {
  const _FavoriteEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      icon: Icons.star_border_rounded,
      text: 'Nenhum medicamento favoritado.',
    );
  }
}

class _RecentEmptyState extends StatelessWidget {
  const _RecentEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      icon: Icons.history_rounded,
      text: 'Nenhum medicamento visualizado recentemente.',
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 28,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
