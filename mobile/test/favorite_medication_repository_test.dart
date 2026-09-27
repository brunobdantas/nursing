import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/core/storage/clinical_database.dart';
import 'package:nursing_clinical_core/features/home/data/favorite_medication_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'favorites persist in local SQLite and return medication labels',
    () async {
      final database = ClinicalDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);

      final sqlite = await database.database;
      await sqlite.insert('medication_product', <String, Object?>{
        'id': 'med-1',
        'brand_name': 'Marca Teste',
        'normalized_brand_name': 'marca teste',
        'generic_name': 'Princípio Teste',
        'normalized_generic_name': 'principio teste',
        'anvisa_registration_number': '123',
        'manufacturer_name': 'Fabricante',
        'regulatory_status': 'VÁLIDO',
      });

      final repository = LocalFavoriteMedicationRepository(database: database);

      expect(await repository.isFavorite('med-1'), isFalse);
      expect(await repository.toggleFavorite('med-1'), isTrue);
      expect(await repository.isFavorite('med-1'), isTrue);

      final favorites = await repository.loadFavorites();
      expect(favorites, hasLength(1));
      expect(favorites.single.displayName, 'Marca Teste');
      expect(favorites.single.genericName, 'Princípio Teste');

      expect(await repository.toggleFavorite('med-1'), isFalse);
      expect(await repository.loadFavorites(), isEmpty);
    },
  );
}
