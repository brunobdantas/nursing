import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/home/data/recent_medication_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_medication_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('recent medication persists across repository instances', () async {
    final preferences = await SharedPreferences.getInstance();
    final firstRepository = SharedPreferencesRecentMedicationRepository(
      preferences: preferences,
    );
    final medication = sampleMedicationDetail();

    await firstRepository.recordMedication(medication);

    final secondRepository = SharedPreferencesRecentMedicationRepository(
      preferences: preferences,
    );
    final recent = await secondRepository.loadRecent();

    expect(recent, hasLength(1));
    expect(recent.single.id, medication.id);
    expect(recent.single.displayName, medication.displayName);
    expect(recent.single.genericName, medication.genericName);
  });

  test('recording same medication deduplicates history', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesRecentMedicationRepository(
      preferences: preferences,
    );
    final medication = sampleMedicationDetail();

    await repository.recordMedication(medication);
    await repository.recordMedication(medication);

    final recent = await repository.loadRecent();
    expect(recent, hasLength(1));
  });

  test('corrupt convenience storage fails open to an empty recent list', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      SharedPreferencesRecentMedicationRepository.storageKey,
      '{not-json',
    );
    final repository = SharedPreferencesRecentMedicationRepository(
      preferences: preferences,
    );

    final recent = await repository.loadRecent();

    expect(recent, isEmpty);
  });
}
