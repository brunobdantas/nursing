import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bulario/bulario_repository.dart';
import 'leaflet_library.dart';

class LeafletLibraryScreen extends StatefulWidget {
  const LeafletLibraryScreen({super.key, this.initialQuery = ''});
  final String initialQuery;
  @override
  State<LeafletLibraryScreen> createState() => _LeafletLibraryScreenState();
}

class _LeafletLibraryScreenState extends State<LeafletLibraryScreen> {
  late final _search = TextEditingController(text: widget.initialQuery);
  late Future<List<NativeLeaflet>> _data = LeafletLibrary.load();
  Set<String> _favorites = {};
  List<String> _recent = [];
  String _filter = 'Todas';

  @override
  void initState() { super.initState(); _preferences(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  Future<void> _preferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _favorites = (prefs.getStringList('native-leaflet-favorites') ?? []).toSet();
      _recent = prefs.getStringList('native-leaflet-recent') ?? [];
    });
  }
  Future<void> _open(NativeLeaflet leaflet) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = [leaflet.id, ..._recent.where((id) => id != leaflet.id)].take(30).toList();
    await prefs.setStringList('native-leaflet-recent', recent);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LeafletDetailScreen(leaflet: leaflet)));
    await _preferences();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bulas profissionais')),
    body: FutureBuilder<List<NativeLeaflet>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: FilledButton(onPressed: () => setState(() => _data = LeafletLibrary.load()), child: const Text('Tentar abrir novamente')));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final all = snapshot.data!;
        final terms = normalizeBulario(_search.text).split(' ').where((s) => s.isNotEmpty);
        final rows = all.where((r) => terms.every(r.searchText.contains)
          && (_filter != 'Favoritas' || _favorites.contains(r.id))
          && (_filter != 'Recentes' || _recent.contains(r.id))).toList();
        if (_filter == 'Recentes') rows.sort((a,b) => _recent.indexOf(a.id).compareTo(_recent.indexOf(b.id)));
        return Column(children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.offline_pin_outlined), SizedBox(width: 8), Text('PRONTAS PARA CONSULTAR')]),
              const SizedBox(height: 8),
              Text('${all.length} bulas em português', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              const Text('Textos do fabricante Cristália • acesso offline\nColeção parcial. Não abrange todo o Bulário Anvisa.'),
            ]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
            key: const ValueKey('leaflet-search'), controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: 'Nome, princípio ativo ou apresentação', prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Limpar busca', onPressed: () => setState(_search.clear), icon: const Icon(Icons.close)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
          )),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [
            for (final label in ['Todas','Favoritas','Recentes']) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(label), selected: _filter == label, onSelected: (_) => setState(() => _filter = label))),
          ])),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nenhuma bula nesta seleção. Tente outro nome ou apresentação.')),
          Expanded(child: ListView.separated(
            itemCount: rows.length, separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final row = rows[i];
              return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.secondaryContainer, child: const Icon(Icons.description_outlined)),
                title: Text(row.name), subtitle: Text('${row.manufacturer} • ${row.pages.length} páginas de origem • texto offline'),
                trailing: Icon(_favorites.contains(row.id) ? Icons.star_rounded : Icons.chevron_right),
                onTap: () => _open(row));
            },
          )),
        ]);
      },
    ),
  );
}

