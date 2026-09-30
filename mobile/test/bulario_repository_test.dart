import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/bulario/bulario_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'complete bundled catalogue is searchable offline without losing records',
    () async {
      final directory = await Directory.systemTemp.createTemp('bulario-test');
      final path = '${directory.path}/catalogue.sqlite';
      final compressed = <int>[
        ...await File('assets/bulario/catalogue-v1.sqlite.gz.part1')
            .readAsBytes(),
        ...await File('assets/bulario/catalogue-v1.sqlite.gz.part2')
            .readAsBytes(),
      ];
      await File(path).writeAsBytes(gzip.decode(compressed));
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final repository = BularioRepository(open: () async => db);
      try {
        final summary = await repository.summary();
        expect(summary['products'], 8831);
        expect(summary['document_records'], 85649);
        expect(
          (await db.rawQuery('SELECT count(*) n FROM products')).single['n'],
          summary['products'],
        );
        expect(
          (await db.rawQuery('SELECT count(*) n FROM documents')).single['n'],
          summary['document_records'],
        );
        final results = await repository.search('dipirona');
        expect(results, isNotEmpty);
        final history = await repository.forProcess(results.first.process);
        expect(history, isNotEmpty);
        expect(
          history.every((r) => r.process == results.first.process),
          isTrue,
        );
        expect(await repository.search('dipirona', favorites: []), isEmpty);
        final literalPercent = await repository.search('%');
        expect(
          literalPercent.every((r) => '${r.name} ${r.company}'.contains('%')),
          isTrue,
        );
        expect(normalizeBulario('ÁCIDO CLORÍDRICO'), 'acido cloridrico');
        expect((await repository.search('', documents: true)).length, 50);
        final page1 = await repository.search('');
        final page2 = await repository.search('', offset: 50);
        expect(
          page1
              .map((r) => r.id)
              .toSet()
              .intersection(page2.map((r) => r.id).toSet()),
          isEmpty,
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
