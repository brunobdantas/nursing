import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../medication/data/medication_models.dart';

final class RecentMedication {
  const RecentMedication({
    required this.id,
    required this.displayName,
    required this.genericName,
    required this.viewedAt,
  });

  factory RecentMedication.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final displayName = json['display_name'];
    final genericName = json['generic_name'];
    final viewedAtRaw = json['viewed_at'];

    if (id is! String ||
        id.trim().isEmpty ||
        displayName is! String ||
        displayName.trim().isEmpty ||
        genericName is! String ||
        genericName.trim().isEmpty ||
        viewedAtRaw is! String) {
      throw const FormatException('Invalid recent medication payload.');
    }

    final viewedAt = DateTime.tryParse(viewedAtRaw);
    if (viewedAt == null) {
      throw const FormatException('Invalid recent medication timestamp.');
    }

    return RecentMedication(
      id: id.trim(),
      displayName: displayName.trim(),
      genericName: genericName.trim(),
      viewedAt: viewedAt.toUtc(),
    );
  }

  final String id;
  final String displayName;
  final String genericName;
  final DateTime viewedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'display_name': displayName,
    'generic_name': genericName,
    'viewed_at': viewedAt.toUtc().toIso8601String(),
  };
}

abstract interface class RecentMedicationRepository {
  Future<List<RecentMedication>> loadRecent();

  Future<void> recordMedication(MedicationDetailResponse medication);
}

final class SharedPreferencesRecentMedicationRepository
    implements RecentMedicationRepository {
  SharedPreferencesRecentMedicationRepository({
    SharedPreferences? preferences,
    this.maxItems = 8,
  }) : _preferences = preferences;

  static const String storageKey = 'recent_medications_v1';

  SharedPreferences? _preferences;
  final int maxItems;

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  @override
  Future<List<RecentMedication>> loadRecent() async {
    final prefs = await _prefs();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return const <RecentMedication>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const <RecentMedication>[];
      }

      final items = <RecentMedication>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        try {
          items.add(
            RecentMedication.fromJson(
              item.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        } on FormatException {
          // One corrupt convenience entry must never block the clinical app.
        }
      }
      items.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      return List<RecentMedication>.unmodifiable(items.take(maxItems));
    } on FormatException {
      return const <RecentMedication>[];
    }
  }

  @override
  Future<void> recordMedication(MedicationDetailResponse medication) async {
    final prefs = await _prefs();
    final existing = await loadRecent();
    final now = DateTime.now().toUtc();

    final next = <RecentMedication>[
      RecentMedication(
        id: medication.id,
        displayName: medication.displayName,
        genericName: medication.genericName,
        viewedAt: now,
      ),
      ...existing.where((item) => item.id != medication.id),
    ].take(maxItems).toList(growable: false);

    await prefs.setString(
      storageKey,
      jsonEncode(next.map((item) => item.toJson()).toList(growable: false)),
    );
  }
}
