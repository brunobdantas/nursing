import 'package:decimal/decimal.dart';

enum SearchEntityType {
  activeIngredient('active_ingredient'),
  medicationProduct('medication_product');

  const SearchEntityType(this.apiValue);

  final String apiValue;

  static SearchEntityType parse(Object? value) {
    return SearchEntityType.values.firstWhere(
      (item) => item.apiValue == value,
      orElse: () => throw const FormatException('Invalid search entity type.'),
    );
  }
}

enum SearchMatchType {
  exact('exact'),
  prefix('prefix'),
  contains('contains'),
  approximate('approximate');

  const SearchMatchType(this.apiValue);

  final String apiValue;

  static SearchMatchType parse(Object? value) {
    return SearchMatchType.values.firstWhere(
      (item) => item.apiValue == value,
      orElse: () => throw const FormatException('Invalid search match type.'),
    );
  }
}

final class MedicationSearchResult {
  const MedicationSearchResult({
    required this.id,
    required this.entityType,
    required this.displayName,
    required this.matchType,
    required this.score,
    required this.isApproximate,
    required this.hasCalculationReadyPresentation,
    this.secondaryName,
  });

  factory MedicationSearchResult.fromJson(Map<String, dynamic> json) {
    final score = _double(json['score'], 'score');
    if (score < 0 || score > 1) {
      throw const FormatException('Search score must be between 0 and 1.');
    }

    return MedicationSearchResult(
      id: _string(json['id'], 'id'),
      entityType: SearchEntityType.parse(json['entity_type']),
      displayName: _string(json['display_name'], 'display_name'),
      secondaryName: _nullableString(json['secondary_name']),
      matchType: SearchMatchType.parse(json['match_type']),
      score: score,
      isApproximate: _bool(json['is_approximate'], 'is_approximate'),
      hasCalculationReadyPresentation: _bool(
        json['has_calculation_ready_presentation'],
        'has_calculation_ready_presentation',
      ),
    );
  }

  final String id;
  final SearchEntityType entityType;
  final String displayName;
  final String? secondaryName;
  final SearchMatchType matchType;
  final double score;
  final bool isApproximate;
  final bool hasCalculationReadyPresentation;

  bool get isMedicationProduct =>
      entityType == SearchEntityType.medicationProduct;
}

final class MedicationSearchResponse {
  const MedicationSearchResponse({
    required this.query,
    required this.items,
    required this.returned,
  });

  factory MedicationSearchResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List<dynamic>) {
      throw const FormatException('items must be a list.');
    }

    final items = rawItems
        .map((item) => MedicationSearchResult.fromJson(_map(item, 'items[]')))
        .toList(growable: false);
    final returned = _int(json['returned'], 'returned');
    if (returned < 0 || returned != items.length) {
      throw const FormatException('Invalid returned count.');
    }

    return MedicationSearchResponse(
      query: _string(json['query'], 'query'),
      items: items,
      returned: returned,
    );
  }

  final String query;
  final List<MedicationSearchResult> items;
  final int returned;
}

final class ActiveIngredientSummary {
  const ActiveIngredientSummary({
    required this.id,
    required this.canonicalName,
    this.atcCode,
  });

  factory ActiveIngredientSummary.fromJson(Map<String, dynamic> json) {
    return ActiveIngredientSummary(
      id: _string(json['id'], 'id'),
      canonicalName: _string(json['canonical_name'], 'canonical_name'),
      atcCode: _nullableString(json['atc_code']),
    );
  }

  final String id;
  final String canonicalName;
  final String? atcCode;
}

final class DosageFormSummary {
  const DosageFormSummary({
    required this.id,
    required this.code,
    required this.name,
  });

  factory DosageFormSummary.fromJson(Map<String, dynamic> json) {
    return DosageFormSummary(
      id: _string(json['id'], 'id'),
      code: _string(json['code'], 'code'),
      name: _string(json['name'], 'name'),
    );
  }

  final String id;
  final String code;
  final String name;
}

final class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.code,
    required this.name,
  });

  factory RouteSummary.fromJson(Map<String, dynamic> json) {
    return RouteSummary(
      id: _string(json['id'], 'id'),
      code: _string(json['code'], 'code'),
      name: _string(json['name'], 'name'),
    );
  }

  final String id;
  final String code;
  final String name;
}

final class ConcentrationData {
  const ConcentrationData({
    required this.numeratorValue,
    required this.numeratorUnit,
    required this.denominatorValue,
    required this.denominatorUnit,
  });

