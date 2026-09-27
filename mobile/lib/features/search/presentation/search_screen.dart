import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../medication/data/medication_models.dart';
import '../../../medication/data/medication_repository.dart';
import '../../../../theme/clinical_theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.repository,
    super.key,
  });

  final MedicationRepository repository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchState { idle, loading, success, error }

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  int _requestGeneration = 0;
  _SearchState _state = _SearchState.idle;
  MedicationSearchResponse? _response;
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
        _response = null;
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
      const Duration(milliseconds: 500),
      () => _runSearch(query, generation),
    );
  }

  Future<void> _runSearch(String query, int generation) async {
    try {
      final response = await widget.repository.searchMedications(query);
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _state = _SearchState.success;
        _response = response;
        _errorMessage = null;
      });
    } on MedicationRepositoryException catch (error) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _state = _SearchState.error;
        _response = null;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _state = _SearchState.error;
        _response = null;
        _errorMessage = 'Não foi possível concluir a busca com segurança.';
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Buscar medicamento')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: TextField(
                    key: const ValueKey<String>('medication-search-field'),
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: 'Medicamento ou princípio ativo',
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
                    onSubmitted: (value) {
                      _debounce?.cancel();
                      final query = value.trim();
                      if (query.length >= 2) {
                        final generation = ++_requestGeneration;
                        setState(() {
                          _state = _SearchState.loading;
                          _errorMessage = null;
                        });
                        _runSearch(query, generation);
                      }
                    },
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
        );
      case _SearchState.loading:
        return const _SearchLoadingState(
          key: ValueKey<String>('search-loading'),
        );
      case _SearchState.error:
        return _SearchErrorState(
          key: const ValueKey<String>('search-error'),
          message: _errorMessage ?? 'Falha de busca.',
          onRetry: () {
            final query = _controller.text.trim();
            if (query.length >= 2) {
              final generation = ++_requestGeneration;
              setState(() => _state = _SearchState.loading);
              _runSearch(query, generation);
            }
          },
        );
      case _SearchState.success:
        final response = _response;
        if (response == null || response.items.isEmpty) {
          return const _NoResultsState(
            key: ValueKey<String>('search-no-results'),
          );
        }
        return ListView.separated(
          key: const ValueKey<String>('search-results'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          itemCount: response.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = response.items[index];
            return _SearchResultCard(
              item: item,
              onOpen: item.isMedicationProduct
                  ? () => _openMedication(item)
                  : null,
              onCalculate:
                  item.isMedicationProduct &&
                      item.hasCalculationReadyPresentation
                  ? () => _openMedication(item, startCalculation: true)
                  : null,
            );
          },
        );
    }
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
                        key: ValueKey<String>(
                          'calculate-${item.id}',
                        ),
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

    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    required this.theme,
    super.key,
  });

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Semantics(
          label: 'Orientações de busca',
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Digite ao menos 2 caracteres.'),
                SizedBox(height: 12),
                Text('Busque por princípio ativo ou nome comercial.'),
                SizedBox(height: 8),
                Text(
                  'Resultados aproximados serão sempre identificados '
                  'explicitamente.',
                ),
              ],
            ),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: const [
        ListTile(
          minTileHeight: 72,
          leading: Icon(Icons.search_off_rounded),
          title: Text('Nenhum resultado encontrado'),
          subtitle: Text(
            'Confira a grafia ou tente buscar pelo princípio ativo.',
          ),
        ),
      ],
    );
  }
}
