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
    this.therapeuticClass,
    this.productType,
    this.professionalLeafletUrl,
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
      therapeuticClass: _nullableString(json['therapeutic_class']),
      productType: _nullableString(json['product_type']),
      professionalLeafletUrl: _nullableString(json['professional_leaflet_url']),
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
  final String? therapeuticClass;
  final String? productType;
  final String? professionalLeafletUrl;
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

final class SyncAdministrationGuidanceRecord {
  const SyncAdministrationGuidanceRecord({
    required this.id,
    required this.medicationProductId,
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

  factory SyncAdministrationGuidanceRecord.fromJson(Map<String, dynamic> json) {
    return SyncAdministrationGuidanceRecord(
      id: _requiredString(json['id'], 'id'),
      medicationProductId: _requiredString(
        json['medication_product_id'],
        'medication_product_id',
      ),
      presentationId: _requiredString(
        json['presentation_id'],
        'presentation_id',
      ),
      route: RouteSummary.fromJson(_requiredMap(json['route'], 'route')),
      administrationMethod: _nullableString(json['administration_method']),
      diluentName: _nullableString(json['diluent_name']),
      diluentVolumeValue: _nullableScalarString(json['diluent_volume_value']),
      diluentVolumeUnit: _nullableString(json['diluent_volume_unit']),
      resultingTotalVolumeValue: _nullableScalarString(
        json['resulting_total_volume_value'],
      ),
      resultingTotalVolumeUnit: _nullableString(
        json['resulting_total_volume_unit'],
      ),
      administrationTimeMinMinutes: _nullableScalarString(
        json['administration_time_min_minutes'],
      ),
      administrationTimeMaxMinutes: _nullableScalarString(
        json['administration_time_max_minutes'],
      ),
      instructionText: _requiredString(
        json['instruction_text'],
        'instruction_text',
      ),
      reviewStatus: _requiredString(json['review_status'], 'review_status'),
      clinicalVersion: _nullableString(json['clinical_version']),
      sourceName: _nullableString(json['source_name']),
      sourceUrl: _nullableString(json['source_url']),
      calculatorFormulaId: _nullableString(json['calculator_formula_id']),
      calculatorVolumeMl: _nullableScalarString(json['calculator_volume_ml']),
      calculatorDurationMinutes: _nullableScalarString(
        json['calculator_duration_minutes'],
      ),
    );
  }

  final String id;
  final String medicationProductId;
  final String presentationId;
  final RouteSummary route;
  final String? administrationMethod;
  final String? diluentName;
  final String? diluentVolumeValue;
  final String? diluentVolumeUnit;
  final String? resultingTotalVolumeValue;
  final String? resultingTotalVolumeUnit;
  final String? administrationTimeMinMinutes;
  final String? administrationTimeMaxMinutes;
  final String instructionText;
  final String reviewStatus;
  final String? clinicalVersion;
  final String? sourceName;
  final String? sourceUrl;
  final String? calculatorFormulaId;
  final String? calculatorVolumeMl;
  final String? calculatorDurationMinutes;
}

final class SyncIncompatibilityRecord {
  const SyncIncompatibilityRecord({
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

  factory SyncIncompatibilityRecord.fromJson(Map<String, dynamic> json) {
    return SyncIncompatibilityRecord(
      id: _requiredString(json['id'], 'id'),
      activeIngredientId: _requiredString(
        json['active_ingredient_id'],
        'active_ingredient_id',
      ),
      incompatibleIngredientId: _requiredString(
        json['incompatible_ingredient_id'],
        'incompatible_ingredient_id',
      ),
      incompatibleIngredientName: _requiredString(
        json['incompatible_ingredient_name'],
        'incompatible_ingredient_name',
      ),
      interactionType: _requiredString(
        json['interaction_type'],
        'interaction_type',
      ),
      severity: _requiredString(json['severity'], 'severity'),
      description: _requiredString(json['description'], 'description'),
      reviewStatus: _requiredString(json['review_status'], 'review_status'),
      clinicalVersion: _nullableString(json['clinical_version']),
      sourceName: _nullableString(json['source_name']),
      sourceUrl: _nullableString(json['source_url']),
    );
  }

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
}

final class SyncProfessionalLeafletRecord {
  const SyncProfessionalLeafletRecord({
    required this.id,
    required this.sourceName,
    required this.sourceDocumentId,
    required this.sourceVersion,
    required this.sourceLanguage,
    required this.sourceUrl,
    required this.reviewStatus,
    this.sourceEffectiveDate,
    this.indicationsText,
    this.dosageAdministrationText,
    this.contraindicationsText,
    this.warningsPrecautionsText,
    this.adverseReactionsText,
    this.drugInteractionsText,
    this.specificPopulationsText,
    this.overdosageText,
    this.descriptionText,
    this.clinicalPharmacologyText,
    this.howSuppliedStorageText,
    this.patientCounselingText,
    this.clinicalVersion,
  });

  factory SyncProfessionalLeafletRecord.fromJson(Map<String, dynamic> json) {
    return SyncProfessionalLeafletRecord(
      id: _requiredString(json['id'], 'id'),
      sourceName: _requiredString(json['source_name'], 'source_name'),
      sourceDocumentId: _requiredString(
        json['source_document_id'],
        'source_document_id',
      ),
      sourceVersion: _requiredString(json['source_version'], 'source_version'),
      sourceLanguage: _requiredString(
        json['source_language'],
        'source_language',
      ),
      sourceUrl: _requiredString(json['source_url'], 'source_url'),
      sourceEffectiveDate: _nullableString(json['source_effective_date']),
      indicationsText: _nullableString(json['indications_text']),
      dosageAdministrationText: _nullableString(
        json['dosage_administration_text'],
      ),
      contraindicationsText: _nullableString(json['contraindications_text']),
      warningsPrecautionsText: _nullableString(
        json['warnings_precautions_text'],
      ),
      adverseReactionsText: _nullableString(json['adverse_reactions_text']),
      drugInteractionsText: _nullableString(json['drug_interactions_text']),
      specificPopulationsText: _nullableString(
        json['specific_populations_text'],
      ),
      overdosageText: _nullableString(json['overdosage_text']),
      descriptionText: _nullableString(json['description_text']),
      clinicalPharmacologyText: _nullableString(
        json['clinical_pharmacology_text'],
      ),
      howSuppliedStorageText: _nullableString(
        json['how_supplied_storage_text'],
      ),
      patientCounselingText: _nullableString(json['patient_counseling_text']),
      reviewStatus: _requiredString(json['review_status'], 'review_status'),
      clinicalVersion: _nullableString(json['clinical_version']),
    );
  }

  final String id;
  final String sourceName;
  final String sourceDocumentId;
  final String sourceVersion;
  final String sourceLanguage;
  final String sourceUrl;
  final String? sourceEffectiveDate;
  final String? indicationsText;
  final String? dosageAdministrationText;
  final String? contraindicationsText;
  final String? warningsPrecautionsText;
  final String? adverseReactionsText;
  final String? drugInteractionsText;
  final String? specificPopulationsText;
  final String? overdosageText;
  final String? descriptionText;
  final String? clinicalPharmacologyText;
  final String? howSuppliedStorageText;
  final String? patientCounselingText;
  final String reviewStatus;
  final String? clinicalVersion;
}

final class SyncMedicationLeafletLinkRecord {
  const SyncMedicationLeafletLinkRecord({
    required this.medicationProductId,
    required this.professionalLeafletId,
    required this.relationType,
  });

  factory SyncMedicationLeafletLinkRecord.fromJson(Map<String, dynamic> json) {
    return SyncMedicationLeafletLinkRecord(
      medicationProductId: _requiredString(
        json['medication_product_id'],
        'medication_product_id',
      ),
      professionalLeafletId: _requiredString(
        json['professional_leaflet_id'],
        'professional_leaflet_id',
      ),
      relationType: _requiredString(json['relation_type'], 'relation_type'),
    );
  }

  final String medicationProductId;
  final String professionalLeafletId;
  final String relationType;
}

final class ClinicalSyncRelease {
  const ClinicalSyncRelease({
    required this.releaseSchema,
    required this.contentVersion,
    required this.generatedAt,
    required this.activeIngredients,
    required this.medications,
    required this.presentations,
    this.administrationGuidance = const <SyncAdministrationGuidanceRecord>[],
    this.incompatibilities = const <SyncIncompatibilityRecord>[],
    this.professionalLeaflets = const <SyncProfessionalLeafletRecord>[],
    this.medicationLeafletLinks = const <SyncMedicationLeafletLinkRecord>[],
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
    final rawAdministrationGuidance =
        json['administration_guidance'] ?? const <dynamic>[];
    final rawIncompatibilities = json['incompatibilities'] ?? const <dynamic>[];
    final rawProfessionalLeaflets =
        json['professional_leaflets'] ?? const <dynamic>[];
    final rawMedicationLeafletLinks =
        json['medication_leaflet_links'] ?? const <dynamic>[];
    if (rawIngredients is! List<dynamic> ||
        rawMedications is! List<dynamic> ||
        rawPresentations is! List<dynamic> ||
        rawAdministrationGuidance is! List<dynamic> ||
        rawIncompatibilities is! List<dynamic> ||
        rawProfessionalLeaflets is! List<dynamic> ||
        rawMedicationLeafletLinks is! List<dynamic>) {
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
    final administrationGuidance = rawAdministrationGuidance
        .map(
          (item) => SyncAdministrationGuidanceRecord.fromJson(
            _requiredMap(item, 'administration_guidance[]'),
          ),
        )
        .toList(growable: false);
    final incompatibilities = rawIncompatibilities
        .map(
          (item) => SyncIncompatibilityRecord.fromJson(
            _requiredMap(item, 'incompatibilities[]'),
          ),
        )
        .toList(growable: false);
    final professionalLeaflets = rawProfessionalLeaflets
        .map(
          (item) => SyncProfessionalLeafletRecord.fromJson(
            _requiredMap(item, 'professional_leaflets[]'),
          ),
        )
        .toList(growable: false);
    final medicationLeafletLinks = rawMedicationLeafletLinks
        .map(
          (item) => SyncMedicationLeafletLinkRecord.fromJson(
            _requiredMap(item, 'medication_leaflet_links[]'),
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

    final presentationIds = presentations
        .map((item) => item.presentation.id)
        .toSet();
    for (final presentation in presentations) {
      if (!medicationIds.contains(presentation.medicationProductId)) {
        throw const FormatException(
          'Presentation references unknown medication.',
        );
      }
    }

    for (final guidance in administrationGuidance) {
      if (!medicationIds.contains(guidance.medicationProductId) ||
          !presentationIds.contains(guidance.presentationId)) {
        throw const FormatException(
          'Administration guidance references unknown clinical content.',
        );
      }
    }

    for (final incompatibility in incompatibilities) {
      if (!ingredientIds.contains(incompatibility.activeIngredientId) ||
          !ingredientIds.contains(incompatibility.incompatibleIngredientId)) {
        throw const FormatException(
          'Incompatibility references unknown active ingredient.',
        );
      }
    }

    final leafletIds = professionalLeaflets.map((item) => item.id).toSet();
    for (final link in medicationLeafletLinks) {
      if (!medicationIds.contains(link.medicationProductId) ||
          !leafletIds.contains(link.professionalLeafletId)) {
        throw const FormatException(
          'Structured leaflet link references unknown clinical content.',
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
      administrationGuidance: administrationGuidance,
      incompatibilities: incompatibilities,
      professionalLeaflets: professionalLeaflets,
      medicationLeafletLinks: medicationLeafletLinks,
    );
  }

  final String releaseSchema;
  final String contentVersion;
  final DateTime generatedAt;
  final List<SyncActiveIngredientRecord> activeIngredients;
  final List<SyncMedicationRecord> medications;
  final List<SyncPresentationRecord> presentations;
  final List<SyncAdministrationGuidanceRecord> administrationGuidance;
  final List<SyncIncompatibilityRecord> incompatibilities;
  final List<SyncProfessionalLeafletRecord> professionalLeaflets;
  final List<SyncMedicationLeafletLinkRecord> medicationLeafletLinks;
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

String? _nullableScalarString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num || value is String) {
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
  throw const FormatException('Expected numeric/string scalar or null.');
}
