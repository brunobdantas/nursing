import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

List<int> _inflate(Uint8List bytes) => gzip.decode(bytes);

String normalizeBulario(String input) {
  const accents = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const plain = 'aaaaaeeeeiiiiooooouuuuc';
  return input.toLowerCase().split('').map((c) {
    final i = accents.indexOf(c);
    return i < 0 ? c : plain[i];
  }).join();
}

class BularioRecord {
  const BularioRecord(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
  String get name =>
      (data['product_name'] ?? 'Documento ${data['document_id']}').toString();
  String get process => data['process_number'].toString();
  String get registration => (data['registration_number'] ?? '').toString();
  String get company => (data['company_name'] ?? '').toString();
  List<String> get columns => (data['raw_columns'] as List).cast<String>();
}

class BularioRepository {
  BularioRepository({Future<Database> Function()? open}) : _override = open;
  final Future<Database> Function()? _override;
  Future<Database>? _pending;
  static final instance = BularioRepository();

  Future<Database> get database => _pending ??= _open().catchError((Object e) {
    _pending = null;
    throw e;
  });

  Future<Database> _open() async {
    if (_override != null) return _override();
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'anvisa-catalogue-v1.sqlite'));
    if (!await file.exists()) {
      final parts = await Future.wait([
        rootBundle.load('assets/bulario/catalogue-v1.sqlite.gz.part1'),
        rootBundle.load('assets/bulario/catalogue-v1.sqlite.gz.part2'),
      ]);
      final compressed = BytesBuilder(copy: false);
      for (final part in parts) {
        compressed.add(
          part.buffer.asUint8List(part.offsetInBytes, part.lengthInBytes),
        );
      }
      final bytes = await compute(_inflate, compressed.takeBytes());
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    }
    return openDatabase(file.path, readOnly: true, singleInstance: true);
  }

  Future<Map<String, dynamic>> summary() async {
    final rows = await (await database).query(
      'metadata',
      where: 'key = ?',
      whereArgs: ['summary'],
    );
    return jsonDecode(rows.single['value'] as String) as Map<String, dynamic>;
  }

  Future<List<BularioRecord>> search(
    String query, {
    int offset = 0,
    bool documents = false,
    List<String>? favorites,
  }) async {
    if (favorites != null && favorites.isEmpty) return [];
    final db = await database;
    final term = normalizeBulario(query.trim())
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final where = <String>[];
    final args = <Object?>[];
    if (term.isNotEmpty) {
      where.add(
        documents
            ? "(process LIKE ? ESCAPE '\\' OR id LIKE ? ESCAPE '\\')"
            : "search LIKE ? ESCAPE '\\'",
      );
      args.add('%$term%');
      if (documents) args.add('%$term%');
    }
    if (!documents && favorites != null) {
      where.add('id IN (${List.filled(favorites.length, '?').join(',')})');
      args.addAll(favorites);
    }
    final rows = await db.query(
      documents ? 'documents' : 'products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: documents ? 'ordinal DESC' : 'name COLLATE NOCASE, id',
      limit: 50,
      offset: offset,
    );
    return rows
        .map(
          (r) => BularioRecord(
            (documents ? r['ordinal'] : r['id']).toString(),
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<List<BularioRecord>> forProcess(String process) async {
    final rows = await (await database).query(
      'documents',
      where: 'process = ?',
      whereArgs: [process],
      orderBy: 'ordinal DESC',
    );
    return rows
        .map(
          (r) => BularioRecord(
            r['ordinal'].toString(),
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }
}
