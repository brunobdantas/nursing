import 'package:flutter/material.dart';

import '../../../core/storage/clinical_database.dart';
import '../../../core/sync/sync_service.dart';
import '../../bulario/bulario_repository.dart';

class OfflineDataStatusScreen extends StatefulWidget {
  const OfflineDataStatusScreen({
    required this.database,
    required this.syncCoordinator,
    required this.bularioRepository,
    super.key,
  });

  final ClinicalDatabase database;
  final ClinicalSyncCoordinator syncCoordinator;
  final BularioRepository bularioRepository;

  @override
  State<OfflineDataStatusScreen> createState() => _OfflineDataStatusScreenState();
}

class _OfflineDataStatusScreenState extends State<OfflineDataStatusScreen> {
  ClinicalSyncStatus? _status;
  Map<String, int>? _clinicalStats;
  Map<String, dynamic>? _bularioSummary;
  bool _loading = true;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.syncCoordinator.localStatus();
      final stats = await widget.database.contentStats();
      final summary = await widget.bularioRepository.summary();
      if (!mounted) return;
      setState(() {
        _status = status;
        _clinicalStats = stats;
        _bularioSummary = summary;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível conferir todas as bases instaladas.';
        _loading = false;
      });
    }
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    final result = await widget.syncCoordinator.syncIfNeeded(
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _status = status);
      },
    );
    if (!mounted) return;
    setState(() {
      _status = result;
      _syncing = false;
    });
    await _load();
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Ainda não registrada';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    final ready =
        status?.hasLocalContent == true &&
        _clinicalStats != null &&
        _bularioSummary != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Base offline')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ready
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    ready
                        ? Icons.offline_pin_rounded
                        : Icons.cloud_sync_outlined,
                    size: 34,
                    color: ready
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ready
                              ? 'Conteúdo principal disponível offline'
                              : 'Conferindo conteúdo instalado',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ready
                                ? theme.colorScheme.onPrimaryContainer
                                : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ready
                              ? 'Medicamentos, apresentações e o catálogo '
                                    'regulatório Anvisa podem ser consultados '
                                    'sem conexão.'
                              : 'A tela valida separadamente a base clínica '
                                    'e o catálogo regulatório.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ready
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text(_error!),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('Tentar novamente'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text('Base clínica Nursing', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            _StatsCard(
              icon: Icons.medical_information_outlined,
              title: 'Conteúdo clínico',
              rows: <(String, String)>[
                (
                  'Medicamentos',
                  '${_clinicalStats?['medications'] ?? 0}',
                ),
                (
                  'Apresentações',
                  '${_clinicalStats?['presentations'] ?? 0}',
                ),
                (
                  'Orientações de administração',
                  '${_clinicalStats?['administrationGuidance'] ?? 0}',
                ),
                (
                  'Bulas estruturadas',
                  '${_clinicalStats?['professionalLeaflets'] ?? 0}',
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Catálogo regulatório Anvisa', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            _StatsCard(
              icon: Icons.account_balance_outlined,
              title: 'Cadastro oficial incorporado ao APK',
              rows: <(String, String)>[
                (
                  'Produtos',
                  '${_bularioSummary?['products'] ?? 0}',
                ),
                (
                  'Registros documentais',
                  '${_bularioSummary?['document_records'] ?? 0}',
                ),
                (
                  'Produtos com vínculo documental exato',
                  '${_bularioSummary?['products_with_exact_document_match'] ?? 0}',
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Sincronização', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status?.displayText ?? 'Status ainda não carregado',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Fact(
                      label: 'Versão',
                      value: status?.contentVersion ?? 'Não instalada',
                    ),
                    _Fact(
                      label: 'Última sincronização',
                      value: _formatDate(status?.lastSyncAt),
                    ),
                    if (status?.isBusy ?? false) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: status?.state == ClinicalSyncState.downloading
                            ? status?.progressFraction
                            : null,
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      if (status?.downloadProgressText != null) ...[
                        const SizedBox(height: 6),
                        Text(status!.downloadProgressText!),
                      ],
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _syncing ? null : _sync,
                        icon: const Icon(Icons.sync_rounded),
                        label: Text(
                          _syncing
                              ? 'SINCRONIZANDO...'
                              : 'SINCRONIZAR BASE CLÍNICA',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              color: theme.colorScheme.surfaceContainerLow,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Transparência: o catálogo Anvisa incorporado contém os '
                  'metadados oficiais disponíveis no conjunto de dados abertos. '
                  'Quando o texto integral de uma bula não estiver instalado, '
                  'o Nursing não o inventa nem o apresenta como conteúdo oficial.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.icon,
    required this.title,
    required this.rows,
  });

  final IconData icon;
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(child: Icon(icon)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    Expanded(child: Text(row.$1)),
                    const SizedBox(width: 12),
                    Text(
                      row.$2,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 142,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
