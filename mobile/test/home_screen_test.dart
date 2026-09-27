import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_clinical_core/core/sync/sync_service.dart';
import 'package:nursing_clinical_core/features/home/data/favorite_medication_repository.dart';
import 'package:nursing_clinical_core/features/home/data/recent_medication_repository.dart';
import 'package:nursing_clinical_core/features/home/presentation/home_screen.dart';
import 'package:nursing_clinical_core/theme/clinical_theme.dart';

import 'support/fake_favorite_medication_repository.dart';
import 'support/fake_recent_medication_repository.dart';
import 'support/fake_sync_coordinator.dart';

void main() {
  testWidgets('home exposes dominant search and fat-finger quick actions', (
    tester,
  ) async {
    final recentRepository = FakeRecentMedicationRepository();
    final favoriteRepository = FakeFavoriteMedicationRepository();
    final syncCoordinator = FakeClinicalSyncCoordinator();

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: HomeScreen(
          recentRepository: recentRepository,
          favoriteRepository: favoriteRepository,
          syncCoordinator: syncCoordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('O que você precisa fazer agora?'), findsOneWidget);
    expect(find.text('Buscar medicamento ou princípio ativo'), findsOneWidget);
    expect(find.text('Calculadoras'), findsOneWidget);
    expect(find.text('Favoritos'), findsOneWidget);

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

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Recentes'), findsOneWidget);
    expect(
      find.text('Base clínica atualizada e disponível offline'),
      findsOneWidget,
    );
  });

  testWidgets('home renders persisted favorite and recent medication', (
    tester,
  ) async {
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
    final favoriteRepository = FakeFavoriteMedicationRepository(
      initial: const <FavoriteMedication>[
        FavoriteMedication(
          id: '22222222-2222-2222-2222-222222222222',
          displayName: 'Medicamento Favorito',
          genericName: 'substância favorita',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: HomeScreen(
          recentRepository: recentRepository,
          favoriteRepository: favoriteRepository,
          syncCoordinator: FakeClinicalSyncCoordinator(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Medicamento Favorito'), findsOneWidget);
    expect(find.text('substância favorita'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('favorite-22222222-2222-2222-2222-222222222222'),
      ),
      findsOneWidget,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -520));
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

  testWidgets('home keeps offline-ready status when sync cannot refresh', (
    tester,
  ) async {
    final syncCoordinator = FakeClinicalSyncCoordinator(
      syncStatus: const ClinicalSyncStatus(
        state: ClinicalSyncState.offlineAvailable,
        hasLocalContent: true,
        contentVersion: 'clinical-release-v1-test',
        message: 'Sem conectividade.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.light(),
        home: HomeScreen(
          recentRepository: FakeRecentMedicationRepository(),
          favoriteRepository: FakeFavoriteMedicationRepository(),
          syncCoordinator: syncCoordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -850));
    await tester.pumpAndSettle();

    expect(
      find.text('Base clínica disponível offline • sincronização pendente'),
      findsOneWidget,
    );
    expect(syncCoordinator.syncCalls, 1);
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
