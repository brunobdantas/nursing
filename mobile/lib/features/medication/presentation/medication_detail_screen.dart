import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/calculation/calculation_core.dart';
import '../../../theme/clinical_theme.dart';
import '../../home/data/favorite_medication_repository.dart';
import '../../home/data/recent_medication_repository.dart';
import '../data/medication_models.dart';
import '../data/medication_repository.dart';
import 'professional_leaflet_screen.dart';

class MedicationDetailScreen extends StatefulWidget {
  const MedicationDetailScreen({
    required this.medicationId,
    required this.repository,
    required this.recentRepository,
    required this.favoriteRepository,
    this.startCalculationFlow = false,
    super.key,
  });

  final String medicationId;
  final MedicationRepository repository;
  final RecentMedicationRepository recentRepository;
  final FavoriteMedicationRepository favoriteRepository;
  final bool startCalculationFlow;

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  MedicationDetailResponse? _medication;
  String? _selectedPresentationId;
  String? _errorMessage;
  bool _loading = true;
  bool _isFavorite = false;
  bool _favoriteBusy = false;

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
      var isFavorite = false;
      try {
        isFavorite = await widget.favoriteRepository.isFavorite(medication.id);
      } catch (_) {
        // Favorites are convenience-only and never block clinical content.
      }

      if (!mounted) {
        return;
      }

      final ready = medication.calculationReadyPresentations;
      setState(() {
        _medication = medication;
        _selectedPresentationId = ready.length == 1 ? ready.single.id : null;
        _isFavorite = isFavorite;
        _loading = false;
      });
      unawaited(_recordRecent(medication));
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

  Future<void> _recordRecent(MedicationDetailResponse medication) async {
    try {
      await widget.recentRepository.recordMedication(medication);
    } catch (_) {
      // Recent history is convenience-only and must never block clinical content.
    }
  }

