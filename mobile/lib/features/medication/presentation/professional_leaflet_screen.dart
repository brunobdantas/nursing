import 'package:flutter/material.dart';

import '../../bulario/bulario_screen.dart';
import '../data/medication_models.dart';

/// Native text reader only. Never opens a PDF, WebView or external portal.
class ProfessionalLeafletScreen extends StatelessWidget {
  const ProfessionalLeafletScreen({required this.medication, super.key});
  final MedicationDetailResponse medication;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bula e referências')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BularioScreen(
                initialQuery: medication.anvisaRegistrationNumber ?? '',
              ),
            ),
          ),
          icon: const Icon(Icons.medication_outlined),
          label: const Text('Consultar cadastro Anvisa offline'),
        ),
        const SizedBox(height: 20),
        if (medication.professionalLeaflets.isEmpty)
          const Text(
            'Texto integral da bula ainda não disponível nesta ficha.',
          ),
        for (final leaflet in medication.professionalLeaflets) ...[
          Text(
            '${leaflet.sourceName} • ${leaflet.sourceLanguage}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Versão ${leaflet.sourceVersion}'),
          if (leaflet.relationType == 'active_ingredient_reference')
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Referência por princípio ativo. Não representa a bula Anvisa específica deste fabricante ou apresentação.',
              ),
            ),
          for (final section in leaflet.sections)
            Card(
              child: ExpansionTile(
                title: Text(section.title),
                childrenPadding: const EdgeInsets.all(16),
                children: [SelectableText(section.text)],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ],
    ),
  );
}
