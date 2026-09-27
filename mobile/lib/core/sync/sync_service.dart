import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../storage/clinical_database.dart';
import 'sync_models.dart';

enum ClinicalSyncState {
  notDownloaded,
  syncing,
  current,
  updated,
  offlineAvailable,
  unavailable,
}

final class ClinicalSyncStatus {
  const ClinicalSyncStatus({
    required this.state,
    required this.hasLocalContent,
    this.contentVersion,
    this.lastSyncAt,
    this.message,
  });

  final ClinicalSyncState state;
  final bool hasLocalContent;
  final String? contentVersion;
  final DateTime? lastSyncAt;
  final String? message;

  String get displayText {
    switch (state) {
      case ClinicalSyncState.current:
      case ClinicalSyncState.updated:
        return 'Base clínica atualizada e disponível offline';
      case ClinicalSyncState.syncing:
        return hasLocalContent
            ? 'Base clínica offline disponível • verificando atualização'
            : 'Preparando base clínica offline';
      case ClinicalSyncState.offlineAvailable:
        return 'Base clínica disponível offline • sincronização pendente';
      case ClinicalSyncState.notDownloaded:
        return 'Base clínica ainda não sincronizada';
      case ClinicalSyncState.unavailable:
        return 'Base clínica indisponível neste dispositivo';
    }
  }
}

final class SyncService {
  SyncService({
    required Uri baseUri,
    required ClinicalDatabase database,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) : _baseUri = baseUri,
       _database = database,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _timeout = timeout;

  final Uri _baseUri;
  final ClinicalDatabase _database;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  Future<ClinicalSyncStatus> localStatus() async {
    final hasLocalContent = await _database.hasClinicalContent();
    final contentVersion = await _database.getContentVersion();
    final lastSyncAt = await _database.getLastSyncAt();

    return ClinicalSyncStatus(
      state: hasLocalContent
          ? ClinicalSyncState.offlineAvailable
          : ClinicalSyncState.notDownloaded,
      hasLocalContent: hasLocalContent,
      contentVersion: contentVersion,
      lastSyncAt: lastSyncAt,
    );
  }

  Future<ClinicalSyncStatus> syncIfNeeded() async {
    final currentVersion = await _database.getContentVersion();
    final hadLocalContent = await _database.hasClinicalContent();
    final lastSyncAt = await _database.getLastSyncAt();

    final uri = _resolve('/v1/sync/content');
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
      HttpHeaders.acceptEncodingHeader: 'gzip',
    };
    if (currentVersion != null) {
      headers[HttpHeaders.ifNoneMatchHeader] = '"$currentVersion"';
    }

    try {
      final response = await _client.get(uri, headers: headers).timeout(_timeout);

      if (response.statusCode == HttpStatus.notModified) {
        return ClinicalSyncStatus(
          state: ClinicalSyncState.current,
          hasLocalContent: hadLocalContent,
          contentVersion: currentVersion,
          lastSyncAt: lastSyncAt,
        );
      }

      if (response.statusCode != HttpStatus.ok) {
        return _fallbackStatus(
          hadLocalContent: hadLocalContent,
          contentVersion: currentVersion,
          lastSyncAt: lastSyncAt,
          message: 'Falha de sincronização HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Sync payload must be a JSON object.');
      }

      final release = ClinicalSyncRelease.fromJson(decoded);
      final headerVersion = response.headers['x-clinical-release'];
      if (headerVersion != null && headerVersion != release.contentVersion) {
        throw const FormatException(
          'Clinical release header and payload version mismatch.',
        );
      }

      final etag = response.headers[HttpHeaders.etagHeader];
      if (etag != null && etag.replaceAll('"', '') != release.contentVersion) {
        throw const FormatException(
          'Clinical release ETag and payload version mismatch.',
        );
      }

      if (release.contentVersion == currentVersion && hadLocalContent) {
        return ClinicalSyncStatus(
          state: ClinicalSyncState.current,
          hasLocalContent: true,
          contentVersion: currentVersion,
          lastSyncAt: lastSyncAt,
        );
      }

      await _database.replaceClinicalRelease(release);
      return ClinicalSyncStatus(
        state: ClinicalSyncState.updated,
        hasLocalContent: true,
        contentVersion: release.contentVersion,
        lastSyncAt: await _database.getLastSyncAt(),
      );
    } on TimeoutException {
      return _fallbackStatus(
        hadLocalContent: hadLocalContent,
        contentVersion: currentVersion,
        lastSyncAt: lastSyncAt,
        message: 'Tempo limite ao verificar atualização.',
      );
    } on SocketException {
      return _fallbackStatus(
        hadLocalContent: hadLocalContent,
        contentVersion: currentVersion,
        lastSyncAt: lastSyncAt,
        message: 'Sem conectividade para sincronização.',
      );
    } on http.ClientException {
      return _fallbackStatus(
        hadLocalContent: hadLocalContent,
        contentVersion: currentVersion,
        lastSyncAt: lastSyncAt,
        message: 'Falha de rede ao sincronizar.',
      );
    } on FormatException catch (error) {
      return _fallbackStatus(
        hadLocalContent: hadLocalContent,
        contentVersion: currentVersion,
        lastSyncAt: lastSyncAt,
        message: 'Release clínica rejeitada: ${error.message}',
      );
    } catch (_) {
      return _fallbackStatus(
        hadLocalContent: hadLocalContent,
        contentVersion: currentVersion,
        lastSyncAt: lastSyncAt,
        message: 'Não foi possível atualizar a base clínica.',
      );
    }
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  ClinicalSyncStatus _fallbackStatus({
    required bool hadLocalContent,
    required String? contentVersion,
    required DateTime? lastSyncAt,
    required String message,
  }) {
    return ClinicalSyncStatus(
      state: hadLocalContent
          ? ClinicalSyncState.offlineAvailable
          : ClinicalSyncState.unavailable,
      hasLocalContent: hadLocalContent,
      contentVersion: contentVersion,
      lastSyncAt: lastSyncAt,
      message: message,
    );
  }

  Uri _resolve(String path) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$basePath$path');
  }
}
