import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/bulario/bulario_repository.dart';
import 'package:nursing_clinical_core/features/search/presentation/search_screen.dart';
import 'package:nursing_clinical_core/theme/clinical_theme.dart';

import 'support/fake_medication_repository.dart';

class _BularioRepository extends BularioRepository {
  final record = const BularioRecord('1:12345:012345678', <String, dynamic>{
    'product_name': 'Dipirona Anvisa',
    'registration_number': '012345678',
    'process_number': '12345',
    'company_name': 'Fabricante oficial',
    'raw_columns': <String>['1', 'Dipirona Anvisa', '012345678'],
  });

  @override
  Future<List<BularioRecord>> search(
    String query, {
    int offset = 0,
    bool documents = false,
    List<String>? favorites,
    int limit = 50,
  }) async => documents ? const <BularioRecord>[] : <BularioRecord>[record];

  @override
  Future<List<BularioRecord>> forProcess(String process) async =>
      const <BularioRecord>[];
}

void main() {
  testWidgets('search waits 350 ms before calling repository', (tester) async {
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
    await tester.pump(const Duration(milliseconds: 349));
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
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(
      find.text('Resultado Aproximado / Nomes Semelhantes (LASA)'),
      findsOneWidget,
    );
    expect(find.text('DOPamina'), findsOneWidget);
    expect(find.text('Calcular'), findsOneWidget);
  });

  testWidgets('search combines clinical and official ANVISA results', (
    tester,
  ) async {
    final repository = FakeMedicationRepository(
      searchResponse: sampleSearchResponse(approximate: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: SearchScreen(
          repository: repository,
          bularioRepository: _BularioRepository(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('medication-search-field')),
      'dipirona',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Ficha clínica'), findsOneWidget);
    expect(find.text('Registro oficial Anvisa'), findsOneWidget);
    expect(find.text('Dipirona Anvisa'), findsOneWidget);
    expect(find.text('Registro 012345678'), findsOneWidget);
  });

  testWidgets(
    'calculate action is hidden without calculation-ready presentation',
    (tester) async {
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
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('Ver ficha'), findsOneWidget);
      expect(find.text('Calcular'), findsNothing);
    },
  );
}