  factory ConcentrationData.fromJson(Map<String, dynamic> json) {
    final numeratorValue = _decimal(json['numerator_value'], 'numerator_value');
    final denominatorValue = _decimal(
      json['denominator_value'],
      'denominator_value',
    );
    if (numeratorValue <= Decimal.zero || denominatorValue <= Decimal.zero) {
      throw const FormatException('Concentration values must be positive.');
    }

    return ConcentrationData(
      numeratorValue: numeratorValue,
      numeratorUnit: _string(json['numerator_unit'], 'numerator_unit'),
      denominatorValue: denominatorValue,
      denominatorUnit: _string(json['denominator_unit'], 'denominator_unit'),
    );
  }

  final Decimal numeratorValue;
  final String numeratorUnit;
  final Decimal denominatorValue;
  final String denominatorUnit;

  String get display =>
      '$numeratorValue $numeratorUnit / $denominatorValue $denominatorUnit';
}

final class PresentationDetail {
  const PresentationDetail({
    required this.id,
    required this.description,
    required this.dosageForm,
    required this.routes,
    required this.calculationReady,
    this.externalPresentationCode,
    this.strengthText,
    this.concentration,
    this.packageQuantity,
    this.packageUnit,
    this.regulatoryStatus,
  });

  factory PresentationDetail.fromJson(Map<String, dynamic> json) {
    final rawRoutes = json['routes'];
    if (rawRoutes is! List<dynamic>) {
      throw const FormatException('routes must be a list.');
    }

    final rawConcentration = json['concentration'];
    final concentration = rawConcentration == null
        ? null
        : ConcentrationData.fromJson(_map(rawConcentration, 'concentration'));
    final calculationReady = _bool(
      json['calculation_ready'],
      'calculation_ready',
    );

    if (calculationReady && concentration == null) {
      throw const FormatException(
        'calculation_ready=true requires structured concentration.',
      );
    }

    return PresentationDetail(
      id: _string(json['id'], 'id'),
      externalPresentationCode: _nullableString(
        json['external_presentation_code'],
      ),
      description: _string(json['description'], 'description'),
      strengthText: _nullableString(json['strength_text']),
      dosageForm: DosageFormSummary.fromJson(
        _map(json['dosage_form'], 'dosage_form'),
      ),
      routes: rawRoutes
          .map((item) => RouteSummary.fromJson(_map(item, 'routes[]')))
          .toList(growable: false),
      concentration: concentration,
      packageQuantity: _nullableDecimal(json['package_quantity']),
      packageUnit: _nullableString(json['package_unit']),
      calculationReady: calculationReady,
      regulatoryStatus: _nullableString(json['regulatory_status']),
    );
  }

  final String id;
  final String? externalPresentationCode;
  final String description;
  final String? strengthText;
  final DosageFormSummary dosageForm;
  final List<RouteSummary> routes;
  final ConcentrationData? concentration;
  final Decimal? packageQuantity;
  final String? packageUnit;
  final bool calculationReady;
  final String? regulatoryStatus;

  String get routeLabel {
    if (routes.isEmpty) {
      return 'Via não informada';
    }
    return routes.map((route) => route.name).join(' • ');
  }
}

final class AdministrationGuidanceDetail {
  const AdministrationGuidanceDetail({
    required this.id,
    required this.presentationId,
    required this.route,
    required this.instructionText,
    required this.reviewStatus,
    this.administrationMethod,
    this.diluentName,
    this.diluentVolumeValue,
    this.diluentVolumeUnit,
    this.resultingTotalVolumeValue,
    this.resultingTotalVolumeUnit,
    this.administrationTimeMinMinutes,
    this.administrationTimeMaxMinutes,
    this.clinicalVersion,
    this.sourceName,
    this.sourceUrl,
    this.calculatorFormulaId,
    this.calculatorVolumeMl,
    this.calculatorDurationMinutes,
  });

  final String id;
  final String presentationId;
  final RouteSummary route;
  final String? administrationMethod;
  final String? diluentName;
  final Decimal? diluentVolumeValue;
  final String? diluentVolumeUnit;
  final Decimal? resultingTotalVolumeValue;
  final String? resultingTotalVolumeUnit;
  final Decimal? administrationTimeMinMinutes;
  final Decimal? administrationTimeMaxMinutes;
  final String instructionText;
  final String reviewStatus;
  final String? clinicalVersion;
  final String? sourceName;
  final String? sourceUrl;
  final String? calculatorFormulaId;
  final Decimal? calculatorVolumeMl;
  final Decimal? calculatorDurationMinutes;

  String get infusionTimeLabel {
    final min = administrationTimeMinMinutes;
    final max = administrationTimeMaxMinutes;
    if (min == null && max == null) {
      return 'Tempo definido conforme indicação/protocolo';
    }
    if (min != null && max != null && min == max) {
      return '${_decimalDisplay(min)} min';
    }
    if (min != null && max != null) {
      return '${_decimalDisplay(min)}–${_decimalDisplay(max)} min';
    }
    return '${_decimalDisplay(min ?? max!)} min';
  }
}

