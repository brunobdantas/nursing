import 'package:decimal/decimal.dart';

/// Stable formula identifiers. Never rename an existing identifier after release.
const String medDoseMgToMlFormulaId = 'MED_DOSE_MG_TO_ML';
const String medDoseMgToMlFormulaVersion = '1.0.0';
const String medInfusionMlHFormulaId = 'MED_INFUSION_ML_H';
const String medInfusionMlHFormulaVersion = '1.0.0';
const String medDropsMinFormulaId = 'MED_DROPS_MIN';
const String medDropsMinFormulaVersion = '1.0.0';

enum CalculationStatus { success, failure }

enum CalculationErrorCode {
  calculationNotReady,
  nonPositiveInput,
  incompatibleUnits,
  roundingPolicyRequired,
}

enum TimeUnit {
  hours('h'),
  minutes('min');

  const TimeUnit(this.symbol);

  final String symbol;
}

final class CalculationError {
  const CalculationError({required this.code, required this.message});

  final CalculationErrorCode code;
  final String message;
}

final class MgToMlInput {
  const MgToMlInput({
    required this.prescribedDose,
    required this.doseUnit,
    required this.concentrationMass,
    required this.concentrationMassUnit,
    required this.concentrationVolume,
    required this.concentrationVolumeUnit,
    required this.calculationReady,
  });

  final Decimal prescribedDose;
  final String doseUnit;
  final Decimal concentrationMass;
  final String concentrationMassUnit;
  final Decimal concentrationVolume;
  final String concentrationVolumeUnit;

  /// Must come from the validated API/local clinical content release.
  final bool calculationReady;
}

final class InfusionInput {
  const InfusionInput({
    required this.totalVolume,
    required this.volumeUnit,
    required this.duration,
    required this.durationUnit,
  });

  final Decimal totalVolume;
  final String volumeUnit;
  final Decimal duration;
  final TimeUnit durationUnit;
}

final class DropsInput {
  const DropsInput({
    required this.totalVolume,
    required this.volumeUnit,
    required this.duration,
    required this.durationUnit,
  });

  final Decimal totalVolume;
  final String volumeUnit;
  final Decimal duration;
  final TimeUnit durationUnit;
}

final class CalculationResult {
  const CalculationResult._({
    required this.status,
    required this.formulaId,
    required this.formulaVersion,
    this.resultValue,
    this.resultUnit,
    this.calculationMemory = const <String>[],
    this.dimensionalAlerts = const <String>[],
    this.error,
  });

  factory CalculationResult.success({
    required Decimal resultValue,
    required String resultUnit,
    required List<String> calculationMemory,
    required List<String> dimensionalAlerts,
    String formulaId = medDoseMgToMlFormulaId,
    String formulaVersion = medDoseMgToMlFormulaVersion,
  }) {
    return CalculationResult._(
      status: CalculationStatus.success,
      formulaId: formulaId,
      formulaVersion: formulaVersion,
      resultValue: resultValue,
      resultUnit: resultUnit,
      calculationMemory: List.unmodifiable(calculationMemory),
      dimensionalAlerts: List.unmodifiable(dimensionalAlerts),
    );
  }

  factory CalculationResult.failure({
    required CalculationErrorCode code,
    required String message,
    List<String> dimensionalAlerts = const <String>[],
    String formulaId = medDoseMgToMlFormulaId,
    String formulaVersion = medDoseMgToMlFormulaVersion,
  }) {
    return CalculationResult._(
      status: CalculationStatus.failure,
      formulaId: formulaId,
      formulaVersion: formulaVersion,
      dimensionalAlerts: List.unmodifiable(dimensionalAlerts),
      error: CalculationError(code: code, message: message),
    );
  }

  final CalculationStatus status;
  final String formulaId;
  final String formulaVersion;
  final Decimal? resultValue;
  final String? resultUnit;
  final List<String> calculationMemory;
  final List<String> dimensionalAlerts;
  final CalculationError? error;

  bool get isSuccess => status == CalculationStatus.success;
}

final class DropsCalculationResult {
  const DropsCalculationResult._({
    required this.status,
    required this.formulaId,
    required this.formulaVersion,
    this.dropsPerMinute,
    this.microdropsPerMinute,
    this.calculationMemory = const <String>[],
    this.dimensionalAlerts = const <String>[],
    this.error,
  });

  factory DropsCalculationResult.success({
    required Decimal dropsPerMinute,
    required Decimal microdropsPerMinute,
    required List<String> calculationMemory,
    required List<String> dimensionalAlerts,
  }) {
    return DropsCalculationResult._(
      status: CalculationStatus.success,
      formulaId: medDropsMinFormulaId,
      formulaVersion: medDropsMinFormulaVersion,
      dropsPerMinute: dropsPerMinute,
      microdropsPerMinute: microdropsPerMinute,
      calculationMemory: List.unmodifiable(calculationMemory),
      dimensionalAlerts: List.unmodifiable(dimensionalAlerts),
    );
  }

