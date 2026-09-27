import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/clinical_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const Key searchKey = ValueKey<String>('home-search');
  static const Key doseActionKey = ValueKey<String>('quick-action-dose');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nursing'),
        centerTitle: false,
      ),
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
                    key: searchKey,
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.push('/search'),
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
                _SectionTitle(
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
                            key: doseActionKey,
                            icon: Icons.medication_outlined,
                            label: 'Calcular dose',
                            onPressed: () =>
                                context.push('/calculators/dose'),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _QuickAction(
                            icon: Icons.water_drop_outlined,
                            label: 'Infusão',
                            onPressed: () =>
                                context.push('/calculators/infusion'),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _QuickAction(
                            icon: Icons.opacity_outlined,
                            label: 'Gotejamento',
                            onPressed: () =>
                                context.push('/calculators/drip'),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _QuickAction(
                            icon: Icons.monitor_weight_outlined,
                            label: 'mg/kg',
                            onPressed: () =>
                                context.push('/calculators/mg-kg'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                const _SectionTitle(
                  title: 'Recentes',
                  subtitle: 'Medicamentos visualizados',
                ),
                const SizedBox(height: 12),
                const _RecentEmptyState(),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Base clínica local • sincronização ainda não configurada',
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
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

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
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 24),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(label),
      ),
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
