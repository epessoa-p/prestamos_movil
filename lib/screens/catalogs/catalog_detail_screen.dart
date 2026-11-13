import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';
import '../../utils/color_utils.dart';
import '../modules/catalogos_screen.dart' show CatalogStatusChip;
import '../widgets/file_ready_sheet.dart';
import 'catalog_form_screen.dart';

/// Detalle de un catálogo: enlace público (copiar / compartir / abrir), PDF con fotos y acciones.
class CatalogDetailScreen extends StatefulWidget {
  const CatalogDetailScreen({super.key, required this.api, required this.logger, required this.catalogId});

  final ApiService api;
  final ErrorLogService logger;
  final int catalogId;

  @override
  State<CatalogDetailScreen> createState() => _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends State<CatalogDetailScreen> {
  final _money = Currency.formatter();
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get _catalog => _data['catalog'] is Map ? Map<String, dynamic>.from(_data['catalog']) : {};
  Map<String, dynamic> get _abilities => _data['abilities'] is Map ? Map<String, dynamic>.from(_data['abilities']) : {};
  String get _url => '${_data['public_url'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.catalogDetail(widget.catalogId);
      if (mounted) setState(() => _data = data);
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'catalog_detail', error: e, stackTrace: st, endpoint: '/catalogs/${widget.catalogId}');
      }
      if (mounted) setState(() => _error = apiErrorMessage(e, fallback: 'No se pudo cargar el catálogo.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppPalette.rose : const Color(0xFF2A9D8F),
    ));
  }

  /// Ejecuta una acción del servidor que devuelve el detalle actualizado + message.
  Future<void> _action(Future<Map<String, dynamic>> Function() call, {String endpoint = ''}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await call();
      if (!mounted) return;
      if (data['catalog'] != null) setState(() => _data = data);
      _toast('${data['message'] ?? 'Listo.'}');
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'catalog_action', error: e, stackTrace: st, endpoint: endpoint);
      }
      if (mounted) _toast(apiErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: AppPalette.rose) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _url));
    if (mounted) _toast('Enlace copiado.');
  }

  void _shareLink() {
    final title = '${_catalog['title'] ?? 'Catálogo'}';
    SharePlus.instance.share(ShareParams(text: 'Mira nuestro catálogo "$title": $_url', subject: title));
  }

  Future<void> _openLink() async {
    final ok = await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast('No se pudo abrir el enlace.', error: true);
  }

  Future<void> _pdf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final path = await widget.api.downloadCatalogPdf(widget.catalogId, dir: dir.path);
      if (!mounted) return;
      await showFileReadySheet(context, path: path, title: 'PDF del catálogo listo', shareText: '${_catalog['title'] ?? ''}');
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'catalog_pdf', error: e, stackTrace: st, endpoint: '/catalogs/${widget.catalogId}/pdf');
      }
      if (mounted) _toast(apiErrorMessage(e, fallback: 'No se pudo generar el PDF.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => CatalogFormScreen(api: widget.api, logger: widget.logger, initial: _data),
      ),
    );
    if (saved != null && mounted) {
      _toast('Catálogo actualizado correctamente.');
      _load();
    }
  }

  Future<void> _regenerate() async {
    if (!await _confirm(
      'Generar enlace nuevo',
      'El enlace actual dejará de funcionar para quienes ya lo tienen. ¿Continuar?',
      'Generar',
    )) {
      return;
    }
    await _action(() => widget.api.regenerateCatalogLink(widget.catalogId), endpoint: '/catalogs/${widget.catalogId}/regenerate-slug');
  }

  Future<void> _toggle() async {
    final active = _catalog['active'] == true;
    if (active &&
        !await _confirm('Pausar catálogo', 'El enlace dejará de funcionar hasta que lo vuelvas a activar.', 'Pausar')) {
      return;
    }
    await _action(() => widget.api.toggleCatalog(widget.catalogId), endpoint: '/catalogs/${widget.catalogId}/toggle-active');
  }

  Future<void> _delete() async {
    if (!await _confirm('Eliminar catálogo', 'Se eliminará el catálogo y su enlace dejará de funcionar.', 'Eliminar', danger: true)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.deleteCatalog(widget.catalogId);
      if (!mounted) return;
      _toast('Catálogo eliminado correctamente.');
      Navigator.pop(context);
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'catalog_delete', error: e, stackTrace: st, endpoint: '/catalogs/${widget.catalogId}');
      }
      if (mounted) {
        setState(() => _busy = false);
        _toast(apiErrorMessage(e, fallback: 'No se pudo eliminar el catálogo.'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _catalog;
    final color = parseHexColor('${c['cover_color'] ?? ''}') ?? AppPalette.deepBlue;
    final canEdit = _abilities['edit'] == true;
    final canDelete = _abilities['delete'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        title: Text('${c['title'] ?? 'Catálogo'}'),
        backgroundColor: color,
        foregroundColor: Colors.white,
        actions: [
          if (canEdit) IconButton(tooltip: 'Editar', onPressed: _busy ? null : _edit, icon: const Icon(Icons.edit_rounded)),
          if (canEdit || canDelete)
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'toggle' => _toggle(),
                'regenerate' => _regenerate(),
                'delete' => _delete(),
                _ => null,
              },
              itemBuilder: (_) => [
                if (canEdit)
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(c['active'] == true ? 'Pausar enlace' : 'Activar enlace'),
                  ),
                if (canEdit) const PopupMenuItem(value: 'regenerate', child: Text('Generar enlace nuevo')),
                if (canDelete) const PopupMenuItem(value: 'delete', child: Text('Eliminar catálogo')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                    children: [
                      if (_busy) const LinearProgressIndicator(minHeight: 2),
                      _summaryCard(c),
                      const SizedBox(height: 12),
                      _linkCard(),
                      const SizedBox(height: 12),
                      if ('${_data['edit_blocked_reason'] ?? ''}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text('${_data['edit_blocked_reason']}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                        ),
                      Text('Productos (${(c['items'] as List? ?? const []).length})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppPalette.ink)),
                      const SizedBox(height: 8),
                      ...(c['items'] as List? ?? const [])
                          .whereType<Map>()
                          .map((i) => _itemCard(Map<String, dynamic>.from(i), c['show_prices'] == true, color)),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryCard(Map<String, dynamic> c) {
    final expires = DateTime.tryParse('${c['expires_at'] ?? ''}');
    final contact = [
      if ('${c['contact_phone'] ?? ''}'.isNotEmpty) 'Tel. ${c['contact_phone']}',
      if ('${c['contact_whatsapp'] ?? ''}'.isNotEmpty) 'WhatsApp ${c['contact_whatsapp']}',
      if ('${c['contact_email'] ?? ''}'.isNotEmpty) '${c['contact_email']}',
    ];
    const muted = TextStyle(fontSize: 12, color: Color(0xFF6A8299));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${c['branch'] ?? 'Todas las sucursales'}', style: const TextStyle(fontWeight: FontWeight.w700))),
                CatalogStatusChip(status: '${_data['status'] ?? ''}'),
              ],
            ),
            if ('${c['description'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('${c['description']}'),
            ],
            const SizedBox(height: 8),
            Text(
              [
                c['show_prices'] == true ? 'Muestra precios' : 'Sin precios',
                expires == null ? 'Sin vencimiento' : 'Vence ${DateFormat('dd/MM/yyyy').format(expires.toLocal())}',
                if (c['created_by'] != null) 'Creado por ${c['created_by']}',
              ].join(' · '),
              style: muted,
            ),
            if (c['show_contact'] == true && contact.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Contacto: ${contact.join(' · ')}', style: muted),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linkCard() {
    final accessible = _data['is_accessible'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enlace para tus clientes', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SelectableText(_url, style: const TextStyle(color: AppPalette.deepBlue)),
            if (!accessible)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('El enlace no funciona ahora: el catálogo está pausado o vencido.',
                    style: TextStyle(fontSize: 12, color: AppPalette.rose)),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _shareLink,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Compartir'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(tooltip: 'Copiar enlace', onPressed: _copyLink, icon: const Icon(Icons.copy_rounded)),
                const SizedBox(width: 4),
                IconButton.outlined(tooltip: 'Abrir', onPressed: _openLink, icon: const Icon(Icons.open_in_new_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pdf,
              icon: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFD32F2F)),
              label: const Text('PDF con fotos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(Map<String, dynamic> item, bool showPrices, Color color) {
    final image = '${item['image'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: image.isEmpty
                ? Container(
                    color: const Color(0xFFF0F4F8),
                    child: const Icon(Icons.image_not_supported_outlined, color: Color(0xFF9DB1C3)),
                  )
                : Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFFF0F4F8),
                      child: const Icon(Icons.broken_image_outlined, color: Color(0xFF9DB1C3)),
                    ),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item['name'] ?? 'Producto'}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ('${item['category'] ?? ''}'.isNotEmpty)
                    Text('${item['category']}', style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                  if (showPrices)
                    Text(_money.format(asDouble(item['price'])),
                        style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
