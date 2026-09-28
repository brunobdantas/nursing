import 'dart:async';
import 'dart:io';

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
  File? _cachedPdf;
  WebViewController? _controller;
  bool _loading = true;
  bool _usingFallback = false;
  String? _error;

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
    unawaited(_initialize());
  }

  Future<File?> _cacheFile() async {
    final registration = _registration;
    if (registration == null) {
      return null;
    }
    final root = await getApplicationSupportDirectory();
    return File(
      p.join(
        root.path,
        'professional_leaflets',
        'anvisa_' + registration + '.pdf',
      ),
    );
  }

  Future<void> _initialize() async {
    final cache = await _cacheFile();
    if (cache != null && await _isPdf(cache)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cachedPdf = cache;
        _loading = false;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    _openOfficialSource();
  }

  Future<bool> _isPdf(File file) async {
    if (!await file.exists()) {
      return false;
    }
    try {
      final bytes = await file.openRead(0, 4).fold<List<int>>(
        <int>[],
        (buffer, data) => buffer..addAll(data),
      );
      return bytes.length >= 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46;
    } catch (_) {
      return false;
    }
  }

  void _openOfficialSource() {
    final configuredUrl = widget.medication.professionalLeafletUrl?.trim();
    final configuredUri = configuredUrl == null
        ? null
        : Uri.tryParse(configuredUrl);
    final canUseConfigured =
        configuredUri != null &&
        (configuredUri.scheme == 'https' || configuredUri.scheme == 'http');

    final initialUri = canUseConfigured
        ? configuredUri
        : Uri.parse('https://consultas.anvisa.gov.br/#/bulario/');

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _loading = false);
            }
          },
          onWebResourceError: (error) {
            if (!(error.isForMainFrame ?? true)) {
              return;
            }
            if (!_usingFallback) {
              _openBularioFallback();
              return;
            }
            if (mounted) {
              setState(() {
                _loading = false;
                _error =
                    'A fonte oficial da Anvisa não respondeu. '
                    'Tente novamente quando houver conexão.';
              });
            }
          },
        ),
      );

    setState(() {
      _controller = controller;
      _loading = true;
      _error = null;
    });

    unawaited(controller.loadRequest(initialUri));
  }

  void _openBularioFallback() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _usingFallback = true;
    unawaited(
      controller.loadRequest(
        Uri.parse('https://consultas.anvisa.gov.br/#/bulario/'),
      ),
    );
  }

  void _reload() {
    final controller = _controller;
    if (controller == null) {
      _openOfficialSource();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(controller.reload());
  }

  @override
  Widget build(BuildContext context) {
    final cachedPdf = _cachedPdf;
    final controller = _controller;
    final registration = _registration;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bula profissional'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: cachedPdf != null
                ? () {
                    setState(() => _cachedPdf = null);
                    _openOfficialSource();
                  }
                : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: cachedPdf != null
            ? Column(
                children: [
                  const _SourceBanner(
                    icon: Icons.offline_pin_outlined,
                    text:
                        'Bula oficial previamente armazenada neste aparelho.',
                  ),
                  Expanded(
                    child: PdfViewer.file(
                      cachedPdf.path,
                      key: ValueKey<String>(cachedPdf.path),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _SourceBanner(
                    icon: Icons.verified_outlined,
                    text: registration == null
                        ? 'Fonte oficial: Bulário Eletrônico da Anvisa.'
                        : 'Fonte oficial: Bulário Eletrônico da Anvisa. '
                              'Registro: ' +
                              registration +
                              '.',
                  ),
                  if (_usingFallback)
                    const _SourceBanner(
                      icon: Icons.info_outline_rounded,
                      text:
                          'A chamada automática da bula falhou e foi '
                          'substituída pela navegação oficial da Anvisa '
                          'dentro do aplicativo. Pesquise pelo nome ou '
                          'registro informado acima.',
                    ),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (controller != null)
                    Expanded(child: WebViewWidget(controller: controller))
                  else
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
      ),
    );
  }
}

class _SourceBanner extends StatelessWidget {
  const _SourceBanner({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