  factory DropsCalculationResult.failure({
    required CalculationErrorCode code,
    required String message,
    List<String> dimensionalAlerts = const <String>[],
  }) {
    return DropsCalculationResult._(
      status: CalculationStatus.failure,
      formulaId: medDropsMinFormulaId,
      formulaVersion: medDropsMinFormulaVersion,
      dimensionalAlerts: List.unmodifiable(dimensionalAlerts),
      error: CalculationError(code: code, message: message),
    );
  }

  final CalculationStatus status;
  final String formulaId;
  final String formulaVersion;
  final Decimal? dropsPerMinute;
  final Decimal? microdropsPerMinute;
  final List<String> calculationMemory;
  final List<String> dimensionalAlerts;
  final CalculationError? error;

  bool get isSuccess => status == CalculationStatus.success;
}

/// Pure, deterministic clinical calculation engine.
///
/// No method performs implicit floating-point arithmetic or clinical rounding.
abstract final class CalculationCore {
  static CalculationResult mgToMl(MgToMlInput input) {
    if (!input.calculationReady) {
      return CalculationResult.failure(
        code: CalculationErrorCode.calculationNotReady,
        message: 'Esta apresentação ainda não está validada para cálculo automático.',
      );
    }

    if (input.prescribedDose <= Decimal.zero ||
        input.concentrationMass <= Decimal.zero ||
        input.concentrationVolume <= Decimal.zero) {
      return CalculationResult.failure(
        code: CalculationErrorCode.nonPositiveInput,
        message: 'Dose e concentração devem ser maiores que zero.',
      );
    }

    const canonicalDoseUnit = 'mg';
    const canonicalMassUnit = 'mg';
    const canonicalVolumeUnit = 'mL';

    final unitsAreCompatible =
        input.doseUnit == canonicalDoseUnit &&
        input.concentrationMassUnit == canonicalMassUnit &&
        input.concentrationVolumeUnit == canonicalVolumeUnit;

    if (!unitsAreCompatible) {
      return CalculationResult.failure(
        code: CalculationErrorCode.incompatibleUnits,
        message:
            'Unidades incompatíveis com $medDoseMgToMlFormulaId. '
            'Esperado: dose em mg e concentração em mg/mL.',
        dimensionalAlerts: <String>[
          'Falha dimensional segura: ${input.doseUnit} ÷ '
              '(${input.concentrationMassUnit}/${input.concentrationVolumeUnit}) '
              'não foi aceita como mg ÷ (mg/mL).',
        ],
      );
    }

    final numerator = input.prescribedDose * input.concentrationVolume;
    final exactResult = numerator / input.concentrationMass;

    if (!exactResult.hasFinitePrecision) {
      return CalculationResult.failure(
        code: CalculationErrorCode.roundingPolicyRequired,
        message:
            'O resultado exige arredondamento. Nenhuma política clínica de '
            'arredondamento está aprovada para esta versão do cálculo.',
        dimensionalAlerts: const <String>[
          'As unidades são dimensionalmente compatíveis: mg ÷ (mg/mL) = mL.',
          'O cálculo foi interrompido antes de qualquer arredondamento implícito.',
        ],
      );
    }

    final result = exactResult.toDecimal();
    final concentration = input.concentrationMass / input.concentrationVolume;
    final concentrationText = concentration.hasFinitePrecision
        ? '${concentration.toDecimal()} mg/mL'
        : '${input.concentrationMass} mg / '
              '${input.concentrationVolume} mL';

    return CalculationResult.success(
      resultValue: result,
      resultUnit: canonicalVolumeUnit,
      calculationMemory: <String>[
        'Concentração: ${input.concentrationMass} mg ÷ '
            '${input.concentrationVolume} mL = $concentrationText',
        'Volume: ${input.prescribedDose} mg × '
            '${input.concentrationVolume} mL ÷ '
            '${input.concentrationMass} mg = $result mL',
      ],
      dimensionalAlerts: const <String>[
        'Cancelamento dimensional confirmado: mg ÷ (mg/mL) = mL.',
        'Nenhuma conversão implícita de unidade foi realizada.',
      ],
    );
  }

