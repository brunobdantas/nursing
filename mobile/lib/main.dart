import 'package:flutter/material.dart';

import 'router/app_router.dart';
import 'theme/clinical_theme.dart';

void main() {
  runApp(const NursingApp());
}

class NursingApp extends StatelessWidget {
  const NursingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Nursing',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: ClinicalTheme.light(),
      darkTheme: ClinicalTheme.dark(),
      themeMode: ThemeMode.system,
    );
  }
}
