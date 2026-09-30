import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bulario_repository.dart';

class BularioScreen extends StatefulWidget {
  const BularioScreen({super.key, this.initialQuery = '', this.repository});
  final String initialQuery;
  final BularioRepository? repository;
  @override
  State<BularioScreen> createState() => _BularioScreenState();
}

class _BularioScreenState extends State<BularioScreen> {
  late final _repository = widget.repository ?? BularioRepository.instance;
  late final _search = TextEditingController(text: widget.initialQuery);
  List<BularioRecord> _rows = [];
  Map<String, dynamic>? _summary;
  List<String> _favorites = [];
  bool _documents = false,
      _onlyFavorites = false,
      _loading = true,
      _more = true;
  String? _error;
  int _generation = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) _rows = [];
    });
    try {
      final summary = await _repository.summary();
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('bulario-favorites') ?? [];
      final rows = await _repository.search(
        _search.text,
        documents: _documents,
        offset: append ? _rows.length : 0,
        favorites: _onlyFavorites && !_documents ? favorites : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _summary = summary;
        _favorites = favorites;
        _rows = [..._rows, ...rows];
        _more = rows.length == 50;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error =
            'Não foi possível abrir o catálogo instalado. Tente novamente.';
        _loading = false;
      });
    }
  }

  Future<void> _open(BularioRecord row) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BularioDetailScreen(
          record: row,
          documents: _documents,
          repository: _repository,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bulário Anvisa')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_summary != null)
                Text(
                  '${_summary!['products']} produtos • ${_summary!['document_records']} registros • offline',
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  _load();
                },
                onChanged: (_) {
                  _generation++;
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => _load(),
                  );
                },
                decoration: InputDecoration(
                  labelText: _documents
                      ? 'Processo ou documento'
                      : 'Medicamento, empresa ou registro',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: () => _load(),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Produtos'),
                    selected: !_documents,
                    onSelected: (_) {
                      setState(() {
                        _documents = false;
                      });
                      _load();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Documentos'),
                    selected: _documents,
                    onSelected: (_) {
                      setState(() {
                        _documents = true;
                      });
                      _load();
                    },
                  ),
                  if (!_documents)
                    FilterChip(
                      label: const Text('Favoritos'),
                      selected: _onlyFavorites,
                      onSelected: (v) {
                        setState(() {
                          _onlyFavorites = v;
                        });
                        _load();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(_error!),
                TextButton(
                  onPressed: () => _load(),
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        if (!_loading && _error == null && _rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum resultado encontrado.'),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _rows.length + (_more && _rows.isNotEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _rows.length) {
                return TextButton(
                  onPressed: _loading ? null : () => _load(append: true),
                  child: const Text('Carregar mais'),
                );
              }
              final row = _rows[index];
              return ListTile(
                title: Text(row.name),
                subtitle: Text(
                  _documents
                      ? 'Processo ${row.process}\n${row.data['document_status']}'
                      : '${row.company}\nRegistro ${row.registration.isEmpty ? 'não informado' : row.registration}',
                ),
                isThreeLine: true,
                trailing: Icon(
                  !_documents && _favorites.contains(row.id)
                      ? Icons.star
                      : Icons.chevron_right,
                ),
                onTap: () => _open(row),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class BularioDetailScreen extends StatefulWidget {
  const BularioDetailScreen({
    super.key,
    required this.record,
    required this.repository,
    this.documents = false,
  });
  final BularioRecord record;
  final BularioRepository repository;
  final bool documents;
  @override
  State<BularioDetailScreen> createState() => _BularioDetailScreenState();
}

class _BularioDetailScreenState extends State<BularioDetailScreen> {
  late final Future<List<BularioRecord>> _history = widget.repository
      .forProcess(widget.record.process);
  final _notes = TextEditingController();
  bool _favorite = false, _preferencesReady = false;
  String get _noteKey =>
      'bulario-note-${widget.documents ? 'document' : 'product'}-${widget.record.id}';
  @override
  void initState() {
    super.initState();
    _preferences();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _preferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _favorite = (prefs.getStringList('bulario-favorites') ?? []).contains(
        widget.record.id,
      );
      _notes.text = prefs.getString(_noteKey) ?? '';
      _preferencesReady = true;
    });
  }

  Future<void> _toggle() async {
    final prefs = await SharedPreferences.getInstance();
    final values = (prefs.getStringList('bulario-favorites') ?? []).toSet();
    if (!values.add(widget.record.id)) values.remove(widget.record.id);
    await prefs.setStringList('bulario-favorites', values.toList());
    if (mounted) {
      setState(() {
        _favorite = values.contains(widget.record.id);
    }
      });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_noteKey, _notes.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nota salva neste dispositivo')),
      );
    }
  }

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SelectableText(value.isEmpty ? 'Não informado na fonte' : value),
      ],
    ),
  );
  Widget _original(BularioRecord r, bool document) {
    final labels = document
        ? <int, String>{
            0: 'Processo',
            1: 'Identificador do documento',
            4: 'Situação administrativa',
            9: 'Data de referência da exportação',
          }
        : <int, String>{
            0: 'Identificador do produto',
            1: 'Nome do produto',
            2: 'Registro Anvisa',
            4: 'Processo',
            5: 'CNPJ',
            6: 'Empresa',
            7: 'Identificador do documento associado',
            11: 'Data de referência da exportação',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < r.columns.length; i++)
          _field(
            labels[i] ?? 'Campo ${i + 1} da fonte (sem descrição confirmada)',
            r.columns[i],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(r.name),
          actions: [
            if (!widget.documents)
              IconButton(
                tooltip: _favorite ? 'Remover dos favoritos' : 'Favoritar',
                onPressed: _preferencesReady ? _toggle : null,
                icon: Icon(_favorite ? Icons.star : Icons.star_border),
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Principal'),
              Tab(text: 'Histórico'),
              Tab(text: 'Fonte'),
              Tab(text: 'Notas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(r.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 20),
                if (!widget.documents) ...[
                  _field('Registro Anvisa', r.registration),
                  _field('Empresa', r.company),
                ],
                _field('Processo', r.process),
                if (widget.documents)
                  _field(
                    'Situação administrativa',
                    r.data['document_status'].toString(),
                  ),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Cadastro oficial disponível offline. O texto integral da bula ainda não foi incorporado a esta ficha. Estes registros não contêm orientações de dose, preparo ou administração.',
                    ),
                  ),
                ),
              ],
            ),
            FutureBuilder<List<BularioRecord>>(
              future: _history,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Não foi possível carregar o histórico.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final records = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: records.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          '${records.length} registros do mesmo processo. A ordem segue a exportação; não indica vigência da bula.',
                        ),
                      );
                    }
                    final record = records[i - 1];
                    return Card(
                      child: ExpansionTile(
                        title: Text('Documento ${record.data['document_id']}'),
                        subtitle: Text(
                          record.data['document_status'].toString(),
                        ),
                        childrenPadding: const EdgeInsets.all(16),
                        children: [_original(record, true)],
                      ),
                    );
                  },
                );
              },
            ),
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _field('Fonte', 'Anvisa — Bulário, dados abertos'),
                _field(
                  'Arquivo',
                  widget.documents
                      ? 'TA_CONSULTA_BULA_DOCUMENTO.CSV'
                      : 'TA_CONSULTA_BULA_PRODUTO.CSV',
                ),
                _original(r, widget.documents),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Anotações pessoais. Não alteram o conteúdo oficial.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notes,
                  enabled: _preferencesReady,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Minha nota',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _preferencesReady ? _save : null,
                  child: const Text('Salvar nota'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
