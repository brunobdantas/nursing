import '../../../core/storage/clinical_database.dart';

final class FavoriteMedication {
  const FavoriteMedication({
    required this.id,
    required this.displayName,
    required this.genericName,
  });

  final String id;
  final String displayName;
  final String genericName;
}

abstract interface class FavoriteMedicationRepository {
  Future<List<FavoriteMedication>> loadFavorites();

  Future<bool> isFavorite(String medicationId);

  Future<bool> toggleFavorite(String medicationId);
}

final class LocalFavoriteMedicationRepository
    implements FavoriteMedicationRepository {
  const LocalFavoriteMedicationRepository({
    required ClinicalDatabase database,
  }) : _database = database;

  final ClinicalDatabase _database;

  @override
  Future<List<FavoriteMedication>> loadFavorites() async {
    final rows = await _database.favoriteMedicationRows();
    return rows
        .map(
          (row) => FavoriteMedication(
            id: row['id']! as String,
            displayName:
                (row['brand_name'] as String?) ?? row['generic_name']! as String,
            genericName: row['generic_name']! as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> isFavorite(String medicationId) {
    return _database.isFavorite(medicationId);
  }

  @override
  Future<bool> toggleFavorite(String medicationId) async {
    final nextValue = !await _database.isFavorite(medicationId);
    await _database.setFavorite(medicationId, nextValue);
    return nextValue;
  }
}
