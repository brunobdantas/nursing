import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nursing_clinical_core/core/storage/clinical_database.dart';
import 'package:nursing_clinical_core/core/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('sync stores clinical release and later uses ETag 304', () async {
    final database = _database();
    addTearDown(database.close);

    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      expect(request.url.path, '/v1/sync/content');
      expect(request.headers['accept-encoding'], 'gzip');

      if (calls == 1) {
        expect(request.headers['if-none-match'], isNull);
        return http.Response(
          jsonEncode(_releaseJson()),
          200,
          headers: <String, String>{
            'content-type': 'application/json',
            'etag': '"clinical-release-v1-testhash"',
            'x-clinical-release': 'clinical-release-v1-testhash',
          },
        );
      }

      expect(
        request.headers['if-none-match'],
        '"clinical-release-v1-testhash"',
      );
      return http.Response(
        '',
        304,
        headers: <String, String>{
          'etag': '"clinical-release-v1-testhash"',
        },
      );
    });

    final service = SyncService(
      baseUri: Uri.parse('http://localhost:8000'),
      database: database,
      client: client,
    );

    final first = await service.syncIfNeeded();
    expect(first.state, ClinicalSyncState.updated);
    expect(first.hasLocalContent, isTrue);
    expect(
      await database.getContentVersion(),
      'clinical-release-v1-testhash',
    );
    expect(await database.hasClinicalContent(), isTrue);

    final second = await service.syncIfNeeded();
    expect(second.state, ClinicalSyncState.current);
    expect(second.hasLocalContent, isTrue);
    expect(calls, 2);
  });

  test('invalid remote release never destroys an existing offline base', () async {
    final database = _database();
    addTearDown(database.close);

    final firstClient = MockClient((request) async {
      return http.Response(
        jsonEncode(_releaseJson()),
        200,
        headers: <String, String>{
          'etag': '"clinical-release-v1-testhash"',
          'x-clinical-release': 'clinical-release-v1-testhash',
        },
      );
    });
    final seedService = SyncService(
      baseUri: Uri.parse('http://localhost:8000'),
      database: database,
      client: firstClient,
    );
    await seedService.syncIfNeeded();

    final brokenClient = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'release_schema': 'clinical-release-v1',
          'content_version': 'clinical-release-v1-broken',
          'generated_at': '2026-09-27T00:00:00Z',
          'active_ingredients': <Object?>[],
          'medications': <Object?>[
            <String, Object?>{
              'id': 'med-broken',
              'brand_name': null,
              'normalized_brand_name': null,
              'generic_name': 'Quebrado',
              'normalized_generic_name': 'quebrado',
              'anvisa_registration_number': null,
              'manufacturer_name': null,
              'regulatory_status': 'VÁLIDO',
              'active_ingredient_ids': <String>['missing-ingredient'],
            },
          ],
          'presentations': <Object?>[],
        }),
        200,
      );
    });

    final service = SyncService(
      baseUri: Uri.parse('http://localhost:8000'),
      database: database,
      client: brokenClient,
    );
    final status = await service.syncIfNeeded();

    expect(status.state, ClinicalSyncState.offlineAvailable);
    expect(status.hasLocalContent, isTrue);
    expect(
      await database.getContentVersion(),
      'clinical-release-v1-testhash',
    );
    expect(await database.medicationById('med-1'), isNotNull);
  });
}

ClinicalDatabase _database() {
  return ClinicalDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

Map<String, Object?> _releaseJson() {
  return <String, Object?>{
    'release_schema': 'clinical-release-v1',
    'content_version': 'clinical-release-v1-testhash',
    'generated_at': '2026-09-27T00:00:00Z',
    'active_ingredients': <Object?>[
      <String, Object?>{
        'id': 'ingredient-1',
        'canonical_name': 'Dipirona',
        'normalized_name': 'dipirona',
        'atc_code': 'N02BB02',
      },
    ],
    'medications': <Object?>[
      <String, Object?>{
        'id': 'med-1',
        'brand_name': 'Novalgina',
        'normalized_brand_name': 'novalgina',
        'generic_name': 'Dipirona',
        'normalized_generic_name': 'dipirona',
        'anvisa_registration_number': '123',
        'manufacturer_name': 'Fabricante',
        'regulatory_status': 'VÁLIDO',
        'active_ingredient_ids': <String>['ingredient-1'],
      },
    ],
    'presentations': <Object?>[
      <String, Object?>{
        'id': 'presentation-1',
        'medication_product_id': 'med-1',
        'external_presentation_code': 'P1',
        'description': '500 mg/mL',
        'strength_text': '500 mg/mL',
        'dosage_form': <String, Object?>{
          'id': 'form-1',
          'code': 'SOL_INJ',
          'name': 'Solução injetável',
        },
        'routes': <Object?>[
          <String, Object?>{
            'id': 'route-1',
            'code': 'IV',
            'name': 'Intravenosa',
          },
        ],
        'concentration': <String, Object?>{
          'numerator_value': '500',
          'numerator_unit': 'mg',
          'denominator_value': '1',
          'denominator_unit': 'mL',
        },
        'package_quantity': '2',
        'package_unit': 'mL',
        'calculation_ready': true,
        'regulatory_status': 'VÁLIDO',
      },
    ],
  };
}
