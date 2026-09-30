import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/features/leaflets/leaflet_library.dart';
import 'package:nursing_clinical_core/features/leaflets/leaflet_screens.dart';
import 'package:nursing_clinical_core/theme/clinical_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final asset = jsonDecode(utf8.decode(gzip.decode(File('assets/leaflets/professional.json.gz').readAsBytesSync()))) as Map<String, dynamic>;
  final leaflets = (asset['leaflets'] as List).map((r) => NativeLeaflet(r as Map<String, dynamic>)).toList();

  test('bundled source text survives section indexing without loss', () {
    expect(leaflets.length, greaterThan(20));
    expect(leaflets.map((r) => r.id).toSet().length, leaflets.length);
    for (final leaflet in leaflets) {
      expect(leaflet.sections.map((s) => s.text).join(), leaflet.pages.join('\n\n'), reason: leaflet.name);
      expect(leaflet.hash, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(leaflet.sourceUrl, startsWith('https://www.cristalia.com.br/produto/'));
      expect(leaflet.pages.join().length, greaterThan(1500));
    }
  });

  testWidgets('real bundled leaflet: search, read, font, favorites and notes offline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(LeafletLibrary.load);
    await tester.pumpWidget(MaterialApp(theme: ClinicalTheme.light(), home: const LeafletLibraryScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('leaflet-search')), 'Xylestesin');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsWidgets);
    await expectLater(find.byType(Scaffold).first, matchesGoldenFile('evidence/01-library.png'));
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Ir direto ao assunto'), findsOneWidget);
    await tester.tap(find.byTooltip('Favoritar bula'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remover favorita'), findsOneWidget);
    await expectLater(find.byType(Scaffold).last, matchesGoldenFile('evidence/02-sections.png'));
    await tester.tap(find.text('Ler texto completo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aumentar texto'));
    await tester.enterText(find.byType(TextField), 'lidocaína');
    await tester.pumpAndSettle();
    expect(find.textContaining('trechos encontrados'), findsOneWidget);
    await expectLater(find.byType(Scaffold).last, matchesGoldenFile('evidence/03-reader.png'));
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Nota de teste offline');
    await tester.ensureVisible(find.text('Salvar nota'));
    await tester.tap(find.text('Salvar nota'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('native-leaflet-favorites'), isNotEmpty);
    expect(prefs.getStringList('native-leaflet-recent'), isNotEmpty);
    final id = prefs.getStringList('native-leaflet-favorites')!.single;
    expect(prefs.getString('native-leaflet-note-$id'), 'Nota de teste offline');
    expect(tester.takeException(), isNull);
  });
}