  static CalculationResult infusionMlPerHour(InfusionInput input) {
    if (input.totalVolume <= Decimal.zero || input.duration <= Decimal.zero) {
      return CalculationResult.failure(
        formulaId: medInfusionMlHFormulaId,
        formulaVersion: medInfusionMlHFormulaVersion,
        code: CalculationErrorCode.nonPositiveInput,
        message: 'Volume e tempo devem ser maiores que zero.',
      );
    }

    if (input.volumeUnit != 'mL') {
      return CalculationResult.failure(
        formulaId: medInfusionMlHFormulaId,
        formulaVersion: medInfusionMlHFormulaVersion,
        code: CalculationErrorCode.incompatibleUnits,
        message: 'A infusão V1 aceita volume somente em mL.',
      );
    }

    final exactResult = switch (input.durationUnit) {
      TimeUnit.hours => input.totalVolume / input.duration,
      TimeUnit.minutes =>
        (input.totalVolume * Decimal.fromInt(60)) / input.duration,
    };

    if (!exactResult.hasFinitePrecision) {
      return CalculationResult.failure(
        formulaId: medInfusionMlHFormulaId,
        formulaVersion: medInfusionMlHFormulaVersion,
        code: CalculationErrorCode.roundingPolicyRequired,
        message:
            'A velocidade exige arredondamento. O cálculo foi interrompido '
            'porque nenhuma política clínica de arredondamento está aprovada.',
      );
    }

    final result = exactResult.toDecimal();
    final memory = input.durationUnit == TimeUnit.hours
        ? <String>[
            'Velocidade: ${input.totalVolume} mL ÷ '
                '${input.duration} h = $result mL/h',
          ]
        : <String>[
            'Conversão temporal exata: ${input.duration} min; '
                '1 h = 60 min.',
            'Velocidade: ${input.totalVolume} mL × 60 ÷ '
                '${input.duration} min = $result mL/h',
          ];

    return CalculationResult.success(
      formulaId: medInfusionMlHFormulaId,
      formulaVersion: medInfusionMlHFormulaVersion,
      resultValue: result,
      resultUnit: 'mL/h',
      calculationMemory: memory,
      dimensionalAlerts: const <String>[
        'Volume aceito em mL.',
        'Tempo em minutos é convertido por razão exata de 60 min = 1 h.',
        'Nenhum arredondamento implícito foi realizado.',
      ],
    );
  }

  static DropsCalculationResult dropsPerMinute(DropsInput input) {
    if (input.totalVolume <= Decimal.zero || input.duration <= Decimal.zero) {
      return DropsCalculationResult.failure(
        code: CalculationErrorCode.nonPositiveInput,
        message: 'Volume e tempo devem ser maiores que zero.',
      );
    }

    if (input.volumeUnit != 'mL') {
      return DropsCalculationResult.failure(
        code: CalculationErrorCode.incompatibleUnits,
        message: 'O cálculo de gotejamento V1 aceita volume somente em mL.',
      );
    }

    final macroExact = switch (input.durationUnit) {
      TimeUnit.hours =>
        input.totalVolume / (input.duration * Decimal.fromInt(3)),
      TimeUnit.minutes =>
        (input.totalVolume * Decimal.fromInt(20)) / input.duration,
    };
    final microExact = switch (input.durationUnit) {
      TimeUnit.hours => input.totalVolume / input.duration,
      TimeUnit.minutes =>
        (input.totalVolume * Decimal.fromInt(60)) / input.duration,
    };

    if (!macroExact.hasFinitePrecision || !microExact.hasFinitePrecision) {
      return DropsCalculationResult.failure(
        code: CalculationErrorCode.roundingPolicyRequired,
        message:
            'O gotejamento exige arredondamento. O cálculo foi interrompido '
            'porque nenhuma política clínica de arredondamento está aprovada.',
        dimensionalAlerts: const <String>[
          'Macrogotas considera equipo de 20 gotas/mL.',
          'Microgotas considera equipo de 60 microgotas/mL.',
          'Nenhum arredondamento implícito foi realizado.',
        ],
      );
    }

    final macro = macroExact.toDecimal();
    final micro = microExact.toDecimal();
    final memory = input.durationUnit == TimeUnit.hours
        ? <String>[
            'Gotas/min: ${input.totalVolume} mL ÷ '
                '(${input.duration} h × 3) = $macro gotas/min',
            'Microgotas/min: ${input.totalVolume} mL ÷ '
                '${input.duration} h = $micro microgotas/min',
          ]
        : <String>[
            'Conversão temporal exata: ${input.duration} min; '
                '1 h = 60 min.',
            'Gotas/min: ${input.totalVolume} mL × 20 ÷ '
                '${input.duration} min = $macro gotas/min',
            'Microgotas/min: ${input.totalVolume} mL × 60 ÷ '
                '${input.duration} min = $micro microgotas/min',
          ];

    return DropsCalculationResult.success(
      dropsPerMinute: macro,
      microdropsPerMinute: micro,
      calculationMemory: memory,
      dimensionalAlerts: const <String>[
        'Macrogotas: fator de gotejamento fixo de 20 gotas/mL.',
        'Microgotas: fator de gotejamento fixo de 60 microgotas/mL.',
        'Confirme o fator impresso no equipo antes de administrar.',
      ],
    );
  }
}
