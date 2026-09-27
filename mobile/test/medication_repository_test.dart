import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nursing_clinical_core/features/medication/data/medication_models.dart';
import 'package:nursing_clinical_core/features/medication/data/medication_repository.dart';

void main() {
  group('HttpMedicationRepository', () {
    test('calls search endpoint and parses contract', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/medications/search');
        expect(request.url.queryParameters['q'], 'dipirona');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'query': 'dipirona',
            'returned': 1,
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': '11111111-1111-1111-1111-111111111111',
                'entity_type': 'medication_product',
                'display_name': 'Dipirona',
                'secondary_name': null,
                'match_type': 'exact',
                'score': 1.0,
                'is_approximate': false,
                'has_calculation_ready_presentation': true,
              },
            ],
          }),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final repository = HttpMedicationRepository(
        baseUri: Uri.parse('http://localhost:8000'),
        client: client,
      );

      final response = await repository.searchMedications('dipirona');

      expect(response.returned, 1);
      expect(
        response.items.single.entityType,
        SearchEntityType.medicationProduct,
      );
      expect(response.items.single.hasCalculationReadyPresentation, isTrue);
    });

    test('fails closed on calculation-ready presentation without concentration', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(_detailJson(calculationReady: true, concentration: null)),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final repository = HttpMedicationRepository(
        baseUri: Uri.parse('http://localhost:8000'),
        client: client,
      );

      expect(
        () => repository.getMedicationDetail(
          '11111111-1111-1111-1111-111111111111',
        ),
        throwsA(
          isA<MedicationRepositoryException>().having(
            (error) => error.kind,
            'kind',
            MedicationRepositoryErrorKind.invalidPayload,
          ),
        ),
      );
    });

    test('maps HTTP 503 to clinical data integrity failure', () async {
      final client = MockClient((request) async {
        return http.Response('{"detail":"blocked"}', 503);
      });
      final repository = HttpMedicationRepository(
        baseUri: Uri.parse('http://localhost:8000'),
        client: client,
      );

      expect(
        () => repository.getMedicationDetail(
          '11111111-1111-1111-1111-111111111111',
        ),
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

Map<String, dynamic> _detailJson({
  required bool calculationReady,
  required Map<String, dynamic>? concentration,
}) {
  return <String, dynamic>{
    'id': '11111111-1111-1111-1111-111111111111',
    'brand_name': 'Medicamento Teste',
    'generic_name': 'dipirona',
    'anvisa_registration_number': '123456789',
    'manufacturer_name': 'Fabricante Teste',
    'regulatory_status': 'VÁLIDO',
    'active_ingredients': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': '22222222-2222-2222-2222-222222222222',
        'canonical_name': 'Dipirona',
        'atc_code': null,
      },
    ],
    'presentations': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': '33333333-3333-3333-3333-333333333333',
        'external_presentation_code': null,
        'description': 'Ampola 500 mg/mL',
        'strength_text': '500 mg/mL',
        'dosage_form': <String, dynamic>{
          'id': '44444444-4444-4444-4444-444444444444',
          'code': 'INJ',
          'name': 'Solução injetável',
        },
        'routes': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': '55555555-5555-5555-5555-555555555555',
            'code': 'IV',
            'name': 'Intravenosa',
          },
        ],
        'concentration': concentration,
        'package_quantity': null,
        'package_unit': null,
        'calculation_ready': calculationReady,
        'regulatory_status': 'VÁLIDO',
      },
    ],
  };
}
