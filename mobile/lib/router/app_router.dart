import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/search/presentation/search_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/search',
      name: 'search',
      builder: (context, state) => const SearchScreen(),
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
            '$title será conectado ao Calculation Core em um próximo ciclo.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
