import 'package:nursing_clinical_core/features/home/data/favorite_medication_repository.dart';

final class FakeFavoriteMedicationRepository
    implements FavoriteMedicationRepository {
  FakeFavoriteMedicationRepository({List<FavoriteMedication>? initial})
    : items = List<FavoriteMedication>.from(
        initial ?? const <FavoriteMedication>[],
      );

  final List<FavoriteMedication> items;
  int loadCalls = 0;
  int toggleCalls = 0;

  @override
  Future<List<FavoriteMedication>> loadFavorites() async {
    loadCalls += 1;
    return List<FavoriteMedication>.unmodifiable(items);
  }

  @override
  Future<bool> isFavorite(String medicationId) async {
    return items.any((item) => item.id == medicationId);
  }

  @override
  Future<bool> toggleFavorite(String medicationId) async {
    toggleCalls += 1;
    final index = items.indexWhere((item) => item.id == medicationId);
    if (index >= 0) {
      items.removeAt(index);
      return false;
    }

    items.insert(
      0,
      FavoriteMedication(
        id: medicationId,
        displayName: 'Medicamento Teste',
        genericName: 'dipirona',
      ),
    );
    return true;
  }
}
