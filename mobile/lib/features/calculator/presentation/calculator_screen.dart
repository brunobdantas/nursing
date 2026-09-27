import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/calculation/calculation_core.dart';
import '../../../theme/clinical_theme.dart';
import '../../medication/data/medication_models.dart';
import '../../medication/data/medication_repository.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({
    required this.medicationId,
    required this.presentationId,
    required this.repository,
    super.key,
  });

  final String medicationId;
  final String presentationId;
  final MedicationRepository repository;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final TextEditingController _doseController = TextEditingController();
  MedicationDetailResponse? _medication;
  PresentationDetail? _presentation;
  CalculationResult? _result;
  String? _inputError;
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _doseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _result = null;
    });

    try {
      final medication = await widget.repository.getMedicationDetail(
        widget.medicationId,
      );
      final presentation = medication.presentationById(widget.presentationId);

      if (!presentation.calculationReady ||
          presentation.concentration == null) {
        throw const MedicationRepositoryException(
          kind: MedicationRepositoryErrorKind.clinicalDataIntegrity,
          message:
              'Esta apresentação não está validada para cálculo automático.',
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _medication = medication;
        _presentation = presentation;
        _loading = false;
      });
    } on MedicationRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.message;
        _loading = false;
      });
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError =
            'A apresentação selecionada não pertence a este medicamento.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = 'Não foi possível preparar a calculadora com segurança.';
        _loading = false;
      });
    }
  }

  void _calculate() {
    final presentation = _presentation;
    final concentration = presentation?.concentration;
    if (presentation == null || concentration == null) {
      return;
    }

    final rawDose = _doseController.text.trim().replaceAll(',', '.');
    Decimal prescribedDose;
    try {
      prescribedDose = Decimal.parse(rawDose);
    } on FormatException {
      setState(() {
        _inputError = 'Informe uma dose numérica válida.';
        _result = null;
      });
      return;
    }

    final result = CalculationCore.mgToMl(
      MgToMlInput(
        prescribedDose: prescribedDose,
        doseUnit: 'mg',
        concentrationMass: concentration.numeratorValue,
        concentrationMassUnit: concentration.numeratorUnit,
        concentrationVolume: concentration.denominatorValue,
        concentrationVolumeUnit: concentration.denominatorUnit,
        calculationReady: presentation.calculationReady,
      ),
    );

    setState(() {
      _inputError = null;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final medication = _medication;
    final presentation = _presentation;

    return Scaffold(
      appBar: AppBar(title: const Text('Calcular dose')),
      bottomNavigationBar:
          medication == null || presentation == null || _loadError != null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                key: const ValueKey<String>('run-dose-calculation'),
                onPressed: _calculate,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('CALCULAR'),
              ),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? _CalculatorLoadError(message: _loadError!, onRetry: _load)
            : medication == null || presentation == null
            ? const SizedBox.shrink()
            : _CalculatorBody(
                medication: medication,
                presentation: presentation,
                doseController: _doseController,
                inputError: _inputError,
                result: _result,
                onDoseChanged: () {
                  if (_result != null || _inputError != null) {
                    setState(() {
                      _result = null;
                      _inputError = null;
                    });
                  }
                },
              ),
      ),
    );
  }
}

class _CalculatorBody extends StatelessWidget {
  const _CalculatorBody({
    required this.medication,
    required this.presentation,
    required this.doseController,
    required this.inputError,
    required this.result,
    required this.onDoseChanged,
  });

  final MedicationDetailResponse medication;
  final PresentationDetail presentation;
  final TextEditingController doseController;
  final String? inputError;
  final CalculationResult? result;
  final VoidCallback onDoseChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concentration = presentation.concentration!;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(medication.displayName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              presentation.description,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            _PresentationDataCard(
              presentation: presentation,
              concentration: concentration,
            ),
            const SizedBox(height: 24),
            Text('Dose prescrita', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Digite exatamente o valor prescrito. Esta calculadora V1 aceita '
              'dose em mg e não realiza conversão implícita de unidades.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('prescribed-dose-field'),
              controller: doseController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const <TextInputFormatter>[
                _ClinicalDecimalInputFormatter(),
              ],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Dose prescrita',
                suffixText: 'mg',
                errorText: inputError,
              ),
              onChanged: (_) => onDoseChanged(),
            ),
            const SizedBox(height: 24),
            if (result != null) _CalculationOutcome(result: result!),
          ],
        ),
      ),
    );
  }
}

class _PresentationDataCard extends StatelessWidget {
  const _PresentationDataCard({
    required this.presentation,
    required this.concentration,
  });

  final PresentationDetail presentation;
  final ConcentrationData concentration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: semantic.informationContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Apresentação selecionada',
            style: theme.textTheme.titleMedium?.copyWith(
              color: semantic.onInformationContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            presentation.description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: semantic.onInformationContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Concentração estruturada: ${concentration.display}',
            style: TextStyle(color: semantic.onInformationContainer),
          ),
          const SizedBox(height: 4),
          Text(
            'Via: ${presentation.routeLabel}',
            style: TextStyle(color: semantic.onInformationContainer),
          ),
        ],
      ),
    );
  }
}

class _CalculationOutcome extends StatelessWidget {
  const _CalculationOutcome({required this.result});

  final CalculationResult result;

  @override
  Widget build(BuildContext context) {
    if (!result.isSuccess) {
      return _CalculationFailure(result: result);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CalculationResultCard(result: result),
        const SizedBox(height: 16),
        _CalculationMemoryCard(result: result),
      ],
    );
  }
}

class _CalculationResultCard extends StatelessWidget {
  const _CalculationResultCard({required this.result});

  final CalculationResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;
    final display = '${result.resultValue} ${result.resultUnit}';

    return Semantics(
      liveRegion: true,
      label: 'Resultado calculado $display',
      child: Container(
        key: const ValueKey<String>('calculation-result-card'),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: semantic.safeContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: semantic.safe, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resultado',
              style: theme.textTheme.titleMedium?.copyWith(
                color: semantic.onSafeContainer,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                display,
                maxLines: 1,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: semantic.onSafeContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalculationMemoryCard extends StatelessWidget {
  const _CalculationMemoryCard({required this.result});

  final CalculationResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey<String>('calculation-memory-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Memória de Cálculo', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final line in result.calculationMemory) ...[
            SelectableText(
              line,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
          ],
          const Divider(),
          const SizedBox(height: 6),
          for (final alert in result.dimensionalAlerts) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(alert)),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CalculationFailure extends StatelessWidget {
  const _CalculationFailure({required this.result});

  final CalculationResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: semantic.criticalContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block_rounded, color: semantic.onCriticalContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              result.error?.message ?? 'Cálculo bloqueado por segurança.',
              style: TextStyle(
                color: semantic.onCriticalContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalculatorLoadError extends StatelessWidget {
  const _CalculatorLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: semantic.criticalContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: semantic.onCriticalContainer),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ClinicalDecimalInputFormatter extends TextInputFormatter {
  const _ClinicalDecimalInputFormatter();

  static final RegExp _pattern = RegExp(r'^\d{0,12}([\.,]\d{0,8})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty || _pattern.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}
