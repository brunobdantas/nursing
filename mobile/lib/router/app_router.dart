import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/network/api_config.dart';
import '../core/storage/clinical_database.dart';
import '../core/sync/sync_service.dart';
import '../features/calculator/presentation/calculator_screen.dart';
import '../features/calculator/presentation/fluid_calculator_screens.dart';
import '../features/home/data/favorite_medication_repository.dart';
import '../features/home/data/recent_medication_repository.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/medication/data/medication_repository.dart';
import '../features/medication/presentation/medication_detail_screen.dart';
import '../features/search/presentation/search_screen.dart';

final ClinicalDatabase clinicalDatabase = ClinicalDatabase();
final LocalMedicationRepository medicationRepository =
    LocalMedicationRepository(database: clinicalDatabase);
final SharedPreferencesRecentMedicationRepository recentMedicationRepository =
    SharedPreferencesRecentMedicationRepository();
final LocalFavoriteMedicationRepository favoriteMedicationRepository =
    LocalFavoriteMedicationRepository(database: clinicalDatabase);
final SyncService syncService = SyncService(
  baseUri: ApiConfig.baseUri,
  database: clinicalDatabase,
);

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => HomeScreen(
        recentRepository: recentMedicationRepository,
        favoriteRepository: favoriteMedicationRepository,
        syncCoordinator: syncService,
      ),
    ),
    GoRoute(
      path: '/search',
      name: 'search',
      builder: (context, state) =>
          SearchScreen(repository: medicationRepository),
    ),
    GoRoute(
      path: '/medications/:medicationId',
      name: 'medication-detail',
      builder: (context, state) {
        final medicationId = state.pathParameters['medicationId'];
        if (medicationId == null || medicationId.isEmpty) {
          return const _InvalidRouteScreen();
        }

        return MedicationDetailScreen(
          medicationId: medicationId,
          repository: medicationRepository,
          recentRepository: recentMedicationRepository,
          favoriteRepository: favoriteMedicationRepository,
          startCalculationFlow:
              state.uri.queryParameters['calculate'] == 'true',
        );
      },
    ),
    GoRoute(
      path: '/medications/:medicationId/calculator/:presentationId',
      name: 'medication-calculator',
      builder: (context, state) {
        final medicationId = state.pathParameters['medicationId'];
        final presentationId = state.pathParameters['presentationId'];
        if (medicationId == null ||
            medicationId.isEmpty ||
            presentationId == null ||
            presentationId.isEmpty) {
          return const _InvalidRouteScreen();
        }

        return CalculatorScreen(
          medicationId: medicationId,
          presentationId: presentationId,
          repository: medicationRepository,
        );
      },
    ),
    GoRoute(
      path: '/calculators/infusion',
      name: 'infusion-calculator',
      builder: (context, state) => const InfusionCalculatorScreen(),
    ),
    GoRoute(
      path: '/calculators/drip',
      name: 'drops-calculator',
      builder: (context, state) => const DropsCalculatorScreen(),
    ),
    GoRoute(
      path: '/calculators/:calculator',
      name: 'calculator',
      builder: (context, state) {
        final calculator = state.pathParameters['calculator'] ?? 'calculator';
        return _CalculatorPlaceholderScreen(calculator: calculator);
      },
    ),
  ],
);

class _CalculatorPlaceholderScreen extends StatelessWidget {
  const _CalculatorPlaceholderScreen({required this.calculator});

  final String calculator;

  @override
  Widget build(BuildContext context) {
    final title = switch (calculator) {
      'dose' => 'Calcular dose',
      'infusion' => 'Infusão',
      'drip' => 'Gotejamento',
      'mg-kg' => 'mg/kg',
      _ => 'Calculadora',
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '$title será conectado a uma jornada independente '
            'em um próximo ciclo.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _InvalidRouteScreen extends StatelessWidget {
  const _InvalidRouteScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nursing')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Não foi possível abrir este conteúdo com segurança.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
