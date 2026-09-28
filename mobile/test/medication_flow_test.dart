import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/calculator/presentation/calculator_screen.dart';
import 'package:nursing_clinical_core/features/medication/presentation/medication_detail_screen.dart';
import 'package:nursing_clinical_core/theme/clinical_theme.dart';

import 'support/fake_favorite_medication_repository.dart';
import 'support/fake_medication_repository.dart';
import 'support/fake_recent_medication_repository.dart';

void main() {
  testWidgets(
    'medication detail renders identity, alerts and selected presentation',
    (tester) async {
      final repository = FakeMedicationRepository();
      final recentRepository = FakeRecentMedicationRepository();
      final favoriteRepository = FakeFavoriteMedicationRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: ClinicalTheme.light(),
          home: MedicationDetailScreen(
            medicationId: repository.detailResponse.id,
            repository: repository,
            recentRepository: recentRepository,
            favoriteRepository: favoriteRepository,
            startCalculationFlow: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Medicamento Teste'), findsOneWidget);
      expect(find.text('dipirona'), findsOneWidget);
      expect(find.text('Alertas'), findsOneWidget);
      expect(find.text('Analgésicos e antipiréticos'), findsOneWidget);
      expect(find.text('Referência'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -560));
      await tester.pumpAndSettle();

      expect(find.text('Bula e fontes oficiais'), findsOneWidget);
      expect(
        find.text('Cadastro regulatório: Anvisa • apresentações: CMED'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('open-professional-leaflet')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('Preparo & Administração'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Preparo & Administração'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Incompatibilidades'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Incompatibilidades'), findsOneWidget);
      expect(find.text('NÃO COMPATÍVEL EM Y'), findsOneWidget);
      expect(find.text('Bicarbonato de sódio'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Ampola 500 mg/mL'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Ampola 500 mg/mL'), findsOneWidget);
      expect(find.text('Validada para cálculo'), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('calculate-dose-button')),
      );
      expect(button.onPressed, isNotNull);
      expect(recentRepository.recordCalls, 1);

      expect(
        find.byKey(const ValueKey<String>('favorite-toggle-button')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('favorite-toggle-button')),
      );
      await tester.pumpAndSettle();
      expect(favoriteRepository.toggleCalls, 1);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    },
  );

  testWidgets('calculator connects prescribed dose to CalculationCore memory', (
    tester,
  ) async {
    final repository = FakeMedicationRepository();
    final detail = repository.detailResponse;
    final presentation = detail.presentations.single;

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: CalculatorScreen(
          medicationId: detail.id,
          presentationId: presentation.id,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Concentração estruturada: 500 mg / 1 mL'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('prescribed-dose-field')),
      '750',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('run-dose-calculation')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('calculation-result-card')),
      findsOneWidget,
    );
    expect(find.text('1.5 mL'), findsOneWidget);
    expect(find.text('Memória de Cálculo'), findsOneWidget);
    expect(
      find.text('Volume: 750 mg × 1 mL ÷ 500 mg = 1.5 mL'),
      findsOneWidget,
    );
  });
}
