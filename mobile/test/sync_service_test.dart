import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nursing_clinical_core/core/storage/clinical_database.dart';
import 'package:nursing_clinical_core/core/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'API endpoint stores release and later uses clinical ETag 304',
    () async {
      final database = _database();
      addTearDown(database.close);

      var calls = 0;
      final client = MockClient((request) async {
        calls += 1;
        expect(request.url.path, '/v1/sync/content');
        expect(request.headers['accept-encoding'], 'gzip');

        if (calls == 1) {
          expect(request.headers['if-none-match'], isNull);
          return _releaseResponse();
        }

        expect(
          request.headers['if-none-match'],
          '"clinical-release-v1-testhash"',
        );
        return http.Response('', 304);
      });

      final service = SyncService(
        endpoints: <SyncEndpoint>[
          SyncEndpoint.api(
            label: 'API clínica',
            baseUri: Uri.parse('https://api.example.test'),
          ),
        ],
        database: database,
        client: client,
        retryBaseDelay: Duration.zero,
      );

      final first = await service.syncIfNeeded();
      expect(first.state, ClinicalSyncState.updated);
      expect(first.hasLocalContent, isTrue);

      final second = await service.syncIfNeeded();
      expect(second.state, ClinicalSyncState.current);
      expect(calls, 2);
    },
  );

  test(
    'falls back from failed API to public static clinical release',
    () async {
      final database = _database();
      addTearDown(database.close);

      final requestedHosts = <String>[];
      final statuses = <ClinicalSyncStatus>[];
      final client = MockClient((request) async {
        requestedHosts.add(request.url.host);
        if (request.url.host == 'api.example.test') {
          return http.Response('temporarily unavailable', 503);
        }
        return _releaseResponse();
      });

      final service = SyncService(
        endpoints: <SyncEndpoint>[
          SyncEndpoint.api(
            label: 'API clínica',
            baseUri: Uri.parse('https://api.example.test'),
          ),
          SyncEndpoint.staticRelease(
            label: 'Base clínica pública',
            uri: Uri.parse(
              'https://raw.githubusercontent.com/example/release.json',
            ),
          ),
        ],
        database: database,
        client: client,
        maxAttemptsPerEndpoint: 2,
        retryBaseDelay: Duration.zero,
      );

      final result = await service.syncIfNeeded(onStatus: statuses.add);

      expect(result.state, ClinicalSyncState.updated);
      expect(result.sourceLabel, 'Base clínica pública');
      expect(await database.hasClinicalContent(), isTrue);
      expect(requestedHosts, <String>[
        'api.example.test',
        'api.example.test',
        'raw.githubusercontent.com',
      ]);
      expect(
        statuses.map((item) => item.state),
        containsAllInOrder(<ClinicalSyncState>[
          ClinicalSyncState.checking,
          ClinicalSyncState.downloading,
          ClinicalSyncState.downloading,
          ClinicalSyncState.downloading,
          ClinicalSyncState.validating,
          ClinicalSyncState.installing,
        ]),
      );
    },
  );

  test(
    'gzipped public release is decoded before clinical validation',
    () async {
      final database = _database();
      addTearDown(database.close);

      final compressed = gzip.encode(utf8.encode(jsonEncode(_releaseJson())));
      final client = MockClient((request) async {
        return http.Response.bytes(
          compressed,
          200,
          headers: <String, String>{'content-type': 'application/gzip'},
        );
      });

      final service = SyncService(
        endpoints: <SyncEndpoint>[
          SyncEndpoint.staticRelease(
            label: 'Base clínica pública',
            uri: Uri.parse(
              'https://raw.githubusercontent.com/example/release.json.gz',
            ),
          ),
        ],
        database: database,
        client: client,
        retryBaseDelay: Duration.zero,
      );

      final result = await service.syncIfNeeded();

      expect(result.state, ClinicalSyncState.updated);
      expect(await database.hasClinicalContent(), isTrue);
    },
  );

  test('generic CDN ETag does not invalidate a valid static release', () async {
    final database = _database();
    addTearDown(database.close);

    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(_releaseJson()),
        200,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          'etag': '"github-cdn-etag-not-the-clinical-version"',
        },
      );
    });

    final service = SyncService(
      endpoints: <SyncEndpoint>[
        SyncEndpoint.staticRelease(
          label: 'Base clínica pública',
          uri: Uri.parse(
            'https://raw.githubusercontent.com/example/release.json',
          ),
        ),
      ],
      database: database,
      client: client,
      retryBaseDelay: Duration.zero,
    );

    final result = await service.syncIfNeeded();

    expect(result.state, ClinicalSyncState.updated);
    expect(await database.hasClinicalContent(), isTrue);
  });

  test('invalid remote release never destroys existing offline base', () async {
    final database = _database();
    addTearDown(database.close);

    final seedService = SyncService(
      endpoints: <SyncEndpoint>[
        SyncEndpoint.staticRelease(
          label: 'seed',
          uri: Uri.parse('https://seed.example.test/release.json'),
        ),
      ],
      database: database,
      client: MockClient((request) async => _releaseResponse()),
      retryBaseDelay: Duration.zero,
    );
    await seedService.syncIfNeeded();

    final brokenClient = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'release_schema': 'clinical-release-v1',
          'content_version': 'clinical-release-v1-broken',
          'generated_at': '2026-09-27T00:00:00Z',
          'active_ingredients': <Object?>[],
          'medications': <Object?>[],
          'presentations': <Object?>[],
        }),
        200,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    final service = SyncService(
      endpoints: <SyncEndpoint>[
        SyncEndpoint.staticRelease(
          label: 'broken',
          uri: Uri.parse('https://broken.example.test/release.json'),
        ),
      ],
      database: database,
      client: brokenClient,
      retryBaseDelay: Duration.zero,
    );
    final status = await service.syncIfNeeded();

    expect(status.state, ClinicalSyncState.offlineAvailable);
    expect(status.hasLocalContent, isTrue);
    expect(await database.getContentVersion(), 'clinical-release-v1-testhash');
    expect(await database.medicationById('med-1'), isNotNull);
  });
}

ClinicalDatabase _database() {
  return ClinicalDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

http.Response _releaseResponse() {
  return http.Response(
    jsonEncode(_releaseJson()),
    200,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'etag': '"clinical-release-v1-testhash"',
      'x-clinical-release': 'clinical-release-v1-testhash',
    },
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
