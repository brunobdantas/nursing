import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/bulario/bulario_repository.dart';
import 'package:nursing_clinical_core/features/bulario/bulario_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository extends BularioRepository {
  final record = const BularioRecord('1:12345:012345678', {
    'product_name': 'Dipirona teste',
    'registration_number': '012345678',
    'process_number': '12345',
    'company_name': 'Fabricante teste',
    'raw_columns': ['1', 'Dipirona teste', '012345678'],
  });

  @override
  Future<Map<String, dynamic>> summary() async => {
    'products': 1,
    'document_records': 0,
  };

  @override
  Future<List<BularioRecord>> search(
    String query, {
    int offset = 0,
    bool documents = false,
    List<String>? favorites,
    int limit = 50,
  }) async => documents ? [] : [record];

  @override
  Future<List<BularioRecord>> forProcess(String process) async => [];
}

void main() {
  testWidgets('native catalogue opens source, favorites and personal notes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: BularioScreen(repository: _Repository())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dipirona teste'));
    await tester.pumpAndSettle();
    expect(find.text('Principal'), findsOneWidget);
    expect(find.textContaining('texto integral'), findsOneWidget);
    await tester.tap(find.byTooltip('Favoritar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remover dos favoritos'), findsOneWidget);
    await tester.tap(find.text('Fonte'));
    await tester.pumpAndSettle();
    expect(find.text('TA_CONSULTA_BULA_PRODUTO.CSV'), findsOneWidget);
    await tester.tap(find.text('Notas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Minha observação');
    await tester.ensureVisible(find.text('Salvar nota'));
    await tester.tap(find.text('Salvar nota'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('bulario-note-product-1:12345:012345678'),
      'Minha observação',
    );
    expect(tester.takeException(), isNull);
  });
}
