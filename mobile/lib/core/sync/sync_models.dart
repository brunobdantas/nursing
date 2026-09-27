import '../../features/medication/data/medication_models.dart';

final class SyncActiveIngredientRecord {
  const SyncActiveIngredientRecord({
    required this.id,
    required this.canonicalName,
    required this.normalizedName,
    this.atcCode,
  });

  factory SyncActiveIngredientRecord.fromJson(Map<String, dynamic> json) {
    return SyncActiveIngredientRecord(
      id: _requiredString(json['id'], 'id'),
      canonicalName: _requiredString(json['canonical_name'], 'canonical_name'),
      normalizedName: _requiredString(
        json['normalized_name'],
        'normalized_name',
      ),
      atcCode: _nullableString(json['atc_code']),
    );
  }

  final String id;
  final String canonicalName;
  final String normalizedName;
  final String? atcCode;
}

final class SyncMedicationRecord {
  const SyncMedicationRecord({
    required this.id,
    required this.genericName,
    required this.normalizedGenericName,
    required this.activeIngredientIds,
    this.brandName,
    this.normalizedBrandName,
    this.anvisaRegistrationNumber,
    this.manufacturerName,
    this.regulatoryStatus,
  });

  factory SyncMedicationRecord.fromJson(Map<String, dynamic> json) {
    final rawIngredientIds = json['active_ingredient_ids'];
    if (rawIngredientIds is! List<dynamic>) {
      throw const FormatException('active_ingredient_ids must be a list.');
    }

    return SyncMedicationRecord(
      id: _requiredString(json['id'], 'id'),
      brandName: _nullableString(json['brand_name']),
      normalizedBrandName: _nullableString(json['normalized_brand_name']),
      genericName: _requiredString(json['generic_name'], 'generic_name'),
      normalizedGenericName: _requiredString(
        json['normalized_generic_name'],
        'normalized_generic_name',
      ),
      anvisaRegistrationNumber: _nullableString(
        json['anvisa_registration_number'],
      ),
      manufacturerName: _nullableString(json['manufacturer_name']),
      regulatoryStatus: _nullableString(json['regulatory_status']),
      activeIngredientIds: rawIngredientIds
          .map((value) => _requiredString(value, 'active_ingredient_ids[]'))
          .toList(growable: false),
    );
  }

  final String id;
  final String? brandName;
  final String? normalizedBrandName;
  final String genericName;
  final String normalizedGenericName;
  final String? anvisaRegistrationNumber;
  final String? manufacturerName;
  final String? regulatoryStatus;
  final List<String> activeIngredientIds;
}

final class SyncPresentationRecord {
  const SyncPresentationRecord({
    required this.medicationProductId,
    required this.presentation,
  });

  factory SyncPresentationRecord.fromJson(Map<String, dynamic> json) {
    final medicationProductId = _requiredString(
      json['medication_product_id'],
      'medication_product_id',
    );

    final detailJson = Map<String, dynamic>.from(json)
      ..remove('medication_product_id');

    return SyncPresentationRecord(
      medicationProductId: medicationProductId,
      presentation: PresentationDetail.fromJson(detailJson),
    );
  }

  final String medicationProductId;
  final PresentationDetail presentation;
}

final class ClinicalSyncRelease {
  const ClinicalSyncRelease({
    required this.releaseSchema,
    required this.contentVersion,
    required this.generatedAt,
    required this.activeIngredients,
    required this.medications,
    required this.presentations,
  });

  factory ClinicalSyncRelease.fromJson(Map<String, dynamic> json) {
    final releaseSchema = _requiredString(
      json['release_schema'],
      'release_schema',
    );
    if (releaseSchema != 'clinical-release-v1') {
      throw FormatException(
        'Unsupported clinical release schema: $releaseSchema',
      );
    }

    final contentVersion = _requiredString(
      json['content_version'],
      'content_version',
    );
    if (!contentVersion.startsWith('clinical-release-v1-')) {
      throw const FormatException('Invalid clinical release content version.');
    }

    final generatedAtRaw = _requiredString(
      json['generated_at'],
      'generated_at',
    );
    final generatedAt = DateTime.tryParse(generatedAtRaw);
    if (generatedAt == null) {
      throw const FormatException('Invalid clinical release generated_at.');
    }

    final rawIngredients = json['active_ingredients'];
    final rawMedications = json['medications'];
    final rawPresentations = json['presentations'];
    if (rawIngredients is! List<dynamic> ||
        rawMedications is! List<dynamic> ||
        rawPresentations is! List<dynamic>) {
      throw const FormatException(
        'Clinical release collections must be lists.',
      );
    }

    final activeIngredients = rawIngredients
        .map(
          (item) => SyncActiveIngredientRecord.fromJson(
            _requiredMap(item, 'active_ingredients[]'),
          ),
        )
        .toList(growable: false);
    final medications = rawMedications
        .map(
          (item) => SyncMedicationRecord.fromJson(
            _requiredMap(item, 'medications[]'),
          ),
        )
        .toList(growable: false);
    final presentations = rawPresentations
        .map(
          (item) => SyncPresentationRecord.fromJson(
            _requiredMap(item, 'presentations[]'),
          ),
        )
        .toList(growable: false);

    final medicationIds = medications.map((item) => item.id).toSet();
    final ingredientIds = activeIngredients.map((item) => item.id).toSet();

    for (final medication in medications) {
      if (!medication.activeIngredientIds.every(ingredientIds.contains)) {
        throw const FormatException(
          'Medication references unknown active ingredient.',
        );
      }
    }

    for (final presentation in presentations) {
      if (!medicationIds.contains(presentation.medicationProductId)) {
        throw const FormatException(
          'Presentation references unknown medication.',
        );
      }
    }

    return ClinicalSyncRelease(
      releaseSchema: releaseSchema,
      contentVersion: contentVersion,
      generatedAt: generatedAt.toUtc(),
      activeIngredients: activeIngredients,
      medications: medications,
      presentations: presentations,
    );
  }

  final String releaseSchema;
  final String contentVersion;
  final DateTime generatedAt;
  final List<SyncActiveIngredientRecord> activeIngredients;
  final List<SyncMedicationRecord> medications;
  final List<SyncPresentationRecord> presentations;
}

Map<String, dynamic> _requiredMap(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw FormatException('$field must be an object.');
}

String _requiredString(Object? value, String field) {
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
