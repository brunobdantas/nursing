import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'medication_models.dart';

enum MedicationRepositoryErrorKind {
  network,
  timeout,
  badResponse,
  invalidPayload,
  notFound,
  clinicalDataIntegrity,
  unknown,
}

final class MedicationRepositoryException implements Exception {
  const MedicationRepositoryException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final MedicationRepositoryErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'MedicationRepositoryException($kind): $message';
}

abstract interface class MedicationRepository {
  Future<MedicationSearchResponse> searchMedications(String query);

  Future<MedicationDetailResponse> getMedicationDetail(String id);
}

final class HttpMedicationRepository implements MedicationRepository {
  HttpMedicationRepository({
    required this.baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri baseUri;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  @override
  Future<MedicationSearchResponse> searchMedications(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      return MedicationSearchResponse(
        query: normalizedQuery,
        items: const <MedicationSearchResult>[],
        returned: 0,
      );
    }

    final uri = _resolve(
      '/v1/medications/search',
      queryParameters: <String, String>{'q': normalizedQuery},
    );
    final json = await _getJson(uri);
    return _parse(
      () => MedicationSearchResponse.fromJson(json),
      operation: 'busca de medicamentos',
    );
  }

  @override
  Future<MedicationDetailResponse> getMedicationDetail(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw const MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.invalidPayload,
        message: 'Identificador de medicamento inválido.',
      );
    }

    final uri = _resolve('/v1/medications/$normalizedId');
    final json = await _getJson(uri);
    return _parse(
      () => MedicationDetailResponse.fromJson(json),
      operation: 'detalhes do medicamento',
    );
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Uri _resolve(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(
      path: '$basePath$path',
      queryParameters: queryParameters,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: const <String, String>{
              HttpHeaders.acceptHeader: 'application/json',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 404) {
        throw const MedicationRepositoryException(
          kind: MedicationRepositoryErrorKind.notFound,
          message: 'Medicamento não encontrado.',
          statusCode: 404,
        );
      }

      if (response.statusCode == 503) {
        throw const MedicationRepositoryException(
          kind: MedicationRepositoryErrorKind.clinicalDataIntegrity,
          message:
              'Os dados clínicos deste medicamento estão temporariamente '
              'indisponíveis para uso seguro.',
          statusCode: 503,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MedicationRepositoryException(
          kind: MedicationRepositoryErrorKind.badResponse,
          message:
              'O serviço retornou uma resposta inesperada '
              '(${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const MedicationRepositoryException(
          kind: MedicationRepositoryErrorKind.invalidPayload,
          message: 'A API retornou um formato de dados inválido.',
        );
      }
      return decoded;
    } on MedicationRepositoryException {
      rethrow;
    } on TimeoutException {
      throw const MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.timeout,
        message: 'A consulta excedeu o tempo limite. Tente novamente.',
      );
    } on http.ClientException {
      throw const MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.network,
        message: 'Não foi possível conectar ao serviço de medicamentos.',
      );
    } on SocketException {
      throw const MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.network,
        message: 'Sem conexão de rede disponível.',
      );
    } on FormatException {
      throw const MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.invalidPayload,
        message: 'A API retornou dados inválidos.',
      );
    } catch (_) {
      throw const MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.unknown,
        message: 'Não foi possível concluir a consulta com segurança.',
      );
    }
  }

  T _parse<T>(
    T Function() parser, {
    required String operation,
  }) {
    try {
      return parser();
    } on FormatException {
      throw MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.invalidPayload,
        message:
            'Os dados recebidos na $operation não passaram nas validações '
            'de segurança.',
      );
    } catch (_) {
      throw MedicationRepositoryException(
        kind: MedicationRepositoryErrorKind.invalidPayload,
        message:
            'Os dados recebidos na $operation não puderam ser validados.',
      );
    }
  }
}
