import 'dart:convert';

import 'package:decimal/decimal.dart';

import '../../../core/storage/clinical_database.dart';
import 'medication_models.dart';

enum MedicationRepositoryErrorKind {
  network,
  timeout,
  badResponse,
  invalidPayload,
  notFound,
  clinicalDataIntegrity,
  localStorage,
  unknown,
}

final class MedicationRepositoryException implements Exception {
  const MedicationRepositoryException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final MedicationRepositoryErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'MedicationRepositoryException($kind): $message';
}

abstract interface class MedicationRepository {
  Future<MedicationSearchResponse> searchMedications(String query);

  Future<MedicationDetailResponse> getMedicationDetail(String id);
}

final class LocalMedicationRepository implements MedicationRepository {
  const LocalMedicationRepository({required this.database});

  final ClinicalDatabase database;

  @override
  Future<MedicationSearchResponse> searchMedications(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      return MedicationSearchResponse(
        query: trimmed,
        items: const <MedicationSearchResult>[],
        returned: 0,
      );
    }

    final normalizedQuery = _normalizeSearchTerm(trimmed);

    try {
      final ingredientRows = await database.queryIngredientFts(normalizedQuery);
      final medicationRows = await database.queryMedicationFts(normalizedQuery);

      final items = <MedicationSearchResult>[
        ...ingredientRows.map(
          (row) =>
              _ingredientSearchResult(row, normalizedQuery, approximate: false),
        ),
        ...medicationRows.map(
          (row) =>
              _medicationSearchResult(row, normalizedQuery, approximate: false),
        ),
      ];

      if (items.isEmpty) {
        final approximateIngredientRows = await database
            .queryApproximateIngredients(normalizedQuery.length);
        final approximateMedicationRows = await database
            .queryApproximateMedications(normalizedQuery.length);

        for (final row in approximateIngredientRows) {
          final candidate = row['normalized_name'] as String;
          final score = _similarity(candidate, normalizedQuery);
          if (score >= 0.64) {
            items.add(
              _ingredientSearchResult(
                row,
                normalizedQuery,
                approximate: true,
                approximateScore: score,
              ),
            );
          }
        }

        for (final row in approximateMedicationRows) {
          final generic = row['normalized_generic_name'] as String;
          final brand = row['normalized_brand_name'] as String?;
          final score = <double>[
            _similarity(generic, normalizedQuery),
            if (brand != null) _similarity(brand, normalizedQuery),
          ].reduce((first, second) => first > second ? first : second);

          if (score >= 0.64) {
            items.add(
              _medicationSearchResult(
                row,
                normalizedQuery,
                approximate: true,
                approximateScore: score,
              ),
            );
          }
        }
      }

      items.sort((a, b) {
        final approximateCompare = a.isApproximate == b.isApproximate
            ? 0
            : a.isApproximate
            ? 1
            : -1;
        if (approximateCompare != 0) {
          return approximateCompare;
        }

        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

      final limited = items.take(20).toList(growable: false);
      return MedicationSearchResponse(
        query: trimmed,
        items: limited,
        returned: limited.length,
      );
    } on MedicationRepositoryException {
      rethrow;
    } catch (_) {
      throw const MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.localStorage,
        message: 'Não foi possível consultar a base clínica local.',
      );
    }
  }