  Future<void> _toggleFavorite() async {
    final medication = _medication;
    if (medication == null || _favoriteBusy) {
      return;
    }

    setState(() {
      _favoriteBusy = true;
    });

    try {
      final nextValue = await widget.favoriteRepository.toggleFavorite(
        medication.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isFavorite = nextValue;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível atualizar o favorito.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusy = false;
        });
      }
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
      appBar: AppBar(
        title: const Text('Ficha do medicamento'),
        actions: [
          if (medication != null)
            IconButton(
              key: const ValueKey<String>('favorite-toggle-button'),
              tooltip: _isFavorite
                  ? 'Remover dos favoritos'
                  : 'Adicionar aos favoritos',
              onPressed: _favoriteBusy ? null : _toggleFavorite,
              icon: Icon(
                _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              ),
            ),
        ],
      ),
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
            if (medication.professionalLeaflets.isNotEmpty) ...[
              _StructuredLeafletSection(
                leaflets: medication.professionalLeaflets,
              ),
              const SizedBox(height: 24),
            ],
            _OfficialLeafletSection(medication: medication),
            const SizedBox(height: 24),
            Text(
              'Preparo & Administração',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (medication.administrationGuidance.isEmpty)
              const _ClinicalContentUnavailableCard(
                message:
                    'Não há orientação de preparo e administração publicada '
                    'para este medicamento na base clínica atual.',
              )
            else
              ...medication.administrationGuidance.map(
                (guidance) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AdministrationGuidanceCard(
                    medicationName: medication.displayName,
                    guidance: guidance,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Incompatibilidades',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (medication.incompatibilities.isEmpty)
              const _ClinicalContentUnavailableCard(
                message:
                    'Nenhuma incompatibilidade estruturada foi publicada para '
                    'este medicamento nesta versão. Ausência de dados não deve '
                    'ser interpretada como compatibilidade.',
              )
            else
              ...medication.incompatibilities.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _IncompatibilityCard(item: item),
                ),
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
        if (medication.therapeuticClass != null)
          _MetadataLine(
            label: 'Classe terapêutica',
            value: medication.therapeuticClass!,
          ),
        if (medication.productType != null)
          _MetadataLine(
            label: 'Tipo de produto',
            value: medication.productType!,
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

class _StructuredLeafletSection extends StatelessWidget {
  const _StructuredLeafletSection({required this.leaflets});

  final List<ProfessionalLeafletDetail> leaflets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bula estruturada offline', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'As seções abaixo são lidas diretamente do SQLite local. '
          'Nenhuma chamada de rede é feita ao abrir a ficha.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        for (final leaflet in leaflets) ...[
          Container(
            key: ValueKey<String>('structured-leaflet-${leaflet.id}'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: semantic.informationContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.offline_pin_outlined,
                  color: semantic.onInformationContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${leaflet.sourceName} • ${leaflet.sourceLanguage} • '
                    'versão ${leaflet.sourceVersion}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: semantic.onInformationContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (leaflet.relationType == 'active_ingredient_reference') ...[
            const SizedBox(height: 8),
            Text(
              'Referência pública vinculada pelo princípio ativo. '
              'Para diferenças específicas de fabricante/apresentação, '
              'confira também a fonte regulatória do produto.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final section in leaflet.sections)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: ValueKey<String>(
                  'leaflet-section-${leaflet.id}-${section.title}',
                ),
                maintainState: false,
                title: Text(
                  section.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      section.text,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _OfficialLeafletSection extends StatelessWidget {
  const _OfficialLeafletSection({required this.medication});

  final MedicationDetailResponse medication;

  void _openLeaflet(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfessionalLeafletScreen(medication: medication),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;
    final registration = medication.anvisaRegistrationNumber?.trim();
    final hasLeaflet = registration != null && registration.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bula e fontes oficiais', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: semantic.informationContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_outlined,
                    color: semantic.onInformationContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cadastro regulatório: Anvisa • apresentações: CMED',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: semantic.onInformationContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                hasLeaflet
                    ? 'Consulte o cadastro Anvisa e as referências em texto '
                          'diretamente no aplicativo. O catálogo Anvisa ainda '
                          'não inclui o texto integral da bula.'
                    : 'Este registro não possui número Anvisa suficiente para '
                          'localizar automaticamente a bula profissional.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: semantic.onInformationContainer,
                ),
              ),
              if (hasLeaflet) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey<String>('open-professional-leaflet'),
                  onPressed: () => _openLeaflet(context),
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('LER REFERÊNCIAS NO APLICATIVO'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AdministrationGuidanceCard extends StatelessWidget {
  const _AdministrationGuidanceCard({
    required this.medicationName,
    required this.guidance,
  });

  final String medicationName;
  final AdministrationGuidanceDetail guidance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPrefill =
        guidance.calculatorFormulaId == medInfusionMlHFormulaId &&
        guidance.calculatorVolumeMl != null;

    final volumeLabel = guidance.diluentVolumeValue == null
        ? null
        : '${guidance.diluentVolumeValue} '
              '${guidance.diluentVolumeUnit ?? 'mL'}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vaccines_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    guidance.administrationMethod ?? 'Administração',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (guidance.diluentName != null) ...[
              const SizedBox(height: 12),
              _GuidanceFact(label: 'Diluente', value: guidance.diluentName!),
            ],
            if (volumeLabel != null) ...[
              const SizedBox(height: 8),
              _GuidanceFact(label: 'Volume', value: volumeLabel),
            ],
            const SizedBox(height: 8),
            _GuidanceFact(label: 'Tempo', value: guidance.infusionTimeLabel),
            const SizedBox(height: 12),
            Text(guidance.instructionText, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (guidance.sourceName != null)
                  Chip(
                    avatar: const Icon(Icons.source_outlined, size: 18),
                    label: Text(guidance.sourceName!),
                  ),
                if (guidance.clinicalVersion != null)
                  Chip(
                    avatar: const Icon(Icons.verified_outlined, size: 18),
                    label: Text(guidance.clinicalVersion!),
                  ),
              ],
            ),
            if (canPrefill) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: ValueKey<String>('prefill-infusion-${guidance.id}'),
                onPressed: () {
                  final uri = Uri(
                    path: '/calculators/infusion',
                    queryParameters: <String, String>{
                      'volumeMl': guidance.calculatorVolumeMl.toString(),
                      if (guidance.calculatorDurationMinutes != null)
                        'durationMinutes': guidance.calculatorDurationMinutes
                            .toString(),
                      'context':
                          '$medicationName • preparo referenciado '
                          '(${guidance.sourceName ?? 'fonte clínica'})',
                    },
                  );
                  context.push(uri.toString());
                },
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('ABRIR INFUSÃO PRÉ-PREENCHIDA'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuidanceFact extends StatelessWidget {
  const _GuidanceFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}

class _IncompatibilityCard extends StatelessWidget {
  const _IncompatibilityCard({required this.item});

  final MedicationIncompatibility item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: semantic.criticalContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: semantic.critical, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.block_rounded,
            color: semantic.onCriticalContainer,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NÃO COMPATÍVEL EM Y',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: semantic.onCriticalContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.incompatibleIngredientName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: semantic.onCriticalContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.description,
                  style: TextStyle(
                    color: semantic.onCriticalContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.sourceName != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Fonte: ${item.sourceName}',
                    style: TextStyle(
                      color: semantic.onCriticalContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClinicalContentUnavailableCard extends StatelessWidget {
  const _ClinicalContentUnavailableCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<ClinicalSemanticColors>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: semantic.informationContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: semantic.onInformationContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: semantic.onInformationContainer),
            ),
          ),
        ],
      ),
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
