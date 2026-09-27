import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/calculation/calculation_core.dart';
import '../../../theme/clinical_theme.dart';

class InfusionCalculatorScreen extends StatefulWidget {
  const InfusionCalculatorScreen({super.key});

  @override
  State<InfusionCalculatorScreen> createState() =>
      _InfusionCalculatorScreenState();
}

class _InfusionCalculatorScreenState extends State<InfusionCalculatorScreen> {
  final TextEditingController _volumeController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  TimeUnit _timeUnit = TimeUnit.hours;
  CalculationResult? _result;
  String? _inputError;

  @override
  void dispose() {
    _volumeController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _clearOutcome() {
    if (_result != null || _inputError != null) {
      setState(() {
        _result = null;
        _inputError = null;
      });
    }
  }

  void _calculate() {
    final parsed = _parseInputs(
      volume: _volumeController.text,
      duration: _timeController.text,
    );
    if (parsed == null) {
      setState(() {
        _result = null;
        _inputError = 'Informe volume e tempo com valores numéricos válidos.';
      });
      return;
    }

    final result = CalculationCore.infusionMlPerHour(
      InfusionInput(
        totalVolume: parsed.$1,
        volumeUnit: 'mL',
        duration: parsed.$2,
        durationUnit: _timeUnit,
      ),
    );

    setState(() {
      _inputError = null;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _CalculatorScaffold(
      title: 'Infusão contínua',
      calculateKey: const ValueKey<String>('run-infusion-calculation'),
      onCalculate: _calculate,
      child: _FluidInputBody(
        heading: 'Velocidade de infusão',
        supportingText:
            'Informe o volume total em mL e o tempo. O resultado é calculado '
            'em mL/h sem arredondamento implícito.',
        volumeController: _volumeController,
        timeController: _timeController,
        timeUnit: _timeUnit,
        inputError: _inputError,
        onChanged: _clearOutcome,
        onTimeUnitChanged: (unit) {
          setState(() {
            _timeUnit = unit;
            _result = null;
            _inputError = null;
          });
        },
        outcome: _result == null
            ? null
            : _SingleCalculationOutcome(result: _result!),
      ),
    );
  }
}

class DropsCalculatorScreen extends StatefulWidget {
  const DropsCalculatorScreen({super.key});

  @override
  State<DropsCalculatorScreen> createState() => _DropsCalculatorScreenState();
}

class _DropsCalculatorScreenState extends State<DropsCalculatorScreen> {
  final TextEditingController _volumeController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  TimeUnit _timeUnit = TimeUnit.hours;
  DropsCalculationResult? _result;
  String? _inputError;

  @override
  void dispose() {
    _volumeController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _clearOutcome() {
    if (_result != null || _inputError != null) {
      setState(() {
        _result = null;
        _inputError = null;
      });
    }
  }

  void _calculate() {
    final parsed = _parseInputs(
      volume: _volumeController.text,
      duration: _timeController.text,
    );
    if (parsed == null) {
      setState(() {
        _result = null;
        _inputError = 'Informe volume e tempo com valores numéricos válidos.';
      });
      return;
    }

    final result = CalculationCore.dropsPerMinute(
      DropsInput(
        totalVolume: parsed.$1,
        volumeUnit: 'mL',
        duration: parsed.$2,
        durationUnit: _timeUnit,
      ),
    );

    setState(() {
      _inputError = null;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _CalculatorScaffold(
      title: 'Gotejamento',
      calculateKey: const ValueKey<String>('run-drops-calculation'),
      onCalculate: _calculate,
      child: _FluidInputBody(
        heading: 'Gotas e microgotas por minuto',
        supportingText:
            'Macrogotas considera equipo de 20 gotas/mL e microgotas, '
            '60 microgotas/mL. Confirme o fator do equipo antes de usar.',
        volumeController: _volumeController,
        timeController: _timeController,
        timeUnit: _timeUnit,
        inputError: _inputError,
        onChanged: _clearOutcome,
        onTimeUnitChanged: (unit) {
          setState(() {
            _timeUnit = unit;
            _result = null;
            _inputError = null;
          });
        },
        outcome: _result == null
            ? null
            : _DropsCalculationOutcome(result: _result!),
      ),
    );
  }
}

class _CalculatorScaffold extends StatelessWidget {
  const _CalculatorScaffold({
    required this.title,
    required this.calculateKey,
    required this.onCalculate,
    required this.child,
  });

  final String title;
  final Key calculateKey;
  final VoidCallback onCalculate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          key: calculateKey,
          onPressed: onCalculate,
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('CALCULAR'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FluidInputBody extends StatelessWidget {
  const _FluidInputBody({
    required this.heading,
    required this.supportingText,
    required this.volumeController,
    required this.timeController,
    required this.timeUnit,
    required this.inputError,
    required this.onChanged,
    required this.onTimeUnitChanged,
    required this.outcome,
  });

  final String heading;
  final String supportingText;
  final TextEditingController volumeController;
  final TextEditingController timeController;
  final TimeUnit timeUnit;
  final String? inputError;
  final VoidCallback onChanged;
  final ValueChanged<TimeUnit> onTimeUnitChanged;
  final Widget? outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(heading, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(supportingText, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 24),
        TextField(
          key: const ValueKey<String>('fluid-volume-field'),
          controller: volumeController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const <TextInputFormatter>[
            _ClinicalDecimalInputFormatter(),
          ],
          decoration: InputDecoration(
            labelText: 'Volume total',
            suffixText: 'mL',
            errorText: inputError,
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey<String>('fluid-time-field'),
          controller: timeController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const <TextInputFormatter>[
            _ClinicalDecimalInputFormatter(),
          ],
          decoration: const InputDecoration(labelText: 'Tempo'),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Unidade do tempo',
          child: SegmentedButton<TimeUnit>(
            segments: const <ButtonSegment<TimeUnit>>[
              ButtonSegment<TimeUnit>(
                value: TimeUnit.hours,
                label: Text('Horas'),
              ),
              ButtonSegment<TimeUnit>(
                value: TimeUnit.minutes,
                label: Text('Minutos'),
              ),
            ],
            selected: <TimeUnit>{timeUnit},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              onTimeUnitChanged(selection.single);
            },
          ),
        ),
        if (outcome != null) ...[const SizedBox(height: 24), outcome!],
      ],
    );
  }
}

class _SingleCalculationOutcome extends StatelessWidget {
  const _SingleCalculationOutcome({required this.result});

  final CalculationResult result;

  @override
  Widget build(BuildContext context) {
    if (!result.isSuccess) {
      return _FailureCard(message: result.error?.message);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResultCard(
          label: 'Velocidade',
          display: '${result.resultValue} ${result.resultUnit}',
        ),
        const SizedBox(height: 16),
        _MemoryCard(
          memory: result.calculationMemory,
          alerts: result.dimensionalAlerts,
        ),
      ],
    );
  }
}

class _DropsCalculationOutcome extends StatelessWidget {
  const _DropsCalculationOutcome({required this.result});

  final DropsCalculationResult result;

  @override
  Widget build(BuildContext context) {
    if (!result.isSuccess) {
      return _FailureCard(message: result.error?.message);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResultCard(
          label: 'Macrogotas',
          display: '${result.dropsPerMinute} gotas/min',
        ),
        const SizedBox(height: 12),
        _ResultCard(
          label: 'Microgotas',
          display: '${result.microdropsPerMinute} microgotas/min',
        ),
        const SizedBox(height: 16),
        _MemoryCard(
          memory: result.calculationMemory,
          alerts: result.dimensionalAlerts,
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.label, required this.display});

  final String label;
  final String display;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<ClinicalSemanticColors>()!;

    return Container(
      key: ValueKey<String>('fluid-result-$label'),
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
            label,
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
              style: theme.textTheme.headlineMedium?.copyWith(
                color: semantic.onSafeContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory, required this.alerts});

  final List<String> memory;
  final List<String> alerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
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
          for (final line in memory) ...[
            SelectableText(
              line,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (alerts.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 6),
            for (final alert in alerts) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(alert)),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.message});

  final String? message;

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
              message ?? 'Cálculo bloqueado por segurança.',
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

(Decimal, Decimal)? _parseInputs({
  required String volume,
  required String duration,
}) {
  try {
    final parsedVolume = Decimal.parse(volume.trim().replaceAll(',', '.'));
    final parsedDuration = Decimal.parse(duration.trim().replaceAll(',', '.'));
    return (parsedVolume, parsedDuration);
  } on FormatException {
    return null;
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
