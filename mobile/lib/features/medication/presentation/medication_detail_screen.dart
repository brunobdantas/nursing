import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/clinical_theme.dart';
import '../data/medication_models.dart';
import '../data/medication_repository.dart';

class MedicationDetailScreen extends StatefulWidget {
  const MedicationDetailScreen({
    required this.medicationId,
    required this.repository,
    this.startCalculationFlow = false,
    super.key,
  });

  final String medicationId;
  final MedicationRepository repository;
  final bool startCalculationFlow;

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  MedicationDetailResponse? _medication;
  String? _selectedPresentationId;
  String? _errorMessage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final medication = await widget.repository.getMedicationDetail(
        widget.medicationId,
      );
      if (!mounted) {
        return;
      }

      final ready = medication.calculationReadyPresentations;
      setState(() {
        _medication = medication;
        _selectedPresentationId = ready.length == 1 ? ready.single.id : null;
        _loading = false;
      });
    } on MedicationRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _medication = null;
        _errorMessage = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _medication = null;
        _errorMessage = 'Não foi possível carregar a ficha com segurança.';
        _loading = false;
      });
    }
  }

  PresentationDetail? get _selectedPresentation {
    final medication = _medication;
    final selectedId = _selectedPresentationId;
    if (medication == null || selectedId == null) {
      return null;
    }

    for (final presentation in medication.presentations) {
      if (presentation.id == selectedId) {
        return presentation;
      }
    }
    return null;
  }

  void _openCalculator() {
    final medication = _medication;
    final presentation = _selectedPresentation;
    if (medication == null ||
        presentation == null ||
        !presentation.calculationReady ||
        presentation.concentration == null) {
      return;
    }

    context.push('/medications/${medication.id}/calculator/${presentation.id}');
  }

  @override
  Widget build(BuildContext context) {
    final medication = _medication;
    final canCalculate = _selectedPresentation != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Ficha do medicamento')),
      bottomNavigationBar: medication == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                key: const ValueKey<String>('calculate-dose-button'),
                onPressed: canCalculate ? _openCalculator : null,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('CALCULAR DOSE'),
              ),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _DetailErrorState(message: _errorMessage!, onRetry: _load)
            : medication == null
            ? const SizedBox.shrink()
            : _MedicationDetailBody(
                medication: medication,
                selectedPresentationId: _selectedPresentationId,
                startCalculationFlow: widget.startCalculationFlow,
                onSelectPresentation: (presentation) {
                  if (!presentation.calculationReady ||
                      presentation.concentration == null) {
                    return;
                  }
                  setState(() {
                    _selectedPresentationId = presentation.id;
                  });
                },
              ),
      ),
    );
  }
}

class _MedicationDetailBody extends StatelessWidget {
  const _MedicationDetailBody({
    required this.medication,
    required this.selectedPresentationId,
    required this.startCalculationFlow,
    required this.onSelectPresentation,
  });

  final MedicationDetailResponse medication;
  final String? selectedPresentationId;
  final bool startCalculationFlow;
  final ValueChanged<PresentationDetail> onSelectPresentation;

  @override
  Widget build(BuildContext context) {
    final readyPresentations = medication.calculationReadyPresentations;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _IdentitySection(medication: medication),
            const SizedBox(height: 24),
            _SafetySection(
              medication: medication,
              startCalculationFlow: startCalculationFlow,
            ),
            const SizedBox(height: 24),
            Text(
              'Apresentações',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              readyPresentations.isEmpty
                  ? 'Nenhuma apresentação está liberada para cálculo.'
                  : readyPresentations.length == 1
                  ? 'A apresentação validada para cálculo foi pré-selecionada.'
                  : 'Selecione explicitamente a apresentação antes de calcular.',
            ),
            const SizedBox(height: 12),
            for (final presentation in medication.presentations) ...[
              _PresentationCard(
                presentation: presentation,
                selected: presentation.id == selectedPresentationId,
                onTap: () => onSelectPresentation(presentation),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _IdentitySection extends StatelessWidget {
  const _IdentitySection({required this.medication});

  final MedicationDetailResponse medication;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(medication.displayName, style: theme.textTheme.headlineSmall),
        if (medication.brandName != null) ...[
          const SizedBox(height: 6),
          Text(
            medication.genericName,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (medication.activeIngredients.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: medication.activeIngredients
                .map(
                  (ingredient) => Chip(
                    avatar: const Icon(Icons.science_outlined, size: 18),
                    label: Text(ingredient.canonicalName),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 16),
        _MetadataLine(
          label: 'Fabricante',
          value: medication.manufacturerName ?? 'Não informado',
        ),
        _MetadataLine(
          label: 'Registro ANVISA',
          value: medication.anvisaRegistrationNumber ?? 'Não informado',
        ),
        _MetadataLine(
          label: 'Situação regulatória',
          value: medication.regulatoryStatus ?? 'Não informada',
        ),
      ],
    );
  }
}

class _SafetySection extends StatelessWidget {
  const _SafetySection({
    required this.medication,
    required this.startCalculationFlow,
  });

  final MedicationDetailResponse medication;
  final bool startCalculationFlow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;
    final readyCount = medication.calculationReadyPresentations.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Alertas', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: readyCount > 0
                ? semantic.informationContainer
                : semantic.warningContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                readyCount > 0
                    ? Icons.verified_user_outlined
                    : Icons.warning_amber_rounded,
                color: readyCount > 0
                    ? semantic.onInformationContainer
                    : semantic.onWarningContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  readyCount > 0
                      ? 'Cálculo disponível somente nas apresentações '
                            'explicitamente validadas. Confira a apresentação '
                            'antes de prosseguir.'
                      : 'Cálculo automático bloqueado: nenhuma apresentação '
                            'possui concentração estruturada validada.',
                  style: TextStyle(
                    color: readyCount > 0
                        ? semantic.onInformationContainer
                        : semantic.onWarningContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (startCalculationFlow && readyCount > 1) ...[
          const SizedBox(height: 10),
          Text(
            'Para continuar, selecione uma apresentação abaixo.',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _PresentationCard extends StatelessWidget {
  const _PresentationCard({
    required this.presentation,
    required this.selected,
    required this.onTap,
  });

  final PresentationDetail presentation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;
    final selectable =
        presentation.calculationReady && presentation.concentration != null;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: selectable ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  selectable
                      ? selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded
                      : Icons.lock_outline_rounded,
                  color: selectable && selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      presentation.description,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      presentation.dosageForm.name,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      presentation.routeLabel,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (presentation.strengthText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        presentation.strengthText!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selectable
                            ? semantic.safeContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        selectable
                            ? 'Validada para cálculo'
                            : 'Cálculo indisponível',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selectable
                              ? semantic.onSafeContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailErrorState extends StatelessWidget {
  const _DetailErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: semantic.criticalContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: semantic.onCriticalContainer,
                  size: 34,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: semantic.onCriticalContainer),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
