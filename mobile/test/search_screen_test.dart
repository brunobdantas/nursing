import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/search/presentation/search_screen.dart';
import 'package:nursing_clinical_core/theme/clinical_theme.dart';

import 'support/fake_medication_repository.dart';

void main() {
  testWidgets('search waits 500 ms before calling repository', (tester) async {
    final repository = FakeMedicationRepository(
      searchResponse: sampleSearchResponse(approximate: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: SearchScreen(repository: repository),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('medication-search-field')),
      'dopa',
    );
    await tester.pump(const Duration(milliseconds: 499));
    expect(repository.searchCalls, 0);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(repository.searchCalls, 1);
    expect(repository.lastQuery, 'dopa');
  });

  testWidgets('approximate LASA result is explicit and calculate is gated', (
    tester,
  ) async {
    final repository = FakeMedicationRepository(
      searchResponse: sampleSearchResponse(
        approximate: true,
        calculationReady: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: SearchScreen(repository: repository),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('medication-search-field')),
      'dopa',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(
      find.text('Resultado Aproximado / Nomes Semelhantes (LASA)'),
      findsOneWidget,
    );
    expect(find.text('DOPamina'), findsOneWidget);
    expect(find.text('Calcular'), findsOneWidget);
  });

  testWidgets('calculate action is hidden without calculation-ready presentation', (
    tester,
  ) async {
    final repository = FakeMedicationRepository(
      searchResponse: sampleSearchResponse(
        approximate: false,
        calculationReady: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: SearchScreen(repository: repository),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('medication-search-field')),
      'dopa',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('Ver ficha'), findsOneWidget);
    expect(find.text('Calcular'), findsNothing);
  });
}
