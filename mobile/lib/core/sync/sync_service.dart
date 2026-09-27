import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../storage/clinical_database.dart';
import 'sync_models.dart';

enum ClinicalSyncState {
  notDownloaded,
  checking,
  downloading,
  validating,
  installing,
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
    this.sourceLabel,
    this.attempt,
    this.maxAttempts,
  });

  final ClinicalSyncState state;
  final bool hasLocalContent;
  final String? contentVersion;
  final DateTime? lastSyncAt;
  final String? message;
  final String? sourceLabel;
  final int? attempt;
  final int? maxAttempts;

  bool get isBusy =>
      state == ClinicalSyncState.checking ||
      state == ClinicalSyncState.downloading ||
      state == ClinicalSyncState.validating ||
      state == ClinicalSyncState.installing;

  bool get canRetry =>
      state == ClinicalSyncState.notDownloaded ||
      state == ClinicalSyncState.offlineAvailable ||
      state == ClinicalSyncState.unavailable;

  String get displayText {
    switch (state) {
      case ClinicalSyncState.notDownloaded:
        return 'Base clínica ainda não sincronizada';
      case ClinicalSyncState.checking:
        return 'Verificando atualização da base clínica';
      case ClinicalSyncState.downloading:
        final attemptText = attempt != null && maxAttempts != null
            ? ' • tentativa $attempt/$maxAttempts'
            : '';
        final sourceText = sourceLabel == null ? '' : ' • $sourceLabel';
        return 'Baixando base clínica$sourceText$attemptText';
      case ClinicalSyncState.validating:
        return 'Validando integridade da base clínica';
      case ClinicalSyncState.installing:
        return 'Atualizando base clínica offline';
      case ClinicalSyncState.current:
        return 'Base clínica atualizada e disponível offline';
      case ClinicalSyncState.updated:
        return 'Base clínica atualizada com sucesso e disponível offline';
      case ClinicalSyncState.offlineAvailable:
        return 'Base clínica disponível offline • atualização pendente';
      case ClinicalSyncState.unavailable:
        return 'Não foi possível baixar a base clínica';
    }
  }
}

final class SyncEndpoint {
  const SyncEndpoint({
    required this.label,
    required this.uri,
    this.supportsClinicalEtag = false,
  });

  factory SyncEndpoint.api({required String label, required Uri baseUri}) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return SyncEndpoint(
      label: label,
      uri: baseUri.replace(path: '$basePath/v1/sync/content'),
      supportsClinicalEtag: true,
    );
  }

  factory SyncEndpoint.staticRelease({
    required String label,
    required Uri uri,
  }) {
    return SyncEndpoint(label: label, uri: uri);
  }

  final String label;
  final Uri uri;
  final bool supportsClinicalEtag;
}

abstract interface class ClinicalSyncCoordinator {
  Future<ClinicalSyncStatus> localStatus();

  Future<ClinicalSyncStatus> syncIfNeeded({
    void Function(ClinicalSyncStatus status)? onStatus,
  });
}

