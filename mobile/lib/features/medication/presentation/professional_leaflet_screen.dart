import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/medication_models.dart';

class ProfessionalLeafletScreen extends StatefulWidget {
  const ProfessionalLeafletScreen({
    required this.medication,
    super.key,
  });

  final MedicationDetailResponse medication;

  @override
  State<ProfessionalLeafletScreen> createState() =>
      _ProfessionalLeafletScreenState();
}

class _ProfessionalLeafletScreenState extends State<ProfessionalLeafletScreen> {
  File? _pdfFile;
  WebViewController? _webViewController;
  BytesBuilder _incomingBytes = BytesBuilder(copy: false);
  int _receivedBytes = 0;
  int? _expectedBytes;
  String _statusMessage = 'Preparando a bula profissional...';
  String? _errorMessage;
  bool _resolverInjected = false;
  bool _busy = true;

  String? get _registration {
    final raw = widget.medication.anvisaRegistrationNumber;
    if (raw == null) {
      return null;
    }
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8 ? digits : null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<File?> _cacheFile() async {
    final registration = _registration;
    if (registration == null) {
      return null;
    }
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'professional_leaflets'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'anvisa_' + registration + '.pdf'));
  }

  Future<void> _start({bool forceRefresh = false}) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
      _statusMessage = forceRefresh
          ? 'Atualizando a bula profissional na Anvisa...'
          : 'Verificando a bula profissional armazenada...';
      _receivedBytes = 0;
      _expectedBytes = null;
      _incomingBytes = BytesBuilder(copy: false);
      _resolverInjected = false;
      _webViewController = null;
    });

    final cache = await _cacheFile();
    if (cache == null) {
      _fail(
        'Este medicamento não possui um número de registro Anvisa válido '
        'para localizar a bula profissional.',
      );
      return;
    }

    if (forceRefresh && await cache.exists()) {
      await cache.delete();
    }

    if (!forceRefresh && await _isValidCachedPdf(cache)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pdfFile = cache;
        _busy = false;
        _statusMessage = 'Bula profissional disponível offline.';
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _pdfFile = null;
      _statusMessage = 'Conectando ao Bulário Eletrônico da Anvisa...';
    });
    _createResolver();
  }

  Future<bool> _isValidCachedPdf(File file) async {
    if (!await file.exists()) {
      return false;
    }
    try {
      final bytes = await file.readAsBytes();
      return _looksLikePdf(bytes);
    } catch (_) {
      return false;
    }
  }

  void _createResolver() {
    final registration = _registration;
    if (registration == null) {
      _fail('Número de registro Anvisa indisponível.');
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'LeafletBridge',
        onMessageReceived: (message) {
          unawaited(_handleBridgeMessage(message.message));
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (_resolverInjected) {
              return;
            }
            _resolverInjected = true;
            unawaited(_injectResolver(registration));
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              _fail(
                'Não foi possível iniciar a consulta à Anvisa. '
                'Verifique a conexão e tente novamente.',
              );
            }
          },
        ),
      );

    if (!mounted) {
      return;
    }
    setState(() {
      _webViewController = controller;
    });

    unawaited(
      controller.loadRequest(
        Uri.parse('https://consultas.anvisa.gov.br/#/bulario/'),
      ),
    );
  }

  Future<void> _injectResolver(String registration) async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }

    final registrationLiteral = jsonEncode(registration);
    final script = '''
(async () => {
  const registration = $registrationLiteral;
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const bridge = (value) => {
    LeafletBridge.postMessage(JSON.stringify(value));
  };

  const bytesToBase64 = (bytes) => {
    let binary = '';
    const step = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += step) {
      const part = bytes.subarray(offset, Math.min(bytes.length, offset + step));
      binary += String.fromCharCode.apply(null, part);
    }
    return btoa(binary);
  };

  try {
    await sleep(2500);

    const params = new URLSearchParams({
      column: '',
      count: '10',
      'filter[numeroRegistro]': registration,
      order: 'asc',
      page: '1',
    });

    let item = null;
    let searchError = '';
    for (let attempt = 1; attempt <= 6; attempt += 1) {
      const response = await fetch(
        '/api/consulta/bulario?' + params.toString(),
        {
          headers: { Accept: 'application/json, text/plain, */*' },
          credentials: 'include',
        },
      );
      if (response.ok) {
        const payload = await response.json();
        item = payload.content && payload.content.length > 0
          ? payload.content[0]
          : null;
        if (item) {
          break;
        }
        searchError = 'Registro sem bula profissional publicada.';
      } else {
        searchError = 'Consulta Anvisa HTTP ' + response.status;
      }
      await sleep(800 * attempt);
    }

    if (!item) {
      throw new Error(searchError || 'Bula profissional não localizada.');
    }

    const token = item.idBulaProfissionalProtegido;
    if (!token) {
      throw new Error('A Anvisa não retornou a bula profissional deste registro.');
    }

    bridge({
      type: 'metadata',
      product: item.nomeProduto || null,
      updatedAt: item.dataAtualizacao || item.data || null,
    });

    // The protected token can be generated with nbf roughly one second ahead
    // of the caller clock. Waiting avoids ANVISA PrematureJwtException.
    await sleep(2200);

    let pdfBytes = null;
    let lastError = '';
    for (let attempt = 1; attempt <= 6; attempt += 1) {
      const response = await fetch(
        '/api/consulta/medicamentos/arquivo/bula/parecer/' +
          encodeURIComponent(token) +
          '/',
        {
          headers: { Accept: 'application/pdf, application/octet-stream, */*' },
          credentials: 'include',
        },
      );

      const buffer = await response.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      const isPdf =
        bytes.length >= 4 &&
        bytes[0] === 0x25 &&
        bytes[1] === 0x50 &&
        bytes[2] === 0x44 &&
        bytes[3] === 0x46;

      if (response.ok && isPdf) {
        pdfBytes = bytes;
        break;
      }

      let detail = '';
      try {
        detail = new TextDecoder().decode(bytes).slice(0, 300);
      } catch (_) {}
      lastError =
        'Download Anvisa HTTP ' + response.status +
        (detail ? ': ' + detail : '');
      await sleep(1000 * attempt);
    }

    if (!pdfBytes) {
      throw new Error(lastError || 'A Anvisa não entregou o PDF da bula.');
    }

    bridge({ type: 'start', size: pdfBytes.length });

    const rawChunkSize = 48 * 1024;
    for (let offset = 0; offset < pdfBytes.length; offset += rawChunkSize) {
      const part = pdfBytes.subarray(
        offset,
        Math.min(pdfBytes.length, offset + rawChunkSize),
      );
      bridge({
        type: 'chunk',
        data: bytesToBase64(part),
      });
      await sleep(2);
    }

    bridge({ type: 'done' });
  } catch (error) {
    bridge({
      type: 'error',
      message: String(error && error.message ? error.message : error),
    });
  }
})();
''';

    try {
      await controller.runJavaScript(script);
    } catch (_) {
      _fail(
        'Não foi possível executar a consulta segura ao Bulário da Anvisa.',
      );
    }
  }

  Future<void> _handleBridgeMessage(String rawMessage) async {
    if (!mounted) {
      return;
    }

    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map) {
        throw const FormatException();
      }
      message = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } catch (_) {
      _fail('A resposta recebida da Anvisa é inválida.');
      return;
    }

    switch (message['type']) {
      case 'metadata':
        if (!mounted) {
          return;
        }
        setState(() {
          _statusMessage = 'Bula localizada. Preparando o conteúdo oficial...';
        });
        return;

      case 'start':
        final size = message['size'];
        if (size is! num || size <= 0) {
          _fail('A Anvisa informou um tamanho de bula inválido.');
          return;
        }
        _incomingBytes = BytesBuilder(copy: false);
        _receivedBytes = 0;
        _expectedBytes = size.toInt();
        if (mounted) {
          setState(() {
            _statusMessage = 'Baixando a bula profissional oficial...';
          });
        }
        return;

      case 'chunk':
        final encoded = message['data'];
        if (encoded is! String || encoded.isEmpty) {
          _fail('Um trecho da bula recebido da Anvisa é inválido.');
          return;
        }
        try {
          final bytes = base64Decode(encoded);
          _incomingBytes.add(bytes);
          _receivedBytes += bytes.length;
          if (mounted) {
            setState(() {});
          }
        } catch (_) {
          _fail('Não foi possível reconstruir a bula recebida da Anvisa.');
        }
        return;

      case 'done':
        final bytes = _incomingBytes.takeBytes();
        final expected = _expectedBytes;
        if (expected != null && bytes.length != expected) {
          _fail(
            'O download da bula ficou incompleto. '
            'Tente novamente com uma conexão estável.',
          );
          return;
        }
        if (!_looksLikePdf(bytes)) {
          _fail('O conteúdo devolvido pela Anvisa não é uma bula PDF válida.');
          return;
        }

        final file = await _cacheFile();
        if (file == null) {
          _fail('Não foi possível preparar o armazenamento local da bula.');
          return;
        }

        try {
          await file.writeAsBytes(bytes, flush: true);
        } catch (_) {
          _fail('Não foi possível salvar a bula no aparelho.');
          return;
        }

        if (!mounted) {
          return;
        }
        setState(() {
          _pdfFile = file;
          _webViewController = null;
          _busy = false;
          _statusMessage = 'Bula profissional disponível offline.';
          _receivedBytes = bytes.length;
          _expectedBytes = bytes.length;
        });
        return;

      case 'error':
        final detail = message['message'];
        _fail(
          detail is String && detail.trim().isNotEmpty
              ? 'Não foi possível obter a bula profissional. ' + detail.trim()
              : 'Não foi possível obter a bula profissional na Anvisa.',
        );
        return;
    }
  }

  bool _looksLikePdf(Uint8List bytes) {
    return bytes.length > 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _errorMessage = message;
      _busy = false;
      _webViewController = null;
    });
  }

  Future<void> _refresh() async {
    await _start(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final pdfFile = _pdfFile;
    final controller = _webViewController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bula profissional'),
        actions: [
          if (pdfFile != null)
            IconButton(
              tooltip: 'Atualizar bula na Anvisa',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: pdfFile != null
            ? Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Row(
                      children: [
                        Icon(Icons.offline_pin_outlined, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bula oficial da Anvisa armazenada no aparelho '
                            'e disponível para consulta offline.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PdfViewer.file(
                      pdfFile.path,
                      key: ValueKey<String>(pdfFile.path),
                    ),
                  ),
                ],
              )
            : _errorMessage != null
            ? _LeafletErrorState(
                message: _errorMessage!,
                onRetry: () => unawaited(_start()),
              )
            : Stack(
                children: [
                  _LeafletLoadingState(
                    message: _statusMessage,
                    progress: _expectedBytes == null
                        ? null
                        : (_receivedBytes / _expectedBytes!).clamp(0.0, 1.0),
                  ),
                  if (controller != null)
                    Positioned(
                      left: 0,
                      top: 0,
                      width: 2,
                      height: 2,
                      child: Opacity(
                        opacity: 0.01,
                        child: WebViewWidget(controller: controller),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _LeafletLoadingState extends StatelessWidget {
  const _LeafletLoadingState({
    required this.message,
    required this.progress,
  });

  final String message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final percentage = progress == null ? null : (progress! * 100).round();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(value: progress),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (percentage != null) ...[
                const SizedBox(height: 8),
                Text('$percentage%'),
              ],
              const SizedBox(height: 12),
              Text(
                'A primeira consulta requer internet. Depois do download, '
                'a bula fica armazenada no aplicativo.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeafletErrorState extends StatelessWidget {
  const _LeafletErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
