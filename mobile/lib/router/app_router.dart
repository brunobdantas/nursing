import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/network/api_config.dart';
import '../core/storage/clinical_database.dart';
import '../core/sync/sync_service.dart';
import '../features/bulario/bulario_screen.dart';
import '../features/calculator/presentation/calculator_screen.dart';
import '../features/calculator/presentation/fluid_calculator_screens.dart';
import '../features/home/data/favorite_medication_repository.dart';
import '../features/home/data/recent_medication_repository.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/medication/data/medication_repository.dart';
import '../features/medication/presentation/medication_detail_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/workspace/presentation/clinical_tools_screens.dart';
import '../features/workspace/presentation/clinical_workspace_screen.dart';
import '../features/workspace/presentation/productivity_screens.dart';
import '../features/workspace/presentation/recent_whitebook_features.dart';

final ClinicalDatabase clinicalDatabase = ClinicalDatabase();
final LocalMedicationRepository medicationRepository =
    LocalMedicationRepository(database: clinicalDatabase);
final SharedPreferencesRecentMedicationRepository recentMedicationRepository =
    SharedPreferencesRecentMedicationRepository();
final LocalFavoriteMedicationRepository favoriteMedicationRepository =
    LocalFavoriteMedicationRepository(database: clinicalDatabase);
