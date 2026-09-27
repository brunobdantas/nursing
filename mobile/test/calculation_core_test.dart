import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/core/calculation/calculation_core.dart';

void main() {
  group('MED_DOSE_MG_TO_ML v1', () {
    test('caminho feliz: 750 mg com 500 mg/mL resulta em 1.5 mL', () {
      final result = CalculationCore.mgToMl(
        MgToMlInput(
          prescribedDose: Decimal.parse('750'),
          doseUnit: 'mg',
          concentrationMass: Decimal.parse('500'),
          concentrationMassUnit: 'mg',
          concentrationVolume: Decimal.parse('1'),
          concentrationVolumeUnit: 'mL',
          calculationReady: true,
        ),
      );

      expect(result.status, CalculationStatus.success);
      expect(result.formulaId, medDoseMgToMlFormulaId);
      expect(result.formulaVersion, medDoseMgToMlFormulaVersion);
      expect(result.resultValue, Decimal.parse('1.5'));
      expect(result.resultUnit, 'mL');
      expect(
        result.calculationMemory,
        contains('Volume: 750 mg × 1 mL ÷ 500 mg = 1.5 mL'),
      );
      expect(
        result.dimensionalAlerts,
        contains('Cancelamento dimensional confirmado: mg ÷ (mg/mL) = mL.'),
      );
      expect(result.error, isNull);
    });

    test('dose prescrita zero falha de forma segura', () {
      final result = CalculationCore.mgToMl(
        MgToMlInput(
          prescribedDose: Decimal.zero,
          doseUnit: 'mg',
          concentrationMass: Decimal.parse('500'),
          concentrationMassUnit: 'mg',
          concentrationVolume: Decimal.one,
          concentrationVolumeUnit: 'mL',
          calculationReady: true,
        ),
      );

      expect(result.status, CalculationStatus.failure);
      expect(result.resultValue, isNull);
      expect(result.resultUnit, isNull);
      expect(result.error?.code, CalculationErrorCode.nonPositiveInput);
    });

    test('dose prescrita negativa falha de forma segura', () {
      final result = CalculationCore.mgToMl(
        MgToMlInput(
          prescribedDose: Decimal.parse('-1'),
          doseUnit: 'mg',
          concentrationMass: Decimal.parse('500'),
          concentrationMassUnit: 'mg',
          concentrationVolume: Decimal.one,
          concentrationVolumeUnit: 'mL',
          calculationReady: true,
        ),
      );

      expect(result.status, CalculationStatus.failure);
      expect(result.resultValue, isNull);
      expect(result.error?.code, CalculationErrorCode.nonPositiveInput);
    });

    test('unidade incompatível falha sem conversão implícita', () {
      final result = CalculationCore.mgToMl(
        MgToMlInput(
          prescribedDose: Decimal.parse('750'),
          doseUnit: 'mcg',
          concentrationMass: Decimal.parse('500'),
          concentrationMassUnit: 'mg',
          concentrationVolume: Decimal.one,
          concentrationVolumeUnit: 'mL',
          calculationReady: true,
        ),
      );

      expect(result.status, CalculationStatus.failure);
      expect(result.resultValue, isNull);
      expect(result.error?.code, CalculationErrorCode.incompatibleUnits);
      expect(result.dimensionalAlerts, isNotEmpty);
    });

    test('apresentação não validada para cálculo falha fechada', () {
      final result = CalculationCore.mgToMl(
        MgToMlInput(
          prescribedDose: Decimal.parse('750'),
          doseUnit: 'mg',
          concentrationMass: Decimal.parse('500'),
          concentrationMassUnit: 'mg',
          concentrationVolume: Decimal.one,
          concentrationVolumeUnit: 'mL',
          calculationReady: false,
        ),
      );

      expect(result.status, CalculationStatus.failure);
      expect(result.resultValue, isNull);
      expect(result.error?.code, CalculationErrorCode.calculationNotReady);
    });

    test(
      'resultado recorrente falha até existir política de arredondamento',
      () {
        final result = CalculationCore.mgToMl(
          MgToMlInput(
            prescribedDose: Decimal.one,
            doseUnit: 'mg',
            concentrationMass: Decimal.parse('3'),
            concentrationMassUnit: 'mg',
            concentrationVolume: Decimal.one,
            concentrationVolumeUnit: 'mL',
            calculationReady: true,
          ),
        );

        expect(result.status, CalculationStatus.failure);
        expect(result.resultValue, isNull);
        expect(result.error?.code, CalculationErrorCode.roundingPolicyRequired);
      },
    );
  });

  group('MED_INFUSION_ML_H v1', () {
    test('500 mL em 4 h resulta em 125 mL/h', () {
      final result = CalculationCore.infusionMlPerHour(
        InfusionInput(
          totalVolume: Decimal.parse('500'),
          volumeUnit: 'mL',
          duration: Decimal.parse('4'),
          durationUnit: TimeUnit.hours,
        ),
      );

      expect(result.status, CalculationStatus.success);
      expect(result.formulaId, medInfusionMlHFormulaId);
      expect(result.formulaVersion, medInfusionMlHFormulaVersion);
      expect(result.resultValue, Decimal.parse('125'));
      expect(result.resultUnit, 'mL/h');
      expect(
        result.calculationMemory,
        contains('Velocidade: 500 mL ÷ 4 h = 125 mL/h'),
      );
    });

    test('conversão segura de 240 min equivale ao cálculo de 4 h', () {
      final result = CalculationCore.infusionMlPerHour(
        InfusionInput(
          totalVolume: Decimal.parse('500'),
          volumeUnit: 'mL',
          duration: Decimal.parse('240'),
          durationUnit: TimeUnit.minutes,
        ),
      );

      expect(result.status, CalculationStatus.success);
      expect(result.resultValue, Decimal.parse('125'));
      expect(
        result.calculationMemory,
        contains('Velocidade: 500 mL × 60 ÷ 240 min = 125 mL/h'),
      );
    });

    test('tempo zero falha de forma segura', () {
      final result = CalculationCore.infusionMlPerHour(
        InfusionInput(
          totalVolume: Decimal.parse('500'),
          volumeUnit: 'mL',
          duration: Decimal.zero,
          durationUnit: TimeUnit.hours,
        ),
      );

      expect(result.status, CalculationStatus.failure);
      expect(result.resultValue, isNull);
      expect(result.error?.code, CalculationErrorCode.nonPositiveInput);
    });

    test('resultado recorrente exige política explícita de arredondamento', () {
      final result = CalculationCore.infusionMlPerHour(
        InfusionInput(
          totalVolume: Decimal.one,
          volumeUnit: 'mL',
          duration: Decimal.parse('3'),
          durationUnit: TimeUnit.hours,
        ),
      );

      expect(result.status, CalculationStatus.failure);
      expect(result.error?.code, CalculationErrorCode.roundingPolicyRequired);
    });
  });

  group('MED_DROPS_MIN v1', () {
    test('180 mL em 2 h resulta em 30 gotas/min e 90 microgotas/min', () {
      final result = CalculationCore.dropsPerMinute(
        DropsInput(
          totalVolume: Decimal.parse('180'),
          volumeUnit: 'mL',
          duration: Decimal.parse('2'),
          durationUnit: TimeUnit.hours,
        ),
      );

      expect(result.status, CalculationStatus.success);
      expect(result.formulaId, medDropsMinFormulaId);
      expect(result.formulaVersion, medDropsMinFormulaVersion);
      expect(result.dropsPerMinute, Decimal.parse('30'));
      expect(result.microdropsPerMinute, Decimal.parse('90'));
      expect(
        result.calculationMemory,
        contains('Gotas/min: 180 mL ÷ (2 h × 3) = 30 gotas/min'),
      );
    });

    test('120 minutos converte sem ponto flutuante implícito', () {
      final result = CalculationCore.dropsPerMinute(
        DropsInput(
          totalVolume: Decimal.parse('180'),
          volumeUnit: 'mL',
          duration: Decimal.parse('120'),
          durationUnit: TimeUnit.minutes,
        ),
      );

      expect(result.status, CalculationStatus.success);
      expect(result.dropsPerMinute, Decimal.parse('30'));
      expect(result.microdropsPerMinute, Decimal.parse('90'));
    });

    test('tempo zero bloqueia gotejamento', () {
      final result = CalculationCore.dropsPerMinute(
        DropsInput(
          totalVolume: Decimal.parse('180'),
          volumeUnit: 'mL',
          duration: Decimal.zero,
          durationUnit: TimeUnit.hours,
        ),
      );

      expect(result.status, CalculationStatus.failure);
      expect(result.dropsPerMinute, isNull);
      expect(result.microdropsPerMinute, isNull);
      expect(result.error?.code, CalculationErrorCode.nonPositiveInput);
    });

    test('resultado que exige arredondamento falha fechado', () {
      final result = CalculationCore.dropsPerMinute(
        DropsInput(
          totalVolume: Decimal.parse('500'),
          volumeUnit: 'mL',
          duration: Decimal.parse('6'),
          durationUnit: TimeUnit.hours,
        ),
      );

      expect(result.status, CalculationStatus.failure);
      expect(result.error?.code, CalculationErrorCode.roundingPolicyRequired);
    });
  });
}