  @override
  Future<MedicationDetailResponse> getMedicationDetail(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw const MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.invalidPayload,
        message: 'Identificador de medicamento inválido.',
      );
    }

    try {
      final medication = await database.medicationById(normalizedId);
      if (medication == null) {
        throw const MedicationRepositoryException(
          kind: MedicationRepositoryErrorKind.notFound,
          message: 'Medicamento não encontrado na base clínica offline.',
        );
      }

      final ingredientRows = await database.ingredientsForMedication(
        normalizedId,
      );
      final presentationRows = await database.presentationsForMedication(
        normalizedId,
      );

      final ingredients = ingredientRows
          .map(
            (row) => ActiveIngredientSummary(
              id: _requiredString(row, 'id'),
              canonicalName: _requiredString(row, 'canonical_name'),
              atcCode: row['atc_code'] as String?,
            ),
          )
          .toList(growable: false);

      final presentations = presentationRows
          .map(_presentationFromRow)
          .toList(growable: false);

      return MedicationDetailResponse(
        id: _requiredString(medication, 'id'),
        brandName: medication['brand_name'] as String?,
        genericName: _requiredString(medication, 'generic_name'),
        anvisaRegistrationNumber:
            medication['anvisa_registration_number'] as String?,
        manufacturerName: medication['manufacturer_name'] as String?,
        regulatoryStatus: medication['regulatory_status'] as String?,
        therapeuticClass: medication['therapeutic_class'] as String?,
        productType: medication['product_type'] as String?,
        professionalLeafletUrl:
            medication['professional_leaflet_url'] as String?,
        activeIngredients: ingredients,
        presentations: presentations,
      );
    } on MedicationRepositoryException {
      rethrow;
    } on FormatException catch (error) {
      throw MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.clinicalDataIntegrity,
        message:
            'A base clínica local contém dados inconsistentes: ${error.message}',
      );
    } catch (_) {
      throw const MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.localStorage,
        message: 'Não foi possível abrir a ficha na base clínica local.',
      );
    }
  }

  MedicationSearchResult _ingredientSearchResult(
    Map<String, Object?> row,
    String normalizedQuery, {
    required bool approximate,
    double? approximateScore,
  }) {
    final normalizedName = _requiredString(row, 'normalized_name');
    final ranked = approximate
        ? (SearchMatchType.approximate, approximateScore ?? 0.5)
        : _rankMatch(normalizedName, normalizedQuery);

    return MedicationSearchResult(
      id: _requiredString(row, 'id'),
      entityType: SearchEntityType.activeIngredient,
      displayName: _requiredString(row, 'canonical_name'),
      matchType: ranked.$1,
      score: ranked.$2,
      isApproximate: approximate,
      hasCalculationReadyPresentation: false,
    );
  }

  MedicationSearchResult _medicationSearchResult(
    Map<String, Object?> row,
    String normalizedQuery, {
    required bool approximate,
    double? approximateScore,
  }) {
    final genericName = _requiredString(row, 'generic_name');
    final normalizedGeneric = _requiredString(row, 'normalized_generic_name');
    final brandName = row['brand_name'] as String?;
    final normalizedBrand = row['normalized_brand_name'] as String?;

    final ranked = approximate
        ? (SearchMatchType.approximate, approximateScore ?? 0.5)
        : <(SearchMatchType, double)>[
            _rankMatch(normalizedGeneric, normalizedQuery),
            if (normalizedBrand != null)
              _rankMatch(normalizedBrand, normalizedQuery),
          ].reduce((first, second) => first.$2 >= second.$2 ? first : second);

    final calculationFlag = row['has_calculation_ready_presentation'];
    final hasCalculationReady = calculationFlag == 1 || calculationFlag == true;

    return MedicationSearchResult(
      id: _requiredString(row, 'id'),
      entityType: SearchEntityType.medicationProduct,
      displayName: brandName ?? genericName,
      secondaryName: brandName == null ? null : genericName,
      matchType: ranked.$1,
      score: ranked.$2,
      isApproximate: approximate,
      hasCalculationReadyPresentation: hasCalculationReady,
    );
  }

  PresentationDetail _presentationFromRow(Map<String, Object?> row) {
    final calculationFlag = row['calculation_ready'];
    final calculationReady = calculationFlag == 1 || calculationFlag == true;

    final concentrationParts = <Object?>[
      row['concentration_value'],
      row['concentration_unit'],
      row['concentration_denominator_value'],
      row['concentration_denominator_unit'],
    ];
    final populatedParts = concentrationParts
        .where((value) => value != null)
        .length;

    ConcentrationData? concentration;
    if (populatedParts == concentrationParts.length) {
      final numerator = Decimal.parse(
        _requiredString(row, 'concentration_value'),
      );
      final denominator = Decimal.parse(
        _requiredString(row, 'concentration_denominator_value'),
      );
      if (numerator <= Decimal.zero || denominator <= Decimal.zero) {
        throw const FormatException(
          'Structured concentration must contain positive values.',
        );
      }
      concentration = ConcentrationData(
        numeratorValue: numerator,
        numeratorUnit: _requiredString(row, 'concentration_unit'),
        denominatorValue: denominator,
        denominatorUnit: _requiredString(row, 'concentration_denominator_unit'),
      );
    } else if (populatedParts != 0) {
      throw const FormatException(
        'Partial structured concentration is not allowed.',
      );
    }

    if (calculationReady && concentration == null) {
      throw const FormatException(
        'calculation_ready=true without complete structured concentration.',
      );
    }

    final routesRaw = row['routes_json'];
    if (routesRaw is! String) {
      throw const FormatException('routes_json must be stored as text.');
    }
    final decodedRoutes = jsonDecode(routesRaw);
    if (decodedRoutes is! List<dynamic>) {
      throw const FormatException('routes_json must decode to a list.');
    }

    final routes = decodedRoutes
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Invalid route payload.');
          }
          final map = item.map((key, value) => MapEntry(key.toString(), value));
          return RouteSummary(
            id: _requiredString(map, 'id'),
            code: _requiredString(map, 'code'),
            name: _requiredString(map, 'name'),
          );
        })
        .toList(growable: false);

    return PresentationDetail(
      id: _requiredString(row, 'id'),
      externalPresentationCode: row['external_presentation_code'] as String?,
      description: _requiredString(row, 'description'),
      strengthText: row['strength_text'] as String?,
      dosageForm: DosageFormSummary(
        id: _requiredString(row, 'dosage_form_id'),
        code: _requiredString(row, 'dosage_form_code'),
        name: _requiredString(row, 'dosage_form_name'),
      ),
      routes: routes,
      concentration: concentration,
      packageQuantity: _nullableDecimal(row['package_quantity']),
      packageUnit: row['package_unit'] as String?,
      calculationReady: calculationReady,
      regulatoryStatus: row['regulatory_status'] as String?,
    );
  }
}

