import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/calculator/presentation/fluid_calculator_screens.dart';
import 'package:nursing_clinical_core/theme/clinical_theme.dart';

void main() {
  testWidgets('infusion calculator renders 125 mL/h for 500 mL over 4 h', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: const InfusionCalculatorScreen(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('fluid-volume-field')),
      '500',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('fluid-time-field')),
      '4',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('run-infusion-calculation')),
    );
    await tester.pump();

    expect(find.text('125 mL/h'), findsOneWidget);
    expect(find.text('Memória de Cálculo'), findsOneWidget);
  });

  testWidgets('drops calculator renders macro and micro results', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: const DropsCalculatorScreen(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('fluid-volume-field')),
      '180',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('fluid-time-field')),
      '2',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('run-drops-calculation')),
    );
    await tester.pump();

    expect(find.text('30 gotas/min'), findsOneWidget);
    expect(find.text('90 microgotas/min'), findsOneWidget);
    expect(find.text('Memória de Cálculo'), findsOneWidget);
  });

  testWidgets('infusion calculator blocks zero duration', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: const InfusionCalculatorScreen(),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('fluid-volume-field')),
      '500',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('fluid-time-field')),
      '0',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('run-infusion-calculation')),
    );
    await tester.pump();

    expect(
      find.text('Volume e tempo devem ser maiores que zero.'),
      findsOneWidget,
    );
    expect(find.text('125 mL/h'), findsNothing);
  });
}
