import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/home/presentation/home_screen.dart';
import 'package:nursing_clinical_core/theme/clinical_theme.dart';

void main() {
  testWidgets('home exposes dominant search and fat-finger quick actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: const HomeScreen(),
      ),
    );

    expect(find.text('O que você precisa fazer agora?'), findsOneWidget);
    expect(
      find.text('Buscar medicamento ou princípio ativo'),
      findsOneWidget,
    );
    expect(find.text('Calculadoras'), findsOneWidget);
    expect(find.text('Recentes'), findsOneWidget);

    final searchSize = tester.getSize(find.byKey(HomeScreen.searchKey));
    expect(searchSize.height, greaterThanOrEqualTo(48));

    final doseSize = tester.getSize(find.byKey(HomeScreen.doseActionKey));
    expect(doseSize.height, greaterThanOrEqualTo(48));
  });

  test('clinical semantic colors exist in light and dark modes', () {
    final light = ClinicalTheme.light()
        .extension<ClinicalSemanticColors>();
    final dark = ClinicalTheme.dark()
        .extension<ClinicalSemanticColors>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.critical, isNot(light.warning));
    expect(dark!.critical, isNot(dark.warning));
  });
}