(SearchMatchType, double) _rankMatch(String candidate, String normalizedQuery) {
  if (candidate == normalizedQuery) {
    return (SearchMatchType.exact, 1);
  }
  if (candidate.startsWith(normalizedQuery)) {
    return (SearchMatchType.prefix, 0.9);
  }
  if (candidate.contains(normalizedQuery)) {
    return (SearchMatchType.contains, 0.75);
  }
  return (SearchMatchType.approximate, 0.5);
}

String _normalizeSearchTerm(String value) {
  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };

  final lower = value.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final character = String.fromCharCode(rune);
    buffer.write(replacements[character] ?? character);
  }
  return buffer.toString().split(RegExp(r'\s+')).join(' ');
}

double _similarity(String candidate, String query) {
  if (candidate == query) {
    return 1;
  }
  final longest = candidate.length > query.length
      ? candidate.length
      : query.length;
  if (longest == 0) {
    return 1;
  }
  final distance = _levenshtein(candidate, query);
  return (longest - distance) / longest;
}

int _levenshtein(String left, String right) {
  if (left == right) {
    return 0;
  }
  if (left.isEmpty) {
    return right.length;
  }
  if (right.isEmpty) {
    return left.length;
  }

  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var i = 0; i < left.length; i++) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = i + 1;
    for (var j = 0; j < right.length; j++) {
      final substitutionCost = left.codeUnitAt(i) == right.codeUnitAt(j)
          ? 0
          : 1;
      final insertion = current[j] + 1;
      final deletion = previous[j + 1] + 1;
      final substitution = previous[j] + substitutionCost;
      current[j + 1] = <int>[
        insertion,
        deletion,
        substitution,
      ].reduce((first, second) => first < second ? first : second);
    }
    previous = current;
  }
  return previous.last;
}

String _requiredString(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

Decimal? _nullableDecimal(Object? value) {
  if (value == null) {
    return null;
  }
  return Decimal.parse(value.toString());
}