final SyncService syncService = SyncService(
  endpoints: <SyncEndpoint>[
    if (ApiConfig.apiBaseUri case final apiBaseUri?)
      SyncEndpoint.api(label: 'API clínica', baseUri: apiBaseUri),
    SyncEndpoint.staticRelease(
      label: 'Base clínica pública',
      uri: ApiConfig.publicClinicalReleaseUri,
    ),
  ],
  database: clinicalDatabase,
);

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      name: 'workspace',
      builder: (context, state) => ClinicalWorkspaceScreen(
        recentRepository: recentMedicationRepository,
        favoriteRepository: favoriteMedicationRepository,
        syncCoordinator: syncService,
      ),
    ),
    GoRoute(
      path: '/classic-home',
      name: 'classic-home',
      builder: (context, state) => HomeScreen(
        recentRepository: recentMedicationRepository,
        favoriteRepository: favoriteMedicationRepository,
        syncCoordinator: syncService,
      ),
    ),
    GoRoute(
      path: '/global-search',
      name: 'global-search',
      builder: (context, state) =>
          GlobalClinicalSearchScreen(repository: medicationRepository),
    ),
    GoRoute(
      path: '/bulario',
      builder: (context, state) =>
          BularioScreen(initialQuery: state.uri.queryParameters['q'] ?? ''),
    ),
    GoRoute(
      path: '/search',
      name: 'search',
      builder: (context, state) =>
          SearchScreen(repository: medicationRepository),
    ),
    GoRoute(
      path: '/assistant',
      name: 'assistant',
      builder: (context, state) =>
          ClinicalAssistantScreen(repository: medicationRepository),
    ),
    GoRoute(
      path: '/interactions',
      name: 'interactions',
      builder: (context, state) =>
          InteractionCheckerScreen(repository: medicationRepository),
    ),
    GoRoute(
      path: '/favorites',
      name: 'favorites',
      builder: (context, state) =>
          FavoritesScreen(repository: favoriteMedicationRepository),
    ),
    GoRoute(
      path: '/notes',
      name: 'notes',
      builder: (context, state) => const LocalNotesScreen(),
    ),
    GoRoute(
      path: '/flashcards',
      name: 'flashcards',
      builder: (context, state) => const FlashcardsScreen(),
    ),
    GoRoute(
      path: '/quizzes',
      name: 'quizzes',
      builder: (context, state) => const QuizzesScreen(),
    ),
    GoRoute(
      path: '/catalog/administration',
      name: 'administration-catalog',
      builder: (context, state) => const ClinicalCatalogScreen(
        title: 'Administração de medicamentos',
        description:
            'Catálogo para organizar conteúdos de preparo, vias e '
            'administração. Fichas clínicas só são liberadas após revisão.',
        topics: <String>[
          'Administração por via oral',
          'Administração intravenosa',
          'Administração intramuscular',
          'Administração subcutânea',
          'Administração por sonda',
          'Diluição e reconstituição',
        ],
      ),
    ),
    GoRoute(
      path: '/catalog/procedures',
      name: 'procedures-catalog',
      builder: (context, state) => const ClinicalCatalogScreen(
        title: 'Procedimentos de enfermagem',
        description:
            'Estrutura editorial para procedimentos com fonte, revisão, '
            'materiais, etapas, alertas e registro.',
        topics: <String>[
          'Higienização das mãos',
          'Punção venosa periférica',
          'Curativos',
          'Cateterismo vesical',
          'Sinais vitais',
          'Coleta de exames',
        ],
      ),
    ),
    GoRoute(
      path: '/catalog/scales',
      name: 'scales-catalog',
      builder: (context, state) => const ClinicalCatalogScreen(
        title: 'Escalas & instrumentos',
        description:
            'Catálogo preparado para escalas com entradas validadas, '
            'resultado, interpretação e referência versionada.',
        topics: <String>[
          'Escala de Glasgow',
          'Escala de Braden',
          'Escala de Morse',
          'RASS',
          'Escala visual analógica',
        ],
      ),
    ),
    GoRoute(
      path: '/catalog/protocols',
      name: 'protocols-catalog',
      builder: (context, state) => const ClinicalCatalogScreen(
        title: 'Protocolos & fluxogramas',
        description:
            'Área preparada para protocolos institucionais e fluxos '
            'versionados, sem criar recomendações clínicas não revisadas.',
        topics: <String>[
          'Segurança na administração de medicamentos',
          'Prevenção de quedas',
          'Prevenção de lesão por pressão',
          'Reconhecimento de deterioração clínica',
          'Fluxos institucionais',
        ],
      ),
    ),
    GoRoute(
      path: '/catalog/codes',
      name: 'codes-catalog',
      builder: (context, state) => const ClinicalCatalogScreen(
        title: 'Códigos e tabelas',
        description:
            'Estrutura para catálogos de codificação quando as bases '
            'licenciadas ou públicas forem incorporadas ao release.',
        topics: <String>[
          'CID-10',
          'SIGTAP / SUS',
          'TUSS',
          'LOINC',
          'SNOMED CT',
        ],
      ),
    ),
    GoRoute(
      path: '/access',
      name: 'access-content',
      builder: (context, state) => const AccessAndContentScreen(),
    ),
    GoRoute(
      path: '/differential',
      name: 'differential-reasoning',
      builder: (context, state) => const DifferentialReasoningScreen(),
    ),
    GoRoute(
      path: '/areas/prescription',
      name: 'prescription-area',
      builder: (context, state) => const ClinicalAreaHubScreen(
        title: 'Prescrição e preparo',
        description:
            'Jornada estruturada para consulta de prescrições, preparo e '
            'conferência, sem substituir prescrição ou protocolo institucional.',
        restricted: true,
        groups: <String, List<String>>{
          'Prescrição': <String>[
            'Leitura e conferência da prescrição',
            'Reconciliação e checagens',
            'Aprazamento e documentação',
          ],
          'Preparo': <String>[
            'Diluição e reconstituição',
            'Compatibilidade de vias',
            'Rotulagem e dupla checagem',
          ],
        },
      ),
    ),
    GoRoute(
      path: '/areas/emergency',
      name: 'emergency-area',
      builder: (context, state) => const ClinicalAreaHubScreen(
        title: 'Emergência & UTI',
        description:
            'Área organizada por contexto crítico, monitorização e fluxos '
            'assistenciais versionados.',
        restricted: true,
        groups: <String, List<String>>{
          'Emergência': <String>[
            'Avaliação inicial',
            'Deterioração clínica',
            'Segurança em situações críticas',
          ],
          'UTI': <String>[
            'Monitorização',
            'Dispositivos e cuidados intensivos',
            'Sedação e avaliação neurológica',
          ],
        },
      ),
    ),
    GoRoute(
      path: '/areas/pediatrics',
      name: 'pediatrics-area',
      builder: (context, state) => const ClinicalAreaHubScreen(
        title: 'Pediatria',
        description:
            'Conteúdo hierárquico por faixa etária e contexto pediátrico.',
        restricted: true,
        groups: <String, List<String>>{
          'Avaliação': <String>[
            'Avaliação pediátrica',
            'Sinais vitais por faixa etária',
            'Crescimento e desenvolvimento',
          ],
          'Administração': <String>[
            'Administração segura em pediatria',
            'Dispositivos e vias',
            'Cálculos pediátricos versionados',
          ],
        },
      ),
    ),
    GoRoute(
      path: '/areas/obgyn',
      name: 'obgyn-area',
      builder: (context, state) => const ClinicalAreaHubScreen(
        title: 'Saúde da mulher & obstetrícia',
        description:
            'Organização de conteúdos de ginecologia, gestação, parto e '
            'puerpério em fichas rastreáveis.',
        restricted: true,
        groups: <String, List<String>>{
          'Obstetrícia': <String>[
            'Pré-natal',
            'Trabalho de parto',
            'Puerpério',
          ],
          'Saúde da mulher': <String>[
            'Assistência ginecológica',
            'Planejamento reprodutivo',
            'Segurança e sinais de alerta',
          ],
        },
      ),
    ),
    GoRoute(
      path: '/areas/surgery',
      name: 'surgery-area',
      builder: (context, state) => const ClinicalAreaHubScreen(
        title: 'Cirurgia & perioperatório',
        description:
            'Fluxos de consulta para pré, intra e pós-operatório com '
            'revisão editorial.',
        restricted: true,
        groups: <String, List<String>>{
          'Pré-operatório': <String>[
            'Preparo pré-operatório',
            'Checklist e identificação',
          ],
          'Intraoperatório': <String>[
            'Segurança cirúrgica',
            'Posicionamento e dispositivos',
          ],
          'Pós-operatório': <String>[
            'Recuperação pós-anestésica',
            'Cuidados pós-operatórios',
          ],
        },
      ),
    ),
    GoRoute(
      path: '/areas/antimicrobials',
      name: 'antimicrobials-area',
      builder: (context, state) => const ClinicalAreaHubScreen(
        title: 'Antimicrobianos',
        description:
            'Consulta organizada para antimicrobianos e stewardship, com '
            'conteúdo bloqueado sem referência revisada.',
        restricted: true,
        groups: <String, List<String>>{
          'Consulta': <String>[
            'Classes de antimicrobianos',
            'Administração e monitorização',
            'Ajustes e populações especiais',
          ],
          'Stewardship': <String>[
            'Uso responsável',
            'Coleta antes da terapia',
            'Reavaliação de terapia',
          ],
        },
      ),
    ),
    GoRoute(
      path: '/areas/vaccination',
      name: 'vaccination-area',
      builder: (context, state) => const ClinicalAreaHubScreen(
        title: 'Vacinação',
        description:
            'Estrutura para imunização, calendários, técnica e registro.',
        groups: <String, List<String>>{
          'Imunização': <String>[
            'Calendários vacinais',
            'Vias e técnica de administração',
            'Conservação e cadeia de frio',
          ],
          'Segurança': <String>[
            'Triagem pré-vacinal',
            'Eventos adversos',
            'Registro da vacinação',
          ],
        },
      ),
    ),
    GoRoute(
      path: '/areas/labs',
      name: 'labs-area',
      builder: (context, state) => const ClinicalAreaHubScreen(
        title: 'Laboratório & exames',
        description:
            'Catálogo para exames, unidades, coleta e interpretação baseada '
            'em fontes e intervalos de referência versionados.',
        restricted: true,
        groups: <String, List<String>>{
          'Laboratório': <String>[
            'Hemograma',
            'Eletrólitos',
            'Função renal',
            'Função hepática',
            'Coagulação',
          ],
          'Coleta': <String>[
            'Preparo para coleta',
            'Identificação de amostras',
            'Conservação e transporte',
          ],
        },
      ),
    ),
    GoRoute(
      path: '/calculators',
      name: 'calculators',
      builder: (context, state) => const CalculatorsHubScreen(),
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
      builder: (context, state) => InfusionCalculatorScreen(
        initialVolumeMl: state.uri.queryParameters['volumeMl'],
        initialDurationMinutes: state.uri.queryParameters['durationMinutes'],
        contextLabel: state.uri.queryParameters['context'],
      ),
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
            '$title exige uma fórmula clínica versionada e permanece bloqueada até a validação editorial.',
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