final class MedicationIncompatibility {
  const MedicationIncompatibility({
    required this.id,
    required this.activeIngredientId,
    required this.incompatibleIngredientId,
    required this.incompatibleIngredientName,
    required this.interactionType,
    required this.severity,
    required this.description,
    required this.reviewStatus,
    this.clinicalVersion,
    this.sourceName,
    this.sourceUrl,
  });

  final String id;
  final String activeIngredientId;
  final String incompatibleIngredientId;
  final String incompatibleIngredientName;
  final String interactionType;
  final String severity;
  final String description;
  final String reviewStatus;
  final String? clinicalVersion;
  final String? sourceName;
  final String? sourceUrl;

  bool get isCritical => severity.toLowerCase() == 'critical';
}

final class MedicationDetailResponse {
  const MedicationDetailResponse({
    required this.id,
    required this.genericName,
    required this.activeIngredients,
    required this.presentations,
    this.administrationGuidance = const <AdministrationGuidanceDetail>[],
    this.incompatibilities = const <MedicationIncompatibility>[],
    this.brandName,
    this.anvisaRegistrationNumber,
    this.manufacturerName,
    this.regulatoryStatus,
    this.therapeuticClass,
    this.productType,
    this.professionalLeafletUrl,
  });

  factory MedicationDetailResponse.fromJson(Map<String, dynamic> json) {
    final rawIngredients = json['active_ingredients'];
    final rawPresentations = json['presentations'];
    if (rawIngredients is! List<dynamic>) {
      throw const FormatException('active_ingredients must be a list.');
    }
    if (rawPresentations is! List<dynamic>) {
      throw const FormatException('presentations must be a list.');
    }

    return MedicationDetailResponse(
      id: _string(json['id'], 'id'),
      brandName: _nullableString(json['brand_name']),
      genericName: _string(json['generic_name'], 'generic_name'),
      anvisaRegistrationNumber: _nullableString(
        json['anvisa_registration_number'],
      ),
      manufacturerName: _nullableString(json['manufacturer_name']),
      regulatoryStatus: _nullableString(json['regulatory_status']),
      therapeuticClass: _nullableString(json['therapeutic_class']),
      productType: _nullableString(json['product_type']),
      professionalLeafletUrl: _nullableString(json['professional_leaflet_url']),
      activeIngredients: rawIngredients
          .map(
            (item) => ActiveIngredientSummary.fromJson(
              _map(item, 'active_ingredients[]'),
            ),
          )
          .toList(growable: false),
      presentations: rawPresentations
          .map(
            (item) =>
                PresentationDetail.fromJson(_map(item, 'presentations[]')),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String? brandName;
  final String genericName;
  final String? anvisaRegistrationNumber;
  final String? manufacturerName;
  final String? regulatoryStatus;
  final String? therapeuticClass;
  final String? productType;
  final String? professionalLeafletUrl;
  final List<ActiveIngredientSummary> activeIngredients;
  final List<PresentationDetail> presentations;
  final List<AdministrationGuidanceDetail> administrationGuidance;
  final List<MedicationIncompatibility> incompatibilities;

  String get displayName => brandName ?? genericName;

  List<PresentationDetail> get calculationReadyPresentations => presentations
      .where(
        (presentation) =>
            presentation.calculationReady && presentation.concentration != null,
      )
      .toList(growable: false);

  PresentationDetail presentationById(String presentationId) {
    for (final presentation in presentations) {
      if (presentation.id == presentationId) {
        return presentation;
      }
    }
    throw const FormatException('Presentation was not found in medication.');
  }
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw FormatException('$field must be an object.');
}

String _string(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

String? _nullableString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('Expected string or null.');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _bool(Object? value, String field) {
  if (value is! bool) {
    throw FormatException('$field must be a boolean.');
  }
  return value;
}

int _int(Object? value, String field) {
  if (value is! num || value % 1 != 0) {
    throw FormatException('$field must be an integer.');
  }
  return value.toInt();
}

double _double(Object? value, String field) {
  if (value is! num) {
    throw FormatException('$field must be numeric.');
  }
  return value.toDouble();
}

Decimal _decimal(Object? value, String field) {
  try {
    if (value is num || value is String) {
      return Decimal.parse(value.toString());
    }
  } on FormatException {
    rethrow;
  }
  throw FormatException('$field must be decimal-compatible.');
}

Decimal? _nullableDecimal(Object? value) {
  if (value == null) {
    return null;
  }
  return _decimal(value, 'decimal');
}

String _decimalDisplay(Decimal value) {
  final text = value.toString();
  if (!text.contains('.')) {
    return text;
  }
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
