import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bulario/bulario_repository.dart';

class LeafletSection {
  const LeafletSection(this.title, this.text);
  final String title;
  final String text;
}

class NativeLeaflet {
  NativeLeaflet(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get name => data['name'] as String;
  String get manufacturer => data['manufacturer'] as String;
  String get sourceUrl => data['sourceUrl'] as String;
  String get collectedAt => (data['collectedAt'] as String).substring(0, 10);
  String get hash => data['sha256'] as String;
  List<String> get pages => (data['pages'] as List).cast<String>();
  String get intro => data['intro'] as String;
  late final String searchText = normalizeBulario('$name $intro');
  late final List<LeafletSection> sections = _sections();

  List<LeafletSection> _sections() {
    final text = pages.join('\n\n');
    final pattern = RegExp(
      r'^\s*(?:[1-9]|10)\s*[.\-–)]\s*(?:INDICA[^\n]*|RESULTADOS[^\n]*|CARACTER[^\n]*|CONTRAINDICA[^\n]*|CONTRA-INDICA[^\n]*|ADVERT[^\n]*|INTERA[^\n]*|CUIDADOS[^\n]*|POSOLOGIA[^\n]*|REA[^\n]*|SUPERDO[^\n]*)',
      multiLine: true,
      caseSensitive: false,
    );
    final found = pattern.allMatches(text).where((m) => m.group(0)!.trim().length < 130).toList();
    if (found.isEmpty) return [LeafletSection('Texto da bula', text)];
    final result = <LeafletSection>[];
    if (found.first.start > 0) {
      result.add(LeafletSection('Identificação e composição', text.substring(0, found.first.start)));
    }
    for (var i = 0; i < found.length; i++) {
      result.add(LeafletSection(found[i].group(0)!.trim(), text.substring(found[i].start, i + 1 < found.length ? found[i + 1].start : text.length)));
    }
    return result;
  }
}

List<NativeLeaflet> _decode(Uint8List bytes) {
  final content = utf8.decode(gzip.decode(bytes));
  final data = jsonDecode(content) as Map<String, dynamic>;
  return (data['leaflets'] as List)
      .map((row) => NativeLeaflet(row as Map<String, dynamic>)).toList();
}

class LeafletLibrary {
  static Future<List<NativeLeaflet>>? _pending;
  static Future<List<NativeLeaflet>> load() => _pending ??= _load().catchError((Object error) {
    _pending = null;
    throw error;
  });
  static Future<List<NativeLeaflet>> _load() async => compute(
    _decode, (await rootBundle.load('assets/leaflets/professional.json.gz')).buffer.asUint8List(),
  );
}