class LeafletDetailScreen extends StatefulWidget {
  const LeafletDetailScreen({super.key, required this.leaflet});
  final NativeLeaflet leaflet;
  @override
  State<LeafletDetailScreen> createState() => _LeafletDetailScreenState();
}
class _LeafletDetailScreenState extends State<LeafletDetailScreen> {
  bool _favorite = false;
  final _notes = TextEditingController();
  bool _ready = false;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _notes.dispose(); super.dispose(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _favorite = (prefs.getStringList('native-leaflet-favorites') ?? []).contains(widget.leaflet.id);
      _notes.text = prefs.getString('native-leaflet-note-${widget.leaflet.id}') ?? '';
      _ready = true;
    });
  }
  Future<void> _toggle() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList('native-leaflet-favorites') ?? []).toSet();
    if (!ids.add(widget.leaflet.id)) ids.remove(widget.leaflet.id);
    await prefs.setStringList('native-leaflet-favorites', ids.toList());
    if (mounted) setState(() => _favorite = ids.contains(widget.leaflet.id));
  }
  void _read(String title, String text) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LeafletReaderScreen(title: title, text: text, product: widget.leaflet.name)));
  @override
  Widget build(BuildContext context) {
    final leaflet = widget.leaflet;
    return DefaultTabController(length: 3, child: Scaffold(
      appBar: AppBar(title: const Text('Bula profissional'), actions: [IconButton(tooltip: _favorite ? 'Remover favorita' : 'Favoritar bula', onPressed: _ready ? _toggle : null, icon: Icon(_favorite ? Icons.star_rounded : Icons.star_outline_rounded))],
        bottom: const TabBar(tabs: [Tab(text: 'Conteúdo'),Tab(text: 'Fonte'),Tab(text: 'Notas')])),
      body: TabBarView(children: [
        ListView(padding: const EdgeInsets.all(20), children: [
          Text(leaflet.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8), Text('${leaflet.manufacturer} • português • offline'),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: () => _read('Texto completo', leaflet.pages.join('\n\n')), icon: const Icon(Icons.article_outlined), label: const Text('Ler texto completo')),
          const SizedBox(height: 22), Text('Ir direto ao assunto', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          for (final section in leaflet.sections) Card(child: ListTile(title: Text(section.title), trailing: const Icon(Icons.chevron_right), onTap: () => _read(section.title, section.text))),
        ]),
        ListView(padding: const EdgeInsets.all(20), children: [
          Text('Documento do fabricante', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16),
          SelectableText('${leaflet.name}\n\nFabricante: ${leaflet.manufacturer}\n\nColetado em: ${leaflet.collectedAt}\n\nOrigem: ${leaflet.sourceUrl}'),
          const SizedBox(height: 20),
          const Text('O texto foi extraído do documento publicado pelo fabricante, sem resumo ou geração de orientações. A data de coleta não é a data de revisão da bula. Consulte a identificação, as apresentações e o histórico no texto completo.'),
          const SizedBox(height: 16),
          const Text('As tabelas mantêm o espaçamento da origem e podem ser deslizadas horizontalmente. Figuras do documento não integram esta versão de texto.'),
          const SizedBox(height: 16), SelectableText('Identificador da versão (SHA-256)\n${leaflet.hash}'),
        ]),
        ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Anotações pessoais, salvas apenas neste dispositivo.'), const SizedBox(height: 16),
          TextField(controller: _notes, enabled: _ready, maxLines: 12, decoration: const InputDecoration(labelText: 'Minha nota', border: OutlineInputBorder())),
          const SizedBox(height: 16), FilledButton(onPressed: !_ready ? null : () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('native-leaflet-note-${leaflet.id}', _notes.text);
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nota salva')));
          }, child: const Text('Salvar nota')),
        ]),
      ]),
    ));
  }
}

class LeafletReaderScreen extends StatefulWidget {
  const LeafletReaderScreen({super.key, required this.title, required this.text, required this.product});
  final String title, text, product;
  @override
  State<LeafletReaderScreen> createState() => _LeafletReaderScreenState();
}
class _LeafletReaderScreenState extends State<LeafletReaderScreen> {
  double _fontSize = 17;
  String _query = '';
  late final _blocks = widget.text.split(RegExp(r'\n\s*\n')).where((s) => s.trim().isNotEmpty).toList();
  @override
  Widget build(BuildContext context) {
    final blocks = _blocks.where((b) => normalizeBulario(b).contains(normalizeBulario(_query))).toList();
    return Scaffold(appBar: AppBar(title: Text(widget.title), actions: [
      IconButton(tooltip: 'Diminuir texto', onPressed: _fontSize <= 14 ? null : () => setState(() => _fontSize--), icon: const Icon(Icons.text_decrease)),
      IconButton(tooltip: 'Aumentar texto', onPressed: _fontSize >= 24 ? null : () => setState(() => _fontSize++), icon: const Icon(Icons.text_increase)),
    ]), body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.product, style: Theme.of(context).textTheme.labelLarge), const SizedBox(height: 12),
        TextField(onChanged: (value) => setState(() => _query = value), decoration: const InputDecoration(hintText: 'Localizar no texto', prefixIcon: Icon(Icons.search), border: OutlineInputBorder())),
        if (_query.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${blocks.length} trechos encontrados • limpe a busca para ler tudo')),
      ])),
      Expanded(child: SelectionArea(child: ListView.builder(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), itemCount: blocks.length, itemBuilder: (context, i) {
        final raw = blocks[i];
        final lines = raw.split('\n').map((s) => s.trim()).toList();
        final table = lines.where((s) => RegExp(r'\S\s{3,}\S').hasMatch(s)).length >= 2;
        final style = TextStyle(fontSize: _fontSize, height: 1.6, fontFamily: table ? 'monospace' : null);
        return Padding(padding: const EdgeInsets.only(bottom: 20), child: table
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text(raw, style: style))
          : Text(lines.join('\n'), style: style));
      }))),
    ]));
  }
}
