import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/home/data/recent_medication_repository.dart';
import 'package:nursing_clinical_core/features/home/presentation/home_screen.dart';
import 'package:nursing_clinical_core/theme/clinical_theme.dart';

import 'support/fake_recent_medication_repository.dart';

void main() {
  testWidgets('home exposes dominant search and fat-finger quick actions', (
    tester,
  ) async {
    final recentRepository = FakeRecentMedicationRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: HomeScreen(recentRepository: recentRepository),
      ),
    );
    await tester.pump();

    expect(find.text('O que você precisa fazer agora?'), findsOneWidget);
    expect(find.text('Buscar medicamento ou princípio ativo'), findsOneWidget);
    expect(find.text('Calculadoras'), findsOneWidget);
    expect(find.text('Recentes'), findsOneWidget);

    final searchSize = tester.getSize(find.byKey(HomeScreen.searchKey));
    expect(searchSize.height, greaterThanOrEqualTo(48));

    final doseSize = tester.getSize(find.byKey(HomeScreen.doseActionKey));
    expect(doseSize.height, greaterThanOrEqualTo(48));

    final infusionSize = tester.getSize(
      find.byKey(HomeScreen.infusionActionKey),
    );
    expect(infusionSize.height, greaterThanOrEqualTo(48));

    final dropsSize = tester.getSize(find.byKey(HomeScreen.dropsActionKey));
    expect(dropsSize.height, greaterThanOrEqualTo(48));
  });

  testWidgets('home renders persisted recent medication', (tester) async {
    final recentRepository = FakeRecentMedicationRepository(
      initial: <RecentMedication>[
        RecentMedication(
          id: '11111111-1111-1111-1111-111111111111',
          displayName: 'Medicamento Recente',
          genericName: 'substância recente',
          viewedAt: DateTime.utc(2026, 9, 27, 2),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: HomeScreen(recentRepository: recentRepository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Medicamento Recente'), findsOneWidget);
    expect(find.text('substância recente'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('recent-11111111-1111-1111-1111-111111111111'),
      ),
      findsOneWidget,
    );
  });

  test('clinical semantic colors exist in light and dark modes', () {
    final light = ClinicalTheme.light().extension<ClinicalSemanticColors>();
    final dark = ClinicalTheme.dark().extension<ClinicalSemanticColors>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.critical, isNot(light.warning));
    expect(dark!.critical, isNot(dark.warning));
  });
}
