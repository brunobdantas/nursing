import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/core/storage/clinical_database.dart';
import 'package:nursing_clinical_core/core/sync/sync_models.dart';
import 'package:nursing_clinical_core/features/medication/data/medication_models.dart';
import 'package:nursing_clinical_core/features/medication/data/medication_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('LocalMedicationRepository', () {
    test('searches medication and active ingredient only from SQLite', () async {
      final database = _newDatabase();
      addTearDown(database.close);
      await database.replaceClinicalRelease(_sampleRelease());

      final repository = LocalMedicationRepository(database: database);
      final response = await repository.searchMedications('dipirona');

      expect(response.returned, 2);
      expect(
        response.items.map((item) => item.entityType),
        containsAll(<SearchEntityType>[
          SearchEntityType.activeIngredient,
          SearchEntityType.medicationProduct,
        ]),
      );
      final medication = response.items.firstWhere(
        (item) => item.entityType == SearchEntityType.medicationProduct,
      );
      expect(medication.displayName, 'Novalgina');
      expect(medication.hasCalculationReadyPresentation, isTrue);
      expect(medication.isApproximate, isFalse);
    });

    test('marks typo fallback explicitly as approximate LASA result', () async {
      final database = _newDatabase();
      addTearDown(database.close);
      await database.replaceClinicalRelease(_sampleRelease());

      final repository = LocalMedicationRepository(database: database);
      final response = await repository.searchMedications('dipirnoa');

      expect(response.items, isNotEmpty);
      expect(response.items.every((item) => item.isApproximate), isTrue);
      expect(
        response.items.every(
          (item) => item.matchType == SearchMatchType.approximate,
        ),
        isTrue,
      );
    });

    test('opens medication details with structured concentration offline', () async {
      final database = _newDatabase();
      addTearDown(database.close);
      await database.replaceClinicalRelease(_sampleRelease());

      final repository = LocalMedicationRepository(database: database);
      final detail = await repository.getMedicationDetail(_medicationId);

      expect(detail.genericName, 'Dipirona');
      expect(detail.activeIngredients.single.canonicalName, 'Dipirona');
      expect(detail.presentations.single.calculationReady, isTrue);
      expect(
        detail.presentations.single.concentration?.numeratorValue,
        Decimal.parse('500'),
      );
      expect(
        detail.presentations.single.concentration?.denominatorUnit,
        'mL',
      );
    });

    test('fails closed if local calculator-ready row is structurally corrupt', () async {
      final database = _newDatabase();
      addTearDown(database.close);
      await database.replaceClinicalRelease(_sampleRelease());

      final sqlite = await database.database;
      await sqlite.update(
        'presentation',
        <String, Object?>{'concentration_unit': null},
        where: 'id = ?',
        whereArgs: <Object>[_presentationId],
      );

      final repository = LocalMedicationRepository(database: database);

      expect(
        () => repository.getMedicationDetail(_medicationId),
        throwsA(
          isA<MedicationRepositoryException>().having(
            (error) => error.kind,
            'kind',
            MedicationRepositoryErrorKind.clinicalDataIntegrity,
          ),
        ),
      );
    });
  });
}

const String _ingredientId = '22222222-2222-2222-2222-222222222222';
const String _medicationId = '11111111-1111-1111-1111-111111111111';
const String _presentationId = '33333333-3333-3333-3333-333333333333';

ClinicalDatabase _newDatabase() {
  return ClinicalDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

ClinicalSyncRelease _sampleRelease() {
  return ClinicalSyncRelease(
    releaseSchema: 'clinical-release-v1',
    contentVersion: 'clinical-release-v1-test',
    generatedAt: DateTime.utc(2026, 9, 27),
    activeIngredients: const <SyncActiveIngredientRecord>[
      SyncActiveIngredientRecord(
        id: _ingredientId,
        canonicalName: 'Dipirona',
        normalizedName: 'dipirona',
        atcCode: 'N02BB02',
      ),
    ],
    medications: const <SyncMedicationRecord>[
      SyncMedicationRecord(
        id: _medicationId,
        brandName: 'Novalgina',
        normalizedBrandName: 'novalgina',
        genericName: 'Dipirona',
        normalizedGenericName: 'dipirona',
        anvisaRegistrationNumber: '123456789',
        manufacturerName: 'Fabricante Exemplo',
        regulatoryStatus: 'VÁLIDO',
        activeIngredientIds: <String>[_ingredientId],
      ),
    ],
    presentations: <SyncPresentationRecord>[
      SyncPresentationRecord(
        medicationProductId: _medicationId,
        presentation: PresentationDetail(
          id: _presentationId,
          externalPresentationCode: 'ANVISA-PRES-001',
          description: '500 mg/mL - ampola 2 mL',
          strengthText: '500 mg/mL',
          dosageForm: const DosageFormSummary(
            id: '44444444-4444-4444-4444-444444444444',
            code: 'SOL_INJ',
            name: 'Solução injetável',
          ),
          routes: const <RouteSummary>[
            RouteSummary(
              id: '55555555-5555-5555-5555-555555555555',
              code: 'IV',
              name: 'Intravenosa',
            ),
          ],
          concentration: ConcentrationData(
            numeratorValue: Decimal.parse('500'),
            numeratorUnit: 'mg',
            denominatorValue: Decimal.one,
            denominatorUnit: 'mL',
          ),
          packageQuantity: Decimal.parse('2'),
          packageUnit: 'mL',
          calculationReady: true,
          regulatoryStatus: 'VÁLIDO',
        ),
      ),
    ],
  );
}
