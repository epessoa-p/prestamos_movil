import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';
import '../widgets/common_widgets.dart';

/// Derives the public base of the API URL to build Storage URLs.
/// E.g. "https://santaana2.sczsoft.net/api/v1" → "https://santaana2.sczsoft.net"
String _storageBase(String apiBaseUrl) {
  final uri = Uri.tryParse(apiBaseUrl);
  if (uri == null) return '';
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.api,
    required this.logger,
    required this.productId,
    required this.productName,
  });

  final ApiService api;
  final ErrorLogService logger;
  final int productId;
  final String productName;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _product = {};
  double _stockTotal = 0;
  bool _canEditPrice = false;
  bool _priceChanged = false;
  List<dynamic> _byWarehouse = [];
  List<dynamic> _recentMovements = [];

  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

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
      final data = await widget.api.inventoryStockDetail(widget.productId);
      setState(() {
        _product = _asMap(data['product']);
        _stockTotal = asDouble(data['summary']?['stock_total']);
        _canEditPrice = data['abilities']?['edit_price'] == true;
        _byWarehouse = _asList(data['stock_by_warehouse']);
        _recentMovements = _asList(data['recent_movements']);
      });
    } catch (e, st) {
      await widget.logger.logError(
        module: 'product_detail',
        error: e,
        stackTrace: st,
        endpoint: '/inventory/stock/${widget.productId}',
      );
      setState(() => _error = 'No se pudo cargar el detalle del producto');
    } finally {
      setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  List<dynamic> _asList(dynamic v) => v is List ? v : [];

  String _formatDate(String raw) {
    try {
      return _dateFmt.format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _priceChanged);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F7FB),
        body: CustomScrollView(
          slivers: [
            _buildAppBar(),
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: AppPalette.rose),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(child: _buildSummaryCard()),
              SliverToBoxAdapter(child: _buildPriceCard()),
              SliverToBoxAdapter(child: _buildWarehouseSection()),
              SliverToBoxAdapter(child: _buildMovementsSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      stretch: true,
      backgroundColor: AppPalette.deepBlue,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          _product['name']?.toString() ?? widget.productName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppPalette.deepBlue, Color(0xFF19C5B6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 60),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_product['code'] ?? ''}'.isNotEmpty ? 'Código' : 'SKU',
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                        Text(
                          '${_product['code'] ?? ''}'.isNotEmpty ? '${_product['code']}' : (_product['sku']?.toString() ?? '-'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Stock total disponible', style: TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                  const SizedBox(height: 4),
                  Text(
                    '${_stockTotal.toStringAsFixed(_stockTotal.truncateToDouble() == _stockTotal ? 0 : 2)} unidades',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppPalette.ink),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: _stockTotal > 0
                    ? AppPalette.aqua.withValues(alpha: 0.12)
                    : AppPalette.rose.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _stockTotal > 0
                      ? AppPalette.aqua.withValues(alpha: 0.35)
                      : AppPalette.rose.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(
                _stockTotal > 0 ? Icons.check_circle_rounded : Icons.warning_rounded,
                color: _stockTotal > 0 ? AppPalette.aqua : AppPalette.rose,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceCard() {
    final money = Currency.formatter();
    final price = asDouble(_product['price']);
    final cost = asDouble(_product['cost']);

    Widget item(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6EEF5)),
        ),
        child: Row(
          children: [
            item('Precio de venta', money.format(price), const Color(0xFF2E7D32)),
            item('Costo', money.format(cost), AppPalette.ink),
            if (_canEditPrice)
              IconButton(
                tooltip: 'Cambiar precio',
                onPressed: _editPrice,
                icon: const Icon(Icons.edit_rounded, color: AppPalette.deepBlue),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPrice() async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PriceDialog(
        api: widget.api,
        logger: widget.logger,
        productId: widget.productId,
        currentPrice: asDouble(_product['price']),
        cost: asDouble(_product['cost']),
      ),
    );
    if (saved == null || !mounted) return;
    final product = _asMap(saved['data']?['product']);
    setState(() {
      if (product.isNotEmpty) _product = {..._product, 'price': product['price']};
      _priceChanged = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved['message']?.toString() ?? 'Precio actualizado.'),
        backgroundColor: const Color(0xFF2A9D8F),
      ),
    );
  }

  Widget _buildWarehouseSection() {
    if (_byWarehouse.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              'Stock por almacén',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppPalette.ink),
            ),
          ),
          ..._byWarehouse.map((item) {
            final map = _asMap(item);
            final stock = asDouble(map['stock']);
            final raw = map['last_movement_at']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE6EEF5)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.deepBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warehouse_rounded, color: AppPalette.deepBlue, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          map['warehouse_name']?.toString() ?? 'Almacén',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppPalette.ink),
                        ),
                        const SizedBox(height: 4),
                        BranchPill(
                          name: map['branch_name']?.toString(),
                          color: map['branch_color']?.toString(),
                          dense: true,
                        ),
                        if (raw.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Último mov: ${_formatDate(raw)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppPalette.aqua.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppPalette.aqua.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      '${stock.toStringAsFixed(stock.truncateToDouble() == stock ? 0 : 2)} un.',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.aqua, fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMovementsSection() {
    if (_recentMovements.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 2),
            child: Text(
              'Movimientos recientes',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppPalette.ink),
            ),
          ),
          ..._recentMovements.map((item) {
            final map = _asMap(item);
            return _MovementCard(map: map, storageBase: _storageBase(widget.api.baseUrl));
          }),
        ],
      ),
    );
  }
}

