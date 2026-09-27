import 'package:decimal/decimal.dart';
import 'package:nursing_clinical_core/features/medication/data/medication_models.dart';
import 'package:nursing_clinical_core/features/medication/data/medication_repository.dart';

final class FakeMedicationRepository implements MedicationRepository {
  FakeMedicationRepository({
    MedicationSearchResponse? searchResponse,
    MedicationDetailResponse? detailResponse,
    this.searchError,
    this.detailError,
  }) : searchResponse = searchResponse ?? sampleSearchResponse(),
       detailResponse = detailResponse ?? sampleMedicationDetail();

  MedicationSearchResponse searchResponse;
  MedicationDetailResponse detailResponse;
  Object? searchError;
  Object? detailError;
  int searchCalls = 0;
  int detailCalls = 0;
  String? lastQuery;

  @override
  Future<MedicationSearchResponse> searchMedications(String query) async {
    searchCalls += 1;
    lastQuery = query;
    final error = searchError;
    if (error != null) {
      throw error;
    }
    return searchResponse;
  }

  @override
  Future<MedicationDetailResponse> getMedicationDetail(String id) async {
    detailCalls += 1;
    final error = detailError;
    if (error != null) {
      throw error;
    }
    return detailResponse;
  }
}

MedicationSearchResponse sampleSearchResponse({
  bool approximate = true,
  bool calculationReady = true,
}) {
  return MedicationSearchResponse(
    query: 'dopa',
    returned: 1,
    items: <MedicationSearchResult>[
      MedicationSearchResult(
        id: '11111111-1111-1111-1111-111111111111',
        entityType: SearchEntityType.medicationProduct,
        displayName: 'DOPamina',
        secondaryName: 'dopamina',
        matchType: approximate
            ? SearchMatchType.approximate
            : SearchMatchType.prefix,
        score: approximate ? 0.5 : 0.9,
        isApproximate: approximate,
        hasCalculationReadyPresentation: calculationReady,
      ),
    ],
  );
}

MedicationDetailResponse sampleMedicationDetail() {
  return MedicationDetailResponse(
    id: '11111111-1111-1111-1111-111111111111',
    brandName: 'Medicamento Teste',
    genericName: 'dipirona',
    anvisaRegistrationNumber: '123456789',
    manufacturerName: 'Fabricante Teste',
    regulatoryStatus: 'VÁLIDO',
    activeIngredients: const <ActiveIngredientSummary>[
      ActiveIngredientSummary(
        id: '22222222-2222-2222-2222-222222222222',
        canonicalName: 'Dipirona',
      ),
    ],
    presentations: <PresentationDetail>[
      PresentationDetail(
        id: '33333333-3333-3333-3333-333333333333',
        description: 'Ampola 500 mg/mL',
        strengthText: '500 mg/mL',
        dosageForm: const DosageFormSummary(
          id: '44444444-4444-4444-4444-444444444444',
          code: 'INJ',
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
        calculationReady: true,
        regulatoryStatus: 'VÁLIDO',
      ),
    ],
  );
}
