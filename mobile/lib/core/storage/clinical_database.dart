import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../sync/sync_models.dart';

final class ClinicalDatabase {
  ClinicalDatabase({DatabaseFactory? factory, this.databasePath})
    : _factory = factory ?? databaseFactory;

  static const int schemaVersion = 3;
  static const String defaultFileName = 'nursing_clinical_v1.db';
  static const String contentVersionKey = 'clinical_content_version';
  static const String lastSyncAtKey = 'clinical_last_sync_at';

  final DatabaseFactory _factory;
  final String? databasePath;
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    final path =
        databasePath ?? p.join(await getDatabasesPath(), defaultFileName);
    final opened = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
    }
    _database = null;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE active_ingredient (
        id TEXT PRIMARY KEY,
        canonical_name TEXT NOT NULL,
        normalized_name TEXT NOT NULL,
        atc_code TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX ix_local_ingredient_normalized_name '
      'ON active_ingredient(normalized_name)',
    );

    await db.execute('''
      CREATE TABLE medication_product (
        id TEXT PRIMARY KEY,
        brand_name TEXT,
        normalized_brand_name TEXT,
        generic_name TEXT NOT NULL,
        normalized_generic_name TEXT NOT NULL,
        anvisa_registration_number TEXT,
        manufacturer_name TEXT,
        regulatory_status TEXT,
        therapeutic_class TEXT,
        product_type TEXT,
        professional_leaflet_url TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX ix_local_medication_brand '
      'ON medication_product(normalized_brand_name)',
    );
    await db.execute(
      'CREATE INDEX ix_local_medication_generic '
      'ON medication_product(normalized_generic_name)',
    );

    await db.execute('''
      CREATE TABLE medication_product_ingredient (
        medication_product_id TEXT NOT NULL,
        active_ingredient_id TEXT NOT NULL,
        sequence_order INTEGER NOT NULL,
        PRIMARY KEY (medication_product_id, active_ingredient_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX ix_local_medication_ingredient_product '
      'ON medication_product_ingredient(medication_product_id, sequence_order)',
    );

    await db.execute('''
      CREATE TABLE presentation (
        id TEXT PRIMARY KEY,
        medication_product_id TEXT NOT NULL,
        external_presentation_code TEXT,
        description TEXT NOT NULL,
        strength_text TEXT,
        dosage_form_id TEXT NOT NULL,
        dosage_form_code TEXT NOT NULL,
        dosage_form_name TEXT NOT NULL,
        routes_json TEXT NOT NULL,
        concentration_value TEXT,
        concentration_unit TEXT,
        concentration_denominator_value TEXT,
        concentration_denominator_unit TEXT,
        package_quantity TEXT,
        package_unit TEXT,
        calculation_ready INTEGER NOT NULL CHECK (calculation_ready IN (0, 1)),
        regulatory_status TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX ix_local_presentation_product '
      'ON presentation(medication_product_id)',
    );
    await db.execute(
      'CREATE INDEX ix_local_presentation_calculation_ready '
      'ON presentation(calculation_ready)',
    );

    await db.execute('''
      CREATE TABLE favorite_medication (
        medication_product_id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL
      )
    ''');

    await _ensureSearchIndexes(db);
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE medication_product ADD COLUMN therapeutic_class TEXT',
      );
      await db.execute(
        'ALTER TABLE medication_product ADD COLUMN product_type TEXT',
      );
      await db.execute(
        'ALTER TABLE medication_product ADD COLUMN professional_leaflet_url TEXT',
      );
    }
    if (oldVersion < 3) {
      await _ensureSearchIndexes(db);
      await _rebuildSearchIndexes(db);
    }
  }

  Future<void> _ensureSearchIndexes(DatabaseExecutor db) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS medication_search_fts USING fts5(
          id UNINDEXED,
          brand_name,
          generic_name,
          normalized_brand_name,
          normalized_generic_name
        )
      ''');
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS ingredient_search_fts USING fts5(
          id UNINDEXED,
          canonical_name,
          normalized_name
        )
      ''');
    } catch (_) {
      // Some SQLite builds may not expose FTS5. Search methods fail over
      // to indexed LIKE queries so clinical lookup remains available.
    }
  }

  Future<void> _rebuildSearchIndexes(DatabaseExecutor db) async {
    try {
      await _ensureSearchIndexes(db);
      await db.delete('medication_search_fts');
      await db.rawInsert('''
        INSERT INTO medication_search_fts(
          id,
          brand_name,
          generic_name,
          normalized_brand_name,
          normalized_generic_name
        )
        SELECT
          id,
          COALESCE(brand_name, ''),
          generic_name,
          COALESCE(normalized_brand_name, ''),
          normalized_generic_name
        FROM medication_product
      ''');
      await db.delete('ingredient_search_fts');
      await db.rawInsert('''
        INSERT INTO ingredient_search_fts(
          id,
          canonical_name,
          normalized_name
        )
        SELECT id, canonical_name, normalized_name
        FROM active_ingredient
      ''');
    } catch (_) {
      // FTS is an optimization only. The canonical tables remain usable.
    }
  }

  Future<String?> getContentVersion() async {
    final db = await database;
    final rows = await db.query(
      'sync_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object>[contentVersionKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.single['value'] as String?;
  }

  Future<DateTime?> getLastSyncAt() async {
    final db = await database;
    final rows = await db.query(
      'sync_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object>[lastSyncAtKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final value = rows.single['value'];
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  Future<bool> hasClinicalContent() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM medication_product'),
    );
    return (count ?? 0) > 0 && await getContentVersion() != null;
  }

  Future<void> replaceClinicalRelease(ClinicalSyncRelease release) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('medication_product_ingredient');
      await txn.delete('presentation');
      await txn.delete('medication_product');
      await txn.delete('active_ingredient');

      final ingredientBatch = txn.batch();
      for (final ingredient in release.activeIngredients) {
        ingredientBatch.insert('active_ingredient', <String, Object?>{
          'id': ingredient.id,
          'canonical_name': ingredient.canonicalName,
          'normalized_name': ingredient.normalizedName,
          'atc_code': ingredient.atcCode,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      await ingredientBatch.commit(noResult: true);

      final medicationBatch = txn.batch();
      for (final medication in release.medications) {
        medicationBatch.insert('medication_product', <String, Object?>{
          'id': medication.id,
          'brand_name': medication.brandName,
          'normalized_brand_name': medication.normalizedBrandName,
          'generic_name': medication.genericName,
          'normalized_generic_name': medication.normalizedGenericName,
          'anvisa_registration_number': medication.anvisaRegistrationNumber,
          'manufacturer_name': medication.manufacturerName,
          'regulatory_status': medication.regulatoryStatus,
          'therapeutic_class': medication.therapeuticClass,
          'product_type': medication.productType,
          'professional_leaflet_url': medication.professionalLeafletUrl,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        for (
          var index = 0;
          index < medication.activeIngredientIds.length;
          index++
        ) {
          medicationBatch.insert(
            'medication_product_ingredient',
            <String, Object?>{
              'medication_product_id': medication.id,
              'active_ingredient_id': medication.activeIngredientIds[index],
              'sequence_order': index + 1,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }
      await medicationBatch.commit(noResult: true);

      final presentationBatch = txn.batch();
      for (final record in release.presentations) {
        final presentation = record.presentation;
        final concentration = presentation.concentration;
        presentationBatch.insert('presentation', <String, Object?>{
          'id': presentation.id,
          'medication_product_id': record.medicationProductId,
          'external_presentation_code': presentation.externalPresentationCode,
          'description': presentation.description,
          'strength_text': presentation.strengthText,
          'dosage_form_id': presentation.dosageForm.id,
          'dosage_form_code': presentation.dosageForm.code,
          'dosage_form_name': presentation.dosageForm.name,
          'routes_json': jsonEncode(
            presentation.routes
                .map(
                  (route) => <String, String>{
                    'id': route.id,
                    'code': route.code,
                    'name': route.name,
                  },
                )
                .toList(growable: false),
          ),
          'concentration_value': concentration?.numeratorValue.toString(),
          'concentration_unit': concentration?.numeratorUnit,
          'concentration_denominator_value': concentration?.denominatorValue
              .toString(),
          'concentration_denominator_unit': concentration?.denominatorUnit,
          'package_quantity': presentation.packageQuantity?.toString(),
          'package_unit': presentation.packageUnit,
          'calculation_ready': presentation.calculationReady ? 1 : 0,
          'regulatory_status': presentation.regulatoryStatus,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      await presentationBatch.commit(noResult: true);

      await _rebuildSearchIndexes(txn);

      final now = DateTime.now().toUtc().toIso8601String();
      await txn.insert('sync_metadata', <String, Object?>{
        'key': contentVersionKey,
        'value': release.contentVersion,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('sync_metadata', <String, Object?>{
        'key': lastSyncAtKey,
        'value': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, Object?>>> queryIngredientFts(
    String normalizedQuery, {
    int limit = 30,
  }) async {
    final db = await database;
    final match = _ftsPrefixQuery(normalizedQuery);
    if (match.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    try {
      return await db.rawQuery(
        '''
        SELECT ai.*
        FROM ingredient_search_fts f
        JOIN active_ingredient ai ON ai.id = f.id
        WHERE ingredient_search_fts MATCH ?
        ORDER BY bm25(ingredient_search_fts)
        LIMIT ?
        ''',
        <Object>[match, limit],
      );
    } catch (_) {
      return queryIngredientMatches(normalizedQuery, limit: limit);
    }
  }

  Future<List<Map<String, Object?>>> queryMedicationFts(
    String normalizedQuery, {
    int limit = 30,
  }) async {
    final db = await database;
    final match = _ftsPrefixQuery(normalizedQuery);
    if (match.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    try {
      return await db.rawQuery(
        '''
        SELECT
          m.*,
          EXISTS (
            SELECT 1
            FROM presentation p
            WHERE p.medication_product_id = m.id
              AND p.calculation_ready = 1
          ) AS has_calculation_ready_presentation
        FROM medication_search_fts f
        JOIN medication_product m ON m.id = f.id
        WHERE medication_search_fts MATCH ?
        ORDER BY bm25(medication_search_fts)
        LIMIT ?
        ''',
        <Object>[match, limit],
      );
    } catch (_) {
      return queryMedicationMatches(normalizedQuery, limit: limit);
    }
  }

  Future<List<Map<String, Object?>>> queryIngredientMatches(
    String normalizedQuery, {
    int limit = 30,
  }) async {
    final db = await database;
    return db.query(
      'active_ingredient',
      where:
          'normalized_name = ? OR normalized_name LIKE ? '
          'OR normalized_name LIKE ?',
      whereArgs: <Object>[
        normalizedQuery,
        '$normalizedQuery%',
        '%$normalizedQuery%',
      ],
      orderBy: 'normalized_name ASC',
      limit: limit,
    );
  }

  Future<List<Map<String, Object?>>> queryMedicationMatches(
    String normalizedQuery, {
    int limit = 30,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        m.*,
        EXISTS (
          SELECT 1
          FROM presentation p
          WHERE p.medication_product_id = m.id
            AND p.calculation_ready = 1
        ) AS has_calculation_ready_presentation
      FROM medication_product m
      WHERE m.normalized_generic_name = ?
         OR m.normalized_brand_name = ?
         OR m.normalized_generic_name LIKE ?
         OR m.normalized_brand_name LIKE ?
         OR m.normalized_generic_name LIKE ?
         OR m.normalized_brand_name LIKE ?
      ORDER BY m.normalized_generic_name ASC
      LIMIT ?
      ''',
      <Object>[
        normalizedQuery,
        normalizedQuery,
        '$normalizedQuery%',
        '$normalizedQuery%',
        '%$normalizedQuery%',
        '%$normalizedQuery%',
        limit,
      ],
    );
  }

  Future<List<Map<String, Object?>>> queryApproximateIngredients(
    int queryLength, {
    int limit = 200,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT *
      FROM active_ingredient
      WHERE ABS(LENGTH(normalized_name) - ?) <= 3
      ORDER BY normalized_name ASC
      LIMIT ?
      ''',
      <Object>[queryLength, limit],
    );
  }

  Future<List<Map<String, Object?>>> queryApproximateMedications(
    int queryLength, {
    int limit = 200,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        m.*,
        EXISTS (
          SELECT 1
          FROM presentation p
          WHERE p.medication_product_id = m.id
            AND p.calculation_ready = 1
        ) AS has_calculation_ready_presentation
      FROM medication_product m
      WHERE ABS(LENGTH(m.normalized_generic_name) - ?) <= 3
         OR (
           m.normalized_brand_name IS NOT NULL
           AND ABS(LENGTH(m.normalized_brand_name) - ?) <= 3
         )
      ORDER BY m.normalized_generic_name ASC
      LIMIT ?
      ''',
      <Object>[queryLength, queryLength, limit],
    );
  }

  Future<Map<String, Object?>?> medicationById(String id) async {
    final db = await database;
    final rows = await db.query(
      'medication_product',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> ingredientsForMedication(String id) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT ai.*
      FROM medication_product_ingredient mpi
      JOIN active_ingredient ai ON ai.id = mpi.active_ingredient_id
      WHERE mpi.medication_product_id = ?
      ORDER BY mpi.sequence_order ASC
      ''',
      <Object>[id],
    );
  }

  Future<List<Map<String, Object?>>> presentationsForMedication(
    String id,
  ) async {
    final db = await database;
    return db.query(
      'presentation',
      where: 'medication_product_id = ?',
      whereArgs: <Object>[id],
      orderBy: 'description COLLATE NOCASE ASC',
    );
  }

  Future<bool> isFavorite(String medicationId) async {
    final db = await database;
    final rows = await db.query(
      'favorite_medication',
      columns: <String>['medication_product_id'],
      where: 'medication_product_id = ?',
      whereArgs: <Object>[medicationId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> setFavorite(String medicationId, bool favorite) async {
    final db = await database;
    if (favorite) {
      await db.insert('favorite_medication', <String, Object?>{
        'medication_product_id': medicationId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }

    await db.delete(
      'favorite_medication',
      where: 'medication_product_id = ?',
      whereArgs: <Object>[medicationId],
    );
  }

  Future<List<Map<String, Object?>>> favoriteMedicationRows() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        m.id,
        m.brand_name,
        m.generic_name,
        f.created_at
      FROM favorite_medication f
      JOIN medication_product m ON m.id = f.medication_product_id
      ORDER BY f.created_at DESC
    ''');
  }
}

String _ftsPrefixQuery(String value) {
  final terms = value
      .trim()
      .split(RegExp(r'\s+'))
      .map((term) => term.replaceAll('"', '""'))
      .where((term) => term.isNotEmpty)
      .map((term) => '"$term"*')
      .toList(growable: false);
  return terms.join(' AND ');
}
