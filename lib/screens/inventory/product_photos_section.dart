import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';

/// Fotos del producto en su detalle del inventario: ver, agregar (cámara o galería) y eliminar.
/// Son las fotos de su préstamo, compra o ingreso: cambiarlas aquí las cambia también allí (y en los catálogos).
class ProductPhotosSection extends StatefulWidget {
  const ProductPhotosSection({
    super.key,
    required this.api,
    required this.logger,
    required this.productId,
    required this.storageBase,
    this.onChanged,
  });

  final ApiService api;
  final ErrorLogService logger;
  final int productId;

  /// Servidor sin /api/v1 (ej. https://santaana2.sczsoft.net), para armar la URL de la foto (servidor/storage/path).
  final String storageBase;
  final VoidCallback? onChanged;

  @override
  State<ProductPhotosSection> createState() => _ProductPhotosSectionState();
}

class _ProductPhotosSectionState extends State<ProductPhotosSection> {
  final _picker = ImagePicker();
  bool _loading = true;
  bool _busy = false;
  bool _canEdit = false;
  int _max = 20;
  String? _error;
  List<Map<String, dynamic>> _photos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _parse(dynamic list) =>
      (list is List ? list : const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.productPhotos(widget.productId);
      final data = res['data'] is Map ? Map<String, dynamic>.from(res['data']) : <String, dynamic>{};
      setState(() {
        _photos = _parse(data['photos']);
        _canEdit = data['can_edit'] == true;
        _max = (data['max_photos'] as num?)?.toInt() ?? 20;
      });
    } catch (e, st) {
      await widget.logger.logError(module: 'product_photos', error: e, stackTrace: st, endpoint: '/inventory/products/${widget.productId}/photos');
      setState(() => _error = 'No se pudieron cargar las fotos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _url(Map<String, dynamic> p) {
    final path = p['path']?.toString() ?? '';
    if (path.isNotEmpty && widget.storageBase.isNotEmpty) return '${widget.storageBase}/storage/$path';
    return p['url']?.toString() ?? '';
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppPalette.rose : const Color(0xFF2A9D8F)),
    );
  }

  Future<void> _add() async {
    final left = _max - _photos.length;
    if (left <= 0) {
      _snack('El producto ya tiene $_max fotos (el máximo).', error: true);
      return;
    }

    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Elegir de la galería'),
              subtitle: Text('Puedes elegir varias (hasta $left)'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    List<String> paths;
    try {
      if (source == 'camera') {
        final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
        paths = f == null ? [] : [f.path];
      } else {
        final files = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 1600);
        paths = files.take(left).map((f) => f.path).toList();
      }
    } catch (_) {
      _snack('No se pudo abrir la cámara o la galería.', error: true);
      return;
    }
    if (paths.isEmpty) return;

    setState(() => _busy = true);
    try {
      final res = await widget.api.addProductPhotos(widget.productId, paths);
      final data = res['data'] is Map ? Map<String, dynamic>.from(res['data']) : <String, dynamic>{};
      setState(() => _photos = _parse(data['photos']));
      widget.onChanged?.call();
      _snack(paths.length == 1 ? 'Foto agregada.' : '${paths.length} fotos agregadas.');
    } catch (e, st) {
      await widget.logger.logError(module: 'product_photos', error: e, stackTrace: st, endpoint: '/inventory/products/${widget.productId}/photos');
      _snack(apiErrorMessage(e, fallback: 'No se pudieron subir las fotos.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar esta foto?'),
        content: Text('Se elimina también de: ${p['source'] ?? 'su origen'}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppPalette.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final res = await widget.api.deleteProductPhoto(widget.productId, '${p['type']}', (p['id'] as num).toInt());
      final data = res['data'] is Map ? Map<String, dynamic>.from(res['data']) : <String, dynamic>{};
      setState(() => _photos = _parse(data['photos']));
      widget.onChanged?.call();
      _snack('Foto eliminada.');
    } catch (e, st) {
      await widget.logger.logError(module: 'product_photos', error: e, stackTrace: st, endpoint: '/inventory/products/${widget.productId}/photos');
      _snack(apiErrorMessage(e, fallback: 'No se pudo eliminar la foto.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(int index) {
    final urls = _photos.map(_url).where((u) => u.isNotEmpty).toList();
    if (urls.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PhotoViewer(urls: urls, initialIndex: index),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6EEF5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_library_rounded, color: AppPalette.deepBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loading ? 'Fotos' : 'Fotos (${_photos.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppPalette.ink),
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_canEdit)
                  TextButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                    label: const Text('Agregar'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Row(children: [
                Expanded(child: Text(_error!, style: const TextStyle(color: AppPalette.rose))),
                TextButton(onPressed: _load, child: const Text('Reintentar')),
              ])
            else if (_photos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 2),
                child: Text(
                  _canEdit ? 'Sin fotos. Toca "Agregar" para tomar o elegir fotos.' : 'Este producto no tiene fotos.',
                  style: const TextStyle(color: Color(0xFF6A8299), fontSize: 13),
                ),
              )
            else
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 6),
                  itemCount: _photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = _photos[i];
                    return SizedBox(
                      width: 96,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              GestureDetector(
                                onTap: () => _open(i),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    _url(p),
                                    width: 96,
                                    height: 90,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 96,
                                      height: 90,
                                      color: const Color(0xFFF0F4F8),
                                      child: const Icon(Icons.broken_image_rounded, color: Color(0xFF9DB1C3)),
                                    ),
                                  ),
                                ),
                              ),
                              if (_canEdit && !_busy)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Material(
                                    color: AppPalette.rose.withValues(alpha: 0.92),
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => _delete(p),
                                      child: const Padding(
                                        padding: EdgeInsets.all(5),
                                        child: Icon(Icons.delete_rounded, color: Colors.white, size: 16),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${p['source'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF6A8299)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late int _current = widget.initialIndex;
  late final PageController _ctrl = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.7,
          maxScale: 5,
          child: Image.network(
            widget.urls[i],
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48)),
          ),
        ),
      ),
    );
  }
}
