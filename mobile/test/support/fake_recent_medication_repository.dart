import 'package:nursing_clinical_core/features/home/data/recent_medication_repository.dart';
import 'package:nursing_clinical_core/features/medication/data/medication_models.dart';

final class FakeRecentMedicationRepository
    implements RecentMedicationRepository {
  FakeRecentMedicationRepository({
    List<RecentMedication>? initial,
    this.loadError,
    this.recordError,
  }) : items = List<RecentMedication>.from(
         initial ?? const <RecentMedication>[],
       );

  final List<RecentMedication> items;
  Object? loadError;
  Object? recordError;
  int loadCalls = 0;
  int recordCalls = 0;

  @override
  Future<List<RecentMedication>> loadRecent() async {
    loadCalls += 1;
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return List<RecentMedication>.unmodifiable(items);
  }

  @override
  Future<void> recordMedication(MedicationDetailResponse medication) async {
    recordCalls += 1;
    final error = recordError;
    if (error != null) {
      throw error;
    }

    items.removeWhere((item) => item.id == medication.id);
    items.insert(
      0,
      RecentMedication(
        id: medication.id,
        displayName: medication.displayName,
        genericName: medication.genericName,
        viewedAt: DateTime.utc(2026, 9, 27, 3),
      ),
    );
  }
}