final class SyncService implements ClinicalSyncCoordinator {
  SyncService({
    required this.endpoints,
    required this.database,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
    this.maxAttemptsPerEndpoint = 3,
    this.retryBaseDelay = const Duration(seconds: 1),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final List<SyncEndpoint> endpoints;
  final ClinicalDatabase database;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  final int maxAttemptsPerEndpoint;
  final Duration retryBaseDelay;

  @override
  Future<ClinicalSyncStatus> localStatus() async {
    final hasLocalContent = await database.hasClinicalContent();
    final contentVersion = await database.getContentVersion();
    final lastSyncAt = await database.getLastSyncAt();

    return ClinicalSyncStatus(
      state: hasLocalContent
          ? ClinicalSyncState.offlineAvailable
          : ClinicalSyncState.notDownloaded,
      hasLocalContent: hasLocalContent,
      contentVersion: contentVersion,
      lastSyncAt: lastSyncAt,
    );
  }

  @override
  Future<ClinicalSyncStatus> syncIfNeeded({
    void Function(ClinicalSyncStatus status)? onStatus,
  }) async {
    final currentVersion = await database.getContentVersion();
    final hadLocalContent = await database.hasClinicalContent();
    final lastSyncAt = await database.getLastSyncAt();

    void emit(ClinicalSyncStatus status) => onStatus?.call(status);

    emit(
      ClinicalSyncStatus(
        state: ClinicalSyncState.checking,
        hasLocalContent: hadLocalContent,
        contentVersion: currentVersion,
        lastSyncAt: lastSyncAt,
      ),
    );

    if (endpoints.isEmpty) {
      return _fallbackStatus(
        hadLocalContent: hadLocalContent,
        contentVersion: currentVersion,
        lastSyncAt: lastSyncAt,
        message: 'Nenhuma fonte de sincronização foi configurada.',
      );
    }

    var lastError = 'Nenhuma fonte de sincronização respondeu.';

    for (final endpoint in endpoints) {
      for (var attempt = 1; attempt <= maxAttemptsPerEndpoint; attempt++) {
        emit(
          ClinicalSyncStatus(
            state: ClinicalSyncState.downloading,
            hasLocalContent: hadLocalContent,
            contentVersion: currentVersion,
            lastSyncAt: lastSyncAt,
            sourceLabel: endpoint.label,
            attempt: attempt,
            maxAttempts: maxAttemptsPerEndpoint,
          ),
        );

        final headers = <String, String>{
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.acceptEncodingHeader: 'gzip',
          HttpHeaders.cacheControlHeader: 'no-cache',
        };
        if (endpoint.supportsClinicalEtag && currentVersion != null) {
          headers[HttpHeaders.ifNoneMatchHeader] = '"$currentVersion"';
        }

        try {
          final response = await _client
              .get(endpoint.uri, headers: headers)
              .timeout(timeout);

          if (response.statusCode == HttpStatus.notModified) {
            if (!hadLocalContent) {
              lastError =
                  '${endpoint.label} informou que não havia atualização, '
                  'mas este dispositivo ainda não possui uma base local.';
              break;
            }
            return ClinicalSyncStatus(
              state: ClinicalSyncState.current,
              hasLocalContent: true,
              contentVersion: currentVersion,
              lastSyncAt: lastSyncAt,
              sourceLabel: endpoint.label,
            );
          }

          if (response.statusCode != HttpStatus.ok) {
            lastError =
                '${endpoint.label}: resposta HTTP ${response.statusCode}.';
            if (_isRetryableHttp(response.statusCode) &&
                attempt < maxAttemptsPerEndpoint) {
              await _retryDelay(attempt);
              continue;
            }
            break;
          }

          emit(
            ClinicalSyncStatus(
              state: ClinicalSyncState.validating,
              hasLocalContent: hadLocalContent,
              contentVersion: currentVersion,
              lastSyncAt: lastSyncAt,
              sourceLabel: endpoint.label,
            ),
          );

          final bodyBytes = response.bodyBytes;
          final decodedBytes =
              bodyBytes.length >= 2 &&
                  bodyBytes[0] == 0x1f &&
                  bodyBytes[1] == 0x8b
              ? gzip.decode(bodyBytes)
              : bodyBytes;
          final decoded = jsonDecode(utf8.decode(decodedBytes));
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException(
              'O conteúdo baixado não é um objeto JSON válido.',
            );
          }

          final release = ClinicalSyncRelease.fromJson(decoded);

          final declaredVersion = response.headers['x-clinical-release'];
          if (declaredVersion != null &&
              declaredVersion != release.contentVersion) {
            throw const FormatException(
              'Versão declarada no cabeçalho diverge do conteúdo clínico.',
            );
          }

          if (release.medications.isEmpty ||
              release.activeIngredients.isEmpty) {
            throw const FormatException(
              'A release clínica não contém medicamentos/princípios ativos.',
            );
          }

          if (release.contentVersion == currentVersion && hadLocalContent) {
            return ClinicalSyncStatus(
              state: ClinicalSyncState.current,
              hasLocalContent: true,
              contentVersion: currentVersion,
              lastSyncAt: lastSyncAt,
              sourceLabel: endpoint.label,
            );
          }

          emit(
            ClinicalSyncStatus(
              state: ClinicalSyncState.installing,
              hasLocalContent: hadLocalContent,
              contentVersion: currentVersion,
              lastSyncAt: lastSyncAt,
              sourceLabel: endpoint.label,
            ),
          );

          await database.replaceClinicalRelease(release);

          return ClinicalSyncStatus(
            state: ClinicalSyncState.updated,
            hasLocalContent: true,
            contentVersion: release.contentVersion,
            lastSyncAt: await database.getLastSyncAt(),
            sourceLabel: endpoint.label,
          );
        } on TimeoutException {
          lastError = '${endpoint.label}: tempo limite de conexão.';
          if (attempt < maxAttemptsPerEndpoint) {
            await _retryDelay(attempt);
            continue;
          }
        } on SocketException {
          lastError = '${endpoint.label}: sem conectividade de rede.';
          if (attempt < maxAttemptsPerEndpoint) {
            await _retryDelay(attempt);
            continue;
          }
        } on http.ClientException catch (error) {
          lastError = '${endpoint.label}: falha de rede (${error.message}).';
          if (attempt < maxAttemptsPerEndpoint) {
            await _retryDelay(attempt);
            continue;
          }
        } on FormatException catch (error) {
          lastError =
              '${endpoint.label}: release rejeitada (${error.message}).';
          break;
        } catch (_) {
          lastError = '${endpoint.label}: falha inesperada de sincronização.';
          if (attempt < maxAttemptsPerEndpoint) {
            await _retryDelay(attempt);
            continue;
          }
        }
      }
    }

    return _fallbackStatus(
      hadLocalContent: hadLocalContent,
      contentVersion: currentVersion,
      lastSyncAt: lastSyncAt,
      message: lastError,
    );
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  bool _isRetryableHttp(int statusCode) {
    return statusCode == HttpStatus.requestTimeout ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  Future<void> _retryDelay(int attempt) {
    final multiplier = attempt.clamp(1, 3);
    return Future<void>.delayed(retryBaseDelay * multiplier);
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
}
