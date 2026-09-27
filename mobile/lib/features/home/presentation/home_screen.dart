import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/clinical_theme.dart';
import '../data/recent_medication_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.recentRepository, super.key});

  static const Key searchKey = ValueKey<String>('home-search');
  static const Key doseActionKey = ValueKey<String>('quick-action-dose');
  static const Key infusionActionKey = ValueKey<String>(
    'quick-action-infusion',
  );
  static const Key dropsActionKey = ValueKey<String>('quick-action-drops');

  final RecentMedicationRepository recentRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RecentMedication> _recent = const <RecentMedication>[];
  bool _loadingRecent = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final recent = await widget.recentRepository.loadRecent();
      if (!mounted) {
        return;
      }
      setState(() {
        _recent = recent;
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recent = const <RecentMedication>[];
        _loadingRecent = false;
      });
    }
  }

  Future<void> _openAndRefresh(String route) async {
    await context.push(route);
    if (mounted) {
      await _loadRecent();
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
                  title: 'Recentes',
                  subtitle: 'Medicamentos visualizados neste dispositivo',
                ),
                const SizedBox(height: 12),
                if (_loadingRecent)
                  const _RecentLoadingState()
                else if (_recent.isEmpty)
                  const _RecentEmptyState()
                else
                  ..._recent.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RecentMedicationCard(
                        item: item,
                        onTap: () => _openAndRefresh('/medications/${item.id}'),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
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
                        'Recentes ficam somente neste dispositivo e não '
                        'armazenam dados de pacientes.',
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (item.genericName != item.displayName) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.genericName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
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

class _RecentLoadingState extends StatelessWidget {
  const _RecentLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 96,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _RecentEmptyState extends StatelessWidget {
  const _RecentEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history_rounded,
            size: 30,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Nenhum medicamento visualizado recentemente.',
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}