class _PriceDialog extends StatefulWidget {
  const _PriceDialog({
    required this.api,
    required this.logger,
    required this.productId,
    required this.currentPrice,
    required this.cost,
  });

  final ApiService api;
  final ErrorLogService logger;
  final int productId;
  final double currentPrice;
  final double cost;

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.currentPrice.toStringAsFixed(2));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    if (price == null || price < 0) {
      setState(() => _error = 'Ingresa un precio válido.');
      return;
    }
    if (price == widget.currentPrice) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.api.updateProductPrice(widget.productId, price);
      if (mounted) Navigator.pop(context, result);
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(
          module: 'product_price',
          error: e,
          stackTrace: st,
          endpoint: '/inventory/products/${widget.productId}/price',
        );
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = apiErrorMessage(e, fallback: 'No se pudo actualizar el precio.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    final margin = price == null ? null : price - widget.cost;

    return AlertDialog(
      title: const Text('Precio de venta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(prefixText: Currency.prefix, errorText: _error),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          if (margin != null) ...[
            const SizedBox(height: 10),
            Text(
              'Costo: ${Currency.formatter().format(widget.cost)} · Ganancia: ${Currency.formatter().format(margin)}',
              style: TextStyle(fontSize: 12, color: margin < 0 ? AppPalette.rose : const Color(0xFF6A8299)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({required this.map, required this.storageBase});

  final Map<String, dynamic> map;
  final String storageBase;

  @override
  Widget build(BuildContext context) {
    final isIn = map['type']?.toString() == 'in';
    final color = isIn ? const Color(0xFF2A9D8F) : const Color(0xFFE76F51);
    final icon = isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    final qty = asDouble(map['quantity']);
    final ref = map['reference']?.toString() ?? '';
    final dateRaw = map['movement_date']?.toString() ?? '';
    final date = dateRaw.isNotEmpty
        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.tryParse(dateRaw) ?? DateTime.now())
        : '-';
    final images = _asList(map['images']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EEF5)),
        boxShadow: const [BoxShadow(color: Color(0x0E000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isIn ? 'Entrada' : 'Salida',
                              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${isIn ? '+' : '-'}${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2)} un.',
                            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF9DB1C3)),
                          const SizedBox(width: 4),
                          Text(date, style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                          if (ref.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            const Icon(Icons.tag_rounded, size: 12, color: Color(0xFF9DB1C3)),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                ref,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (images.isNotEmpty) _ImageCarousel(images: images, storageBase: storageBase),
        ],
      ),
    );
  }

  List<dynamic> _asList(dynamic v) => v is List ? v : [];
}

class _ImageCarousel extends StatefulWidget {
  const _ImageCarousel({required this.images, required this.storageBase});

  final List<dynamic> images;
  final String storageBase;

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _current = 0;
  late final PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  String _imageUrl(Map<String, dynamic> img) {
    // Prefer url field (full URL from API), fall back to constructing from path
    final url = img['url']?.toString() ?? '';
    if (url.startsWith('http')) return url;
    if (url.isNotEmpty) return '${widget.storageBase}$url';
    final path = img['path']?.toString() ?? '';
    if (path.isNotEmpty) return '${widget.storageBase}/storage/$path';
    return '';
  }

  void _openFullscreen(int index) {
    final urls = widget.images.map((item) => _imageUrl(_asMap(item))).where((u) => u.isNotEmpty).toList();
    if (urls.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (ctx, anim, secAnim) => _FullscreenGallery(urls: urls, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.images.length;

    return Column(
      children: [
        const Divider(height: 1),
        ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
          child: Stack(
            children: [
              SizedBox(
                height: 200,
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: total,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, index) {
                    final img = _asMap(widget.images[index]);
                    final url = _imageUrl(img);
                    final name = img['original_name']?.toString() ?? '';
                    return GestureDetector(
                      onTap: () => _openFullscreen(index),
                      child: url.isNotEmpty
                          ? Image.network(
                              url,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (context, err, st) => _placeholder(name),
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: progress.expectedTotalBytes != null
                                        ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                        : null,
                                  ),
                                );
                              },
                            )
                          : _placeholder(name),
                    );
                  },
                ),
              ),
              if (total > 1)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(total, (i) {
                      final active = i == _current;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active ? Colors.white : Colors.white54,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
              Positioned(
                top: 8,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    '${_current + 1}/$total',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholder(String name) {
    return Container(
      color: const Color(0xFFF0F4F8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_rounded, size: 32, color: Color(0xFF9DB1C3)),
          if (name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(name, style: const TextStyle(fontSize: 11, color: Color(0xFF9DB1C3))),
            ),
        ],
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late int _current;
  late final PageController _ctrl;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

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
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.7,
            maxScale: 5,
            child: Image.network(
              widget.urls[index],
              fit: BoxFit.contain,
              errorBuilder: (context, err, st) =>
                  const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48)),
            ),
          );
        },
      ),
    );
  }
}
