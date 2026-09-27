import 'package:flutter/material.dart';

@immutable
final class ClinicalSemanticColors
    extends ThemeExtension<ClinicalSemanticColors> {
  const ClinicalSemanticColors({
    required this.critical,
    required this.onCritical,
    required this.criticalContainer,
    required this.onCriticalContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.safe,
    required this.onSafe,
    required this.safeContainer,
    required this.onSafeContainer,
    required this.information,
    required this.onInformation,
    required this.informationContainer,
    required this.onInformationContainer,
  });

  final Color critical;
  final Color onCritical;
  final Color criticalContainer;
  final Color onCriticalContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color safe;
  final Color onSafe;
  final Color safeContainer;
  final Color onSafeContainer;
  final Color information;
  final Color onInformation;
  final Color informationContainer;
  final Color onInformationContainer;

  @override
  ClinicalSemanticColors copyWith({
    Color? critical,
    Color? onCritical,
    Color? criticalContainer,
    Color? onCriticalContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? safe,
    Color? onSafe,
    Color? safeContainer,
    Color? onSafeContainer,
    Color? information,
    Color? onInformation,
    Color? informationContainer,
    Color? onInformationContainer,
  }) {
    return ClinicalSemanticColors(
      critical: critical ?? this.critical,
      onCritical: onCritical ?? this.onCritical,
      criticalContainer: criticalContainer ?? this.criticalContainer,
      onCriticalContainer: onCriticalContainer ?? this.onCriticalContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      safe: safe ?? this.safe,
      onSafe: onSafe ?? this.onSafe,
      safeContainer: safeContainer ?? this.safeContainer,
      onSafeContainer: onSafeContainer ?? this.onSafeContainer,
      information: information ?? this.information,
      onInformation: onInformation ?? this.onInformation,
      informationContainer:
          informationContainer ?? this.informationContainer,
      onInformationContainer:
          onInformationContainer ?? this.onInformationContainer,
    );
  }

  @override
  ClinicalSemanticColors lerp(
    covariant ClinicalSemanticColors? other,
    double t,
  ) {
    if (other == null) {
      return this;
    }
    return ClinicalSemanticColors(
      critical: Color.lerp(critical, other.critical, t)!,
      onCritical: Color.lerp(onCritical, other.onCritical, t)!,
      criticalContainer:
          Color.lerp(criticalContainer, other.criticalContainer, t)!,
      onCriticalContainer:
          Color.lerp(onCriticalContainer, other.onCriticalContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      safe: Color.lerp(safe, other.safe, t)!,
      onSafe: Color.lerp(onSafe, other.onSafe, t)!,
      safeContainer: Color.lerp(safeContainer, other.safeContainer, t)!,
      onSafeContainer:
          Color.lerp(onSafeContainer, other.onSafeContainer, t)!,
      information: Color.lerp(information, other.information, t)!,
      onInformation:
          Color.lerp(onInformation, other.onInformation, t)!,
      informationContainer:
          Color.lerp(informationContainer, other.informationContainer, t)!,
      onInformationContainer:
          Color.lerp(onInformationContainer, other.onInformationContainer, t)!,
    );
  }
}

abstract final class ClinicalTheme {
  static const double minimumTouchTarget = 48;
  static const double primaryActionHeight = 56;
  static const double searchHeight = 64;

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF005A67),
      onPrimary: Colors.white,
      secondary: Color(0xFF466469),
      onSecondary: Colors.white,
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      surface: Color(0xFFF8FAFA),
      onSurface: Color(0xFF191C1D),
    );

    return _baseTheme(
      scheme,
      const ClinicalSemanticColors(
        critical: Color(0xFFB3261E),
        onCritical: Colors.white,
        criticalContainer: Color(0xFFF9DEDC),
        onCriticalContainer: Color(0xFF410E0B),
        warning: Color(0xFF795900),
        onWarning: Colors.white,
        warningContainer: Color(0xFFFFE08A),
        onWarningContainer: Color(0xFF271900),
        safe: Color(0xFF2E6B3C),
        onSafe: Colors.white,
        safeContainer: Color(0xFFD0E8D2),
        onSafeContainer: Color(0xFF0B2110),
        information: Color(0xFF335CA8),
        onInformation: Colors.white,
        informationContainer: Color(0xFFD9E2FF),
        onInformationContainer: Color(0xFF001944),
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF7BD0DF),
      onPrimary: Color(0xFF00363E),
      secondary: Color(0xFFB2CBD0),
      onSecondary: Color(0xFF1D3438),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: Color(0xFF101415),
      onSurface: Color(0xFFE0E3E3),
    );

    return _baseTheme(
      scheme,
      const ClinicalSemanticColors(
        critical: Color(0xFFFFB4AB),
        onCritical: Color(0xFF690005),
        criticalContainer: Color(0xFF93000A),
        onCriticalContainer: Color(0xFFFFDAD6),
        warning: Color(0xFFFFC84A),
        onWarning: Color(0xFF3F2E00),
        warningContainer: Color(0xFF5A4300),
        onWarningContainer: Color(0xFFFFE08A),
        safe: Color(0xFFA6D7AD),
        onSafe: Color(0xFF10391C),
        safeContainer: Color(0xFF1F512B),
        onSafeContainer: Color(0xFFC1F3C8),
        information: Color(0xFFADC6FF),
        onInformation: Color(0xFF002E69),
        informationContainer: Color(0xFF174584),
        onInformationContainer: Color(0xFFD9E2FF),
      ),
    );
  }

  static ThemeData _baseTheme(
    ColorScheme scheme,
    ClinicalSemanticColors semanticColors,
  ) {
    final base = ThemeData(
      colorScheme: scheme,
      brightness: scheme.brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[semanticColors],
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 17,
          height: 1.35,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.primary,
            width: 2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(minimumTouchTarget, primaryActionHeight),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(minimumTouchTarget, primaryActionHeight),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(minimumTouchTarget, minimumTouchTarget),
          ),
        ),
      ),
    );
  }
}
