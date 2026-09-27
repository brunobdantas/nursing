import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/core/calculation/calculation_core.dart';

void main() {
  group('MED_DOSE_MG_TO_ML v1', () {
    test('caminho feliz: 750 mg com 500 mg/mL resulta em 1.5 mL', () {
      final result = CalculationCore.mgToMl(MgToMlInput(prescribedDose: Decimal.parse('750'),doseUnit:'mg',concentrationMass:Decimal.parse('500'),concentrationMassUnit:'mg',concentrationVolume:Decimal.parse('1'),concentrationVolumeUnit:'mL',calculationReady:true));
      expect(result.status,CalculationStatus.success); expect(result.formulaId,medDoseMgToMlFormulaId); expect(result.formulaVersion,medDoseMgToMlFormulaVersion); expect(result.resultValue,Decimal.parse('1.5')); expect(result.resultUnit,'mL'); expect(result.calculationMemory,contains('Volume: 750 mg × 1 mL ÷ 500 mg = 1.5 mL')); expect(result.dimensionalAlerts,contains('Cancelamento dimensional confirmado: mg ÷ (mg/mL) = mL.')); expect(result.error,isNull);
    });
    test('dose prescrita zero falha de forma segura',(){final r=CalculationCore.mgToMl(MgToMlInput(prescribedDose:Decimal.zero,doseUnit:'mg',concentrationMass:Decimal.parse('500'),concentrationMassUnit:'mg',concentrationVolume:Decimal.one,concentrationVolumeUnit:'mL',calculationReady:true)); expect(r.status,CalculationStatus.failure); expect(r.resultValue,isNull); expect(r.resultUnit,isNull); expect(r.error?.code,CalculationErrorCode.nonPositiveInput);});
    test('dose prescrita negativa falha de forma segura',(){final r=CalculationCore.mgToMl(MgToMlInput(prescribedDose:Decimal.parse('-1'),doseUnit:'mg',concentrationMass:Decimal.parse('500'),concentrationMassUnit:'mg',concentrationVolume:Decimal.one,concentrationVolumeUnit:'mL',calculationReady:true)); expect(r.status,CalculationStatus.failure); expect(r.resultValue,isNull); expect(r.error?.code,CalculationErrorCode.nonPositiveInput);});
    test('unidade incompatível falha sem conversão implícita',(){final r=CalculationCore.mgToMl(MgToMlInput(prescribedDose:Decimal.parse('750'),doseUnit:'mcg',concentrationMass:Decimal.parse('500'),concentrationMassUnit:'mg',concentrationVolume:Decimal.one,concentrationVolumeUnit:'mL',calculationReady:true)); expect(r.status,CalculationStatus.failure); expect(r.resultValue,isNull); expect(r.error?.code,CalculationErrorCode.incompatibleUnits); expect(r.dimensionalAlerts,isNotEmpty);});
    test('apresentação não validada para cálculo falha fechada',(){final r=CalculationCore.mgToMl(MgToMlInput(prescribedDose:Decimal.parse('750'),doseUnit:'mg',concentrationMass:Decimal.parse('500'),concentrationMassUnit:'mg',concentrationVolume:Decimal.one,concentrationVolumeUnit:'mL',calculationReady:false)); expect(r.status,CalculationStatus.failure); expect(r.resultValue,isNull); expect(r.error?.code,CalculationErrorCode.calculationNotReady);});
    test('resultado recorrente falha até existir política de arredondamento',(){final r=CalculationCore.mgToMl(MgToMlInput(prescribedDose:Decimal.one,doseUnit:'mg',concentrationMass:Decimal.parse('3'),concentrationMassUnit:'mg',concentrationVolume:Decimal.one,concentrationVolumeUnit:'mL',calculationReady:true)); expect(r.status,CalculationStatus.failure); expect(r.resultValue,isNull); expect(r.error?.code,CalculationErrorCode.roundingPolicyRequired);});
  });
}
