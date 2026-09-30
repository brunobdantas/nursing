import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/clinical_theme.dart';
import '../../bulario/bulario_repository.dart';
import '../../bulario/bulario_screen.dart';
import '../../medication/data/medication_models.dart';
import '../../medication/data/medication_repository.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.repository,
    this.bularioRepository,
    super.key,
  });

  final MedicationRepository repository;
  final BularioRepository? bularioRepository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchState { idle, loading, success, error }

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  int _requestGeneration = 0;
  _SearchState _state = _SearchState.idle;
  MedicationSearchResponse? _clinicalResponse;
  List<BularioRecord> _regulatoryRows = const <BularioRecord>[];
  String? _clinicalWarning;
  String? _regulatoryWarning;
  String? _errorMessage;

  @override
  void dispose() {
    _requestGeneration += 1;
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();

    if (query.length < 2) {
      _requestGeneration += 1;
      setState(() {
        _state = _SearchState.idle;
        _clinicalResponse = null;
        _regulatoryRows = const <BularioRecord>[];
        _clinicalWarning = null;
        _regulatoryWarning = null;
        _errorMessage = null;
      });
      return;
    }

    final generation = ++_requestGeneration;
    setState(() {
      _state = _SearchState.loading;
      _errorMessage = null;
    });

    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(query, generation),
    );
  }

  Future<void> _runSearch(String query, int generation) async {
    MedicationSearchResponse? clinical;
    List<BularioRecord> regulatory = const <BularioRecord>[];
    String? clinicalWarning;
    String? regulatoryWarning;

    try {
      clinical = await widget.repository.searchMedications(query);
    } on MedicationRepositoryException catch (error) {
      clinicalWarning = error.message;
    } catch (_) {
      clinicalWarning = 'A base clínica não respondeu à busca.';
    }

    final bulario = widget.bularioRepository;
    if (bulario != null) {
      try {
        regulatory = await bulario.search(query, limit: 10);
      } catch (_) {
        regulatoryWarning =
            'O catálogo regulatório offline não pôde ser aberto.';
      }
    }

    if (!mounted || generation != _requestGeneration) {
      return;
    }

    if (clinical == null && bulario != null && regulatoryWarning != null) {
      setState(() {
        _state = _SearchState.error;
        _errorMessage =
            'Não foi possível consultar as bases clínica e regulatória.';
      });
      return;
    }

    setState(() {
      _state = _SearchState.success;
      _clinicalResponse = clinical;
      _regulatoryRows = regulatory;
      _clinicalWarning = clinicalWarning;
      _regulatoryWarning = regulatoryWarning;
      _errorMessage = null;
    });
  }

  void _openMedication(
    MedicationSearchResult item, {
    bool startCalculation = false,
  }) {
    if (!item.isMedicationProduct) {
      return;
    }

    final suffix = startCalculation ? '?calculate=true' : '';
    context.push('/medications/${item.id}$suffix');
  }

  Future<void> _openBulario(BularioRecord item) async {
    final repository = widget.bularioRepository;
    if (repository == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BularioDetailScreen(record: item, repository: repository),
      ),
    );
  }

  void _submit(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      return;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _state = _SearchState.loading;
      _errorMessage = null;
    });
    _runSearch(query, generation);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Busca unificada'),
        actions: [
          if (widget.bularioRepository != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.offline_pin_outlined, size: 18),
                  label: const Text('offline'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: TextField(
                    key: const ValueKey<String>('medication-search-field'),
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText:
                          'Medicamento, princípio ativo, empresa ou registro',
                      helperText: widget.bularioRepository == null
                          ? 'Busca na base clínica local'
                          : 'Cruza ficha clínica e catálogo oficial Anvisa no aparelho',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              onPressed: () {
                                _controller.clear();
                                _onQueryChanged('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                    onChanged: _onQueryChanged,
                    onSubmitted: _submit,
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _buildBody(theme),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_state) {
      case _SearchState.idle:
        return _SearchEmptyState(
          key: const ValueKey<String>('search-idle'),
          theme: theme,
          hasRegulatoryCatalogue: widget.bularioRepository != null,
        );
      case _SearchState.loading:
        return const _SearchLoadingState(
          key: ValueKey<String>('search-loading'),
        );
      case _SearchState.error:
        return _SearchErrorState(
          key: const ValueKey<String>('search-error'),
          message: _errorMessage ?? 'Falha de busca.',
          onRetry: () => _submit(_controller.text),
        );
      case _SearchState.success:
        return _buildResults(theme);
    }
  }

  Widget _buildResults(ThemeData theme) {
    final clinicalItems =
        _clinicalResponse?.items ?? const <MedicationSearchResult>[];
    final hasAnything = clinicalItems.isNotEmpty || _regulatoryRows.isNotEmpty;

    if (!hasAnything &&
        _clinicalWarning == null &&
        _regulatoryWarning == null) {
      return const _NoResultsState(key: ValueKey<String>('search-no-results'));
    }

    return ListView(
      key: const ValueKey<String>('search-results'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (_clinicalWarning != null)
          _SourceWarning(
            icon: Icons.medication_outlined,
            message: 'Ficha clínica indisponível: $_clinicalWarning',
          ),
        if (_regulatoryWarning != null)
          _SourceWarning(
            icon: Icons.account_balance_outlined,
            message: _regulatoryWarning!,
          ),
        if (clinicalItems.isNotEmpty) ...[
          _ResultSectionHeader(
            icon: Icons.medical_information_outlined,
            title: 'Ficha clínica',
            subtitle: '${clinicalItems.length} resultado(s) na base Nursing',
          ),
          const SizedBox(height: 10),
          for (final item in clinicalItems) ...[
            _SearchResultCard(
              item: item,
              onOpen: item.isMedicationProduct
                  ? () => _openMedication(item)
                  : null,
              onCalculate:
                  item.isMedicationProduct &&
                      item.hasCalculationReadyPresentation
                  ? () => _openMedication(item, startCalculation: true)
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (_regulatoryRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ResultSectionHeader(
            icon: Icons.account_balance_outlined,
            title: 'Registro oficial Anvisa',
            subtitle:
                '${_regulatoryRows.length} resultado(s) no catálogo regulatório offline',
          ),
          const SizedBox(height: 10),
          for (final item in _regulatoryRows) ...[
            _RegulatoryResultCard(item: item, onOpen: () => _openBulario(item)),
            const SizedBox(height: 10),
          ],
        ],
        if (!hasAnything)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: _NoResultsState(),
          ),
      ],
    );
  }
}

class _ResultSectionHeader extends StatelessWidget {
  const _ResultSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RegulatoryResultCard extends StatelessWidget {
  const _RegulatoryResultCard({required this.item, required this.onOpen});

  final BularioRecord item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registration = item.registration.trim();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Icon(
                  Icons.verified_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.company.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.company,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Chip(
                          avatar: const Icon(
                            Icons.account_balance_outlined,
                            size: 16,
                          ),
                          label: const Text('Anvisa'),
                          visualDensity: VisualDensity.compact,
                        ),
                        if (registration.isNotEmpty)
                          Chip(
                            label: Text('Registro $registration'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.item,
    required this.onOpen,
    required this.onCalculate,
  });

  final MedicationSearchResult item;
  final VoidCallback? onOpen;
  final VoidCallback? onCalculate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.isApproximate) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: semantic.warningContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: semantic.onWarningContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Resultado Aproximado / Nomes Semelhantes (LASA)',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: semantic.onWarningContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.displayName,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _EntityTypeChip(item: item),
                ],
              ),
              if (item.secondaryName != null) ...[
                const SizedBox(height: 6),
                Text(
                  item.secondaryName!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (onOpen != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onOpen,
                        child: const Text('Ver ficha'),
                      ),
                    ),
                  if (onOpen != null && onCalculate != null)
                    const SizedBox(width: 10),
                  if (onCalculate != null)
                    Expanded(
                      child: FilledButton.icon(
                        key: ValueKey<String>('calculate-${item.id}'),
                        onPressed: onCalculate,
                        icon: const Icon(Icons.calculate_outlined),
                        label: const Text('Calcular'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntityTypeChip extends StatelessWidget {
  const _EntityTypeChip({required this.item});

  final MedicationSearchResult item;

  @override
  Widget build(BuildContext context) {
    final label = item.isMedicationProduct ? 'Medicamento' : 'Princípio ativo';
    return Chip(visualDensity: VisualDensity.compact, label: Text(label));
  }
}

class _SourceWarning extends StatelessWidget {
  const _SourceWarning({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(message),
        subtitle: const Text(
          'Os resultados da outra fonte continuam disponíveis quando possível.',
        ),
        textColor: theme.colorScheme.onSurface,
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    required this.theme,
    required this.hasRegulatoryCatalogue,
    super.key,
  });

  final ThemeData theme;
  final bool hasRegulatoryCatalogue;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.search_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Uma busca, duas bases',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Digite ao menos 2 caracteres.'),
              const SizedBox(height: 8),
              const Text(
                'A ficha clínica mostra conteúdo preparado para uso no Nursing. '
                'Resultados aproximados são identificados explicitamente.',
              ),
              if (hasRegulatoryCatalogue) ...[
                const SizedBox(height: 8),
                const Text(
                  'Em paralelo, o app consulta o catálogo oficial Anvisa '
                  'instalado no aparelho, inclusive sem internet.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchLoadingState extends StatelessWidget {
  const _SearchLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 42,
        height: 42,
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: semantic.criticalContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Busca indisponível',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: semantic.onCriticalContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
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
      ],
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: ListTile(
        minTileHeight: 72,
        leading: Icon(Icons.search_off_rounded),
        title: Text('Nenhum resultado encontrado'),
        subtitle: Text(
          'Confira a grafia ou tente o princípio ativo, nome comercial '
          'ou número de registro.',
        ),
      ),
    );
  }
}
