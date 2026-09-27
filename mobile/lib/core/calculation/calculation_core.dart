import 'package:decimal/decimal.dart';

/// Stable formula identifier. Never rename an existing identifier after release.
const String medDoseMgToMlFormulaId = 'MED_DOSE_MG_TO_ML';
const String medDoseMgToMlFormulaVersion = '1.0.0';

enum CalculationStatus { success, failure }

enum CalculationErrorCode {
  calculationNotReady,
  nonPositiveInput,
  incompatibleUnits,
  roundingPolicyRequired,
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
  }) {
    return CalculationResult._(
      status: CalculationStatus.success,
      formulaId: medDoseMgToMlFormulaId,
      formulaVersion: medDoseMgToMlFormulaVersion,
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
  }) {
    return CalculationResult._(
      status: CalculationStatus.failure,
      formulaId: medDoseMgToMlFormulaId,
      formulaVersion: medDoseMgToMlFormulaVersion,
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

/// Pure, deterministic clinical calculation engine.
///
/// V1 deliberately supports only the canonical dimensional contract:
///   prescribed dose: mg
///   concentration: mg / mL
///   result: mL
///
/// Unit conversion (mcg↔mg, g↔mg etc.) must be introduced as a separately
/// versioned, tested capability rather than inferred silently.
abstract final class CalculationCore {
  static CalculationResult mgToMl(MgToMlInput input) {
    if (!input.calculationReady) {
      return CalculationResult.failure(
        code: CalculationErrorCode.calculationNotReady,
        message:
            'Esta apresentação ainda não está validada para cálculo automático.',
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

    final unitsAreCompatible = input.doseUnit == canonicalDoseUnit &&
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

    // Formula expressed without floating point:
    // volume = prescribedDose * concentrationVolume / concentrationMass
    final numerator = input.prescribedDose * input.concentrationVolume;
    final exactResult = numerator / input.concentrationMass;

    // Clinical rounding rules depend on context/device and have not yet been
    // approved for V1. Never choose a number of decimal places implicitly.
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
    final concentration =
        input.concentrationMass / input.concentrationVolume;
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
}
