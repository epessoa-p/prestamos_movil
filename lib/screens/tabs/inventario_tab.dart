import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/inventory_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/upper_case.dart';
import '../../utils/number_utils.dart';
import '../inventory/product_detail_screen.dart';
import '../widgets/common_widgets.dart';
import '../../utils/currency.dart';

class InventarioTab extends StatefulWidget {
  const InventarioTab({
    super.key,
    required this.controller,
    required this.api,
    required this.logger,
    this.canCreate = false,
  });

  final InventoryController controller;
  final ApiService api;
  final ErrorLogService logger;

  /// Permiso "warehouses.create": registrar ingresos de stock.
  final bool canCreate;

  @override
  State<InventarioTab> createState() => _InventarioTabState();
}

class _InventarioTabState extends State<InventarioTab> {
  final _searchCtrl = TextEditingController();

  Future<void> _openStockEntrySheet() async {
    if (widget.controller.branches.isEmpty && !widget.controller.optionsLoading) {
      await widget.controller.loadOptions();
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StockEntrySheet(controller: widget.controller),
    );

    if (!mounted) return;
    if (widget.controller.submitSuccess != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.controller.submitSuccess!)));
      widget.controller.clearSubmitState();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _differentWarehouse(Map<String, dynamic> row) {
    final warehouse = '${row['warehouse_name'] ?? ''}'.trim().toLowerCase();
    final branch = '${row['branch_name'] ?? ''}'.trim().toLowerCase();
    return warehouse.isNotEmpty && warehouse != branch;
  }

  List<Map<String, dynamic>> _asMaps(List<dynamic> list) =>
      list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  Future<void> _openFilters() async {
    final c = widget.controller;
    if (c.branches.isEmpty && !c.optionsLoading) await c.loadOptions();
    if (!mounted) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InventoryFiltersSheet(
        initial: c.filters,
        branches: _asMaps(c.branches),
        warehouses: _asMaps(c.warehouses),
        categories: _asMaps(c.categories),
      ),
    );
    if (result != null) c.applyFilters(result);
  }

  /// Texto con los filtros aplicados y el botón para quitarlos.
  Widget _filtersBar() {
    final c = widget.controller;
    if (c.activeFilterCount == 0) return const SizedBox.shrink();
    String find(List<dynamic> list, String key) {
      final id = '${c.filters[key] ?? ''}';
      final match = _asMaps(list).where((o) => '${o['id']}' == id);
      return match.isEmpty ? id : '${match.first['name']}';
    }

    bool has(String k) => '${c.filters[k] ?? ''}'.isNotEmpty;
    final parts = [
      if (has('branch_id')) find(c.branches, 'branch_id'),
      if (has('warehouse_id')) find(c.warehouses, 'warehouse_id'),
      if (has('category_id')) find(c.categories, 'category_id'),
      if (c.filters['in_stock'] != 1) 'Incluye sin stock',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
      child: Row(
        children: [
          Expanded(child: Text(parts.join(' · '), style: const TextStyle(fontSize: 12, color: AppPalette.deepBlue))),
          TextButton(
            onPressed: () => c.applyFilters({'in_stock': 1}),
            child: const Text('Quitar filtros'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            const AppHeader(title: 'Inventario', subtitle: 'Stock de productos por almacén'),
            if (widget.canCreate)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E5E9D), Color(0xFF19C5B6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 6))],
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Registrar ingreso',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Agrega stock de forma rapida y segura',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppPalette.deepBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _openStockEntrySheet,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Nuevo'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (query) => widget.controller.load(query: query.trim()),
                      decoration: InputDecoration(
                        hintText: 'Buscar producto o SKU…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded),
                          onPressed: () => widget.controller.load(query: _searchCtrl.text.trim()),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Filtros',
                    onPressed: _openFilters,
                    icon: Badge(
                      isLabelVisible: widget.controller.activeFilterCount > 0,
                      label: Text('${widget.controller.activeFilterCount}'),
                      child: const Icon(Icons.filter_list_rounded),
                    ),
                  ),
                ],
              ),
            ),
            _filtersBar(),
            if (!widget.controller.loading && widget.controller.totals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _InventoryValueCard(totals: widget.controller.totals),
              ),
            if (widget.controller.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(widget.controller.error!, style: const TextStyle(color: AppPalette.rose)),
              ),
            if (widget.controller.loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (widget.controller.inventory.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('No hay productos en inventario.'))
            else
              ...widget.controller.inventory.map((item) {
                final map = (item as Map).cast<String, dynamic>();
                final stock = asDouble(map['stock']);
                final productId = map['product_id'];
                final parsedId = productId is int ? productId : int.tryParse(productId?.toString() ?? '');
                final productName = map['product_name']?.toString() ?? 'Producto';
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: parsedId == null
                        ? null
                        : () async {
                            final changed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute<bool>(
                                builder: (_) => ProductDetailScreen(
                                  api: widget.api,
                                  logger: widget.logger,
                                  productId: parsedId,
                                  productName: productName,
                                ),
                              ),
                            );
                            if (changed == true) widget.controller.load(query: _searchCtrl.text.trim());
                          },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE6EEF5)),
                        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0, 4))],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppPalette.deepBlue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.inventory_2_rounded, color: AppPalette.deepBlue),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    map['product_name']?.toString() ?? 'Producto',
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      BranchPill(
                                        name: map['branch_name']?.toString(),
                                        color: map['branch_color']?.toString(),
                                        dense: true,
                                      ),
                                      // El almacén solo si se llama distinto a la sucursal (hoy cada
                                      // sucursal tiene un almacén con su mismo nombre).
                                      if (_differentWarehouse(map))
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.warehouse_rounded, size: 13, color: Color(0xFF9DB1C3)),
                                            const SizedBox(width: 3),
                                            Text(
                                              '${map['warehouse_name']}',
                                              style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Código correlativo del producto (PD-00012) en pill; el SKU solo si no hay código.
                                  if ('${map['product_code'] ?? ''}'.isNotEmpty)
                                    CodePill('${map['product_code']}')
                                  else
                                    Text(
                                      'SKU: ${map['product_sku'] ?? '-'}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                                    ),
                                  if (map['product_price'] != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Precio: ${Currency.formatter().format(asDouble(map['product_price']))}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF2E7D32),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppPalette.aqua.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppPalette.aqua.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                '${stock.toStringAsFixed(stock.truncateToDouble() == stock ? 0 : 2)} un.',
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.aqua),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ), // InkWell
                );
              }),
            if (!widget.controller.loading && widget.controller.page < widget.controller.lastPage)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: OutlinedButton(
                  onPressed: widget.controller.loadingMore ? null : () => widget.controller.load(more: true),
                  child: widget.controller.loadingMore
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Ver más (${widget.controller.total - widget.controller.inventory.length} restantes)'),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Valor del inventario filtrado: unidades, valor a costo, a precio de venta y ganancia posible,
/// separado en "para la venta" y "en garantía" (prendas de préstamos vigentes).
class _InventoryValueCard extends StatefulWidget {
  const _InventoryValueCard({required this.totals});

  final Map<String, dynamic> totals;

  @override
  State<_InventoryValueCard> createState() => _InventoryValueCardState();
}

class _InventoryValueCardState extends State<_InventoryValueCard> {
  bool _expanded = false;
  final _money = Currency.formatter();

  Map<String, dynamic> _block(String key) {
    final v = widget.totals[key];
    return v is Map ? Map<String, dynamic>.from(v) : {};
  }

  String _units(dynamic v) {
    final n = asDouble(v);
    return n == n.truncateToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.totals;
    final profit = asDouble(t['profit']);
    final missing = asInt(t['missing_price']);

    Widget metric(String label, String value, {Color color = Colors.white}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16476F), Color(0xFF1E5E9D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 5))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Valor del inventario',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${_units(t['units'])} unid.',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.white70),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    metric('A costo', _money.format(asDouble(t['cost']))),
                    const SizedBox(width: 10),
                    metric('A precio de venta', _money.format(asDouble(t['sale']))),
                    const SizedBox(width: 10),
                    metric(
                      'Ganancia posible',
                      _money.format(profit),
                      color: profit >= 0 ? const Color(0xFF9BF6C8) : const Color(0xFFFFB4B4),
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 12),
                  _breakdown(
                    'Para la venta',
                    'Stock libre y prendas de préstamos incumplidos',
                    Icons.sell_rounded,
                    _block('for_sale'),
                  ),
                  const SizedBox(height: 8),
                  _breakdown(
                    'En garantía',
                    'Prendas de préstamos vigentes: el cliente aún puede recuperarlas',
                    Icons.lock_clock_rounded,
                    _block('pledged'),
                  ),
                  if (missing > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$missing ${missing == 1 ? 'producto no tiene' : 'productos no tienen'} precio de venta: '
                      'cuentan en el costo pero no en la venta ni en la ganancia.',
                      style: const TextStyle(color: Color(0xFFFFE0B2), fontSize: 11),
                    ),
                  ],
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Toca para ver cuánto está para la venta y cuánto en garantía.',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _breakdown(String title, String hint, IconData icon, Map<String, dynamic> b) {
    const label = TextStyle(color: Colors.white70, fontSize: 10);
    const value = TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12);
    Widget col(String l, String v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l, style: label),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: value)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 5),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              const Spacer(),
              Text('${_units(b['units'])} unid.', style: value),
            ],
          ),
          Text(hint, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          const SizedBox(height: 6),
          Row(
            children: [
              col('Costo', _money.format(asDouble(b['cost']))),
              col('Venta', _money.format(asDouble(b['sale']))),
              col('Ganancia', _money.format(asDouble(b['profit']))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Filtros del inventario: sucursal, almacén, categoría y si se incluyen los productos sin stock.
class _InventoryFiltersSheet extends StatefulWidget {
  const _InventoryFiltersSheet({
    required this.initial,
    required this.branches,
    required this.warehouses,
    required this.categories,
  });

  final Map<String, dynamic> initial;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> warehouses;
  final List<Map<String, dynamic>> categories;

  @override
  State<_InventoryFiltersSheet> createState() => _InventoryFiltersSheetState();
}

class _InventoryFiltersSheetState extends State<_InventoryFiltersSheet> {
  late final Map<String, dynamic> _f = Map<String, dynamic>.from(widget.initial);

  Widget _dropdown(String key, String label, List<Map<String, dynamic>> items) {
    final value = '${_f[key] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: items.any((i) => '${i['id']}' == value) ? value : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          for (final i in items)
            DropdownMenuItem(value: '${i['id']}', child: Text('${i['name']}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => _f[key] = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Filtrar inventario', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (widget.branches.length > 1) _dropdown('branch_id', 'Sucursal', widget.branches),
              if (widget.warehouses.length > 1) _dropdown('warehouse_id', 'Almacén', widget.warehouses),
              _dropdown('category_id', 'Categoría', widget.categories),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Solo productos con stock'),
                subtitle: const Text('Oculta los que quedaron en 0 (vendidos o devueltos)'),
                value: _f['in_stock'] == 1,
                onChanged: (v) => setState(() => _f['in_stock'] = v ? 1 : 0),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, <String, dynamic>{'in_stock': 1}),
                      child: const Text('Limpiar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(onPressed: () => Navigator.pop(context, _f), child: const Text('Aplicar')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockEntrySheet extends StatefulWidget {
  const _StockEntrySheet({required this.controller});

  final InventoryController controller;

  @override
  State<_StockEntrySheet> createState() => _StockEntrySheetState();
}

class _StockEntrySheetState extends State<_StockEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  static const int _maxImages = 20;
  static const int _maxImageSizeBytes = 5 * 1024 * 1024;
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _images = <XFile>[];
  int? _branchId;
  int? _warehouseId;
  int? _categoryId;

  final _productNameCtrl = TextEditingController();
  final _productCodeCtrl = TextEditingController();
  final _productBrandCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  // Artículos
  final _itemModelCtrl = TextEditingController();
  // Vehículos
  int? _selectedModelYear;
  final _plateCtrl = TextEditingController();
  final _chassisCtrl = TextEditingController();
  // Joyas
  final _itemTypeCtrl = TextEditingController();
  String? _selectedKarat;
  String? _selectedMaterialType;

  final _unitCostCtrl = TextEditingController();
  final _productPriceCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _movementDateCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()));

  @override
  void initState() {
    super.initState();
    // Personal que no es gerente: su sucursal fija. Con una sola sucursal, esa.
    final c = widget.controller;
    _branchId = c.lockedBranchId ?? (c.branches.length == 1 ? _id((c.branches.first as Map)['id']) : null);
    // Código sugerido (siguiente PD-); se puede cambiar.
    _productCodeCtrl.text = c.nextProductCode ?? '';
  }

  @override
  void dispose() {
    _productNameCtrl.dispose();
    _productCodeCtrl.dispose();
    _productBrandCtrl.dispose();
    _serialCtrl.dispose();
    _descriptionCtrl.dispose();
    _itemModelCtrl.dispose();
    _plateCtrl.dispose();
    _chassisCtrl.dispose();
    _itemTypeCtrl.dispose();
    _unitCostCtrl.dispose();
    _productPriceCtrl.dispose();
    _referenceCtrl.dispose();
    _notesCtrl.dispose();
    _movementDateCtrl.dispose();
    super.dispose();
  }

  String? _fieldError(String key) {
    final direct = widget.controller.validationErrors[key];
    if (direct != null) return direct;
    for (final entry in widget.controller.validationErrors.entries) {
      if (entry.key.startsWith('$key.')) {
        return entry.value;
      }
    }
    return null;
  }

  int? _id(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String _label(Map<String, dynamic> map, String key) => map[key]?.toString() ?? '-';

  /// Formulario del producto según la categoría, como en préstamos y compras (lo indica la API en `form`):
  /// 1 vehículos, 2 joyas, 3 garrafas y cualquier otra (celular, computadora…) usa el de artículos.
  String? _categoryType() {
    if (_categoryId == null) return null;
    final cat = widget.controller.categories
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .firstWhere((m) => _id(m['id']) == _categoryId, orElse: () => <String, dynamic>{});
    return switch (_id(cat['form']) ?? _id(cat['id'])) {
      1 => 'vehiculos',
      2 => 'joyas',
      3 => 'garrafas',
      _ => 'articulos',
    };
  }

  /// Sucursal elegida (con su warehouse_id).
  Map<String, dynamic>? get _branch => widget.controller.branches
      .whereType<Map>()
      .map((m) => m.cast<String, dynamic>())
      .where((m) => _id(m['id']) == _branchId)
      .firstOrNull;

  /// Almacén de la sucursal elegida (null si la sucursal no tiene uno asignado).
  int? get _branchWarehouseId => _id(_branch?['warehouse_id']);

  String? _warehouseName(int? id) => widget.controller.warehouses
      .whereType<Map>()
      .map((m) => m.cast<String, dynamic>())
      .where((m) => _id(m['id']) == id)
      .map((m) => m['name']?.toString())
      .firstOrNull;

  void _clearCategoryFields() {
    _productNameCtrl.clear();
    _productBrandCtrl.clear();
    _serialCtrl.clear();
    _descriptionCtrl.clear();
    _itemModelCtrl.clear();
    _selectedModelYear = null;
    _plateCtrl.clear();
    _chassisCtrl.clear();
    _itemTypeCtrl.clear();
    _selectedKarat = null;
    _selectedMaterialType = null;
  }

  Future<void> _pickMovementDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (!mounted) return;
    final combined = DateTime(date.year, date.month, date.day, time?.hour ?? 0, time?.minute ?? 0);
    setState(() {
      _movementDateCtrl.text = DateFormat('yyyy-MM-dd HH:mm:ss').format(combined);
    });
  }

  double? _parseDouble(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  Future<void> _pickFromCamera() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (file == null) return;
      await _addImages(<XFile>[file]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir la camara')));
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 85);
      if (files.isEmpty) return;
      await _addImages(files);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir la galeria')));
    }
  }

  Future<void> _addImages(List<XFile> files) async {
    final availableSlots = _maxImages - _images.length;
    if (availableSlots <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Solo puedes adjuntar hasta 20 imagenes')));
      return;
    }

    final accepted = <XFile>[];
    final limited = files.take(availableSlots);
    for (final file in limited) {
      final size = await file.length();
      if (size <= _maxImageSizeBytes) {
        accepted.add(file);
      }
    }

    if (accepted.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Las imagenes deben pesar maximo 5MB cada una')));
      return;
    }

    if (!mounted) return;
    setState(() => _images.addAll(accepted));

    final skipped = files.length - accepted.length;
    if (skipped > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Se omitieron $skipped imagen(es) por limite o tamano')));
    }
  }

  void _removeImageAt(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  Future<void> _showImageSourcePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Agregar imagenes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppPalette.deepBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: AppPalette.deepBlue),
                  ),
                  title: const Text('Tomar foto'),
                  subtitle: const Text('Abrir camara del dispositivo'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickFromCamera();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppPalette.aqua.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_library_rounded, color: AppPalette.aqua),
                  ),
                  title: const Text('Elegir de galeria'),
                  subtitle: const Text('Seleccion multiple disponible'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickFromGallery();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // El almacén sale de la sucursal; solo se elige a mano si la sucursal no tiene uno asignado.
    final warehouseId = _branchWarehouseId ?? _warehouseId;
    if (_branchId == null || warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_branchId == null ? 'Selecciona la sucursal' : 'Selecciona el almacén')),
      );
      return;
    }

    final catType = _categoryType();

    final ok = await widget.controller.submitStockEntry(
      branchId: _branchId!,
      warehouseId: warehouseId,
      productMode: 'new',
      creditCategoryId: _categoryId,
      // Joyas y garrafas: el nombre lo arma el servidor (tipo de joya / nombre de la categoría).
      productCode: _productCodeCtrl.text.trim(),
      productName: (catType == 'vehiculos' || catType == 'articulos') ? _productNameCtrl.text.trim() : null,
      productBrand: (catType == 'vehiculos' || catType == 'articulos') ? _productBrandCtrl.text.trim() : null,
      productSerialNumber: catType == 'articulos' ? _serialCtrl.text.trim() : null,
      productDescription: _descriptionCtrl.text.trim(),
      productCost: _parseDouble(_unitCostCtrl.text),
      productPrice: _parseDouble(_productPriceCtrl.text),
      productItemModel: catType == 'articulos' ? _itemModelCtrl.text.trim() : null,
      productModelYear: catType == 'vehiculos' ? _selectedModelYear?.toString() : null,
      productPlate: catType == 'vehiculos' ? _plateCtrl.text.trim() : null,
      productChassis: catType == 'vehiculos' ? _chassisCtrl.text.trim() : null,
      productItemType: catType == 'joyas' ? _itemTypeCtrl.text.trim() : null,
      productKarat: catType == 'joyas' ? _selectedKarat : null,
      productMaterialType: catType == 'joyas' ? _selectedMaterialType : null,
      quantity: 1,
      reference: _referenceCtrl.text,
      notes: _notesCtrl.text,
      movementDate: _movementDateCtrl.text.trim(),
      imagePaths: _images.map((file) => file.path).toList(),
    );

    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      return;
    }

    if (widget.controller.submitError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.controller.submitError!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FBFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 52,
                height: 5,
                decoration: BoxDecoration(color: const Color(0xFFD4DEE7), borderRadius: BorderRadius.circular(999)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nuevo ingreso de stock',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppPalette.ink),
                          ),
                          SizedBox(height: 2),
                          Text('Completa los datos para registrar el movimiento'),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(18, 16, 18, bottomInset + 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (controller.optionsError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppPalette.rose),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(controller.optionsError!, style: const TextStyle(color: AppPalette.rose)),
                                ),
                                TextButton(onPressed: () => controller.loadOptions(), child: const Text('Reintentar')),
                              ],
                            ),
                          ),
                        // Solo la sucursal: el almacén es el que tiene asignado (como en la web).
                        DropdownButtonFormField<int>(
                          initialValue: _branchId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Sucursal',
                            prefixIcon: const Icon(Icons.store_rounded),
                            errorText: _fieldError('branch_id'),
                            helperText: controller.lockedBranchId != null ? 'Solo puedes ingresar en tu sucursal' : null,
                          ),
                          items: controller.branches
                              .map((item) {
                                final map = (item as Map).cast<String, dynamic>();
                                final id = _id(map['id']);
                                if (id == null) return null;
                                return DropdownMenuItem<int>(
                                  value: id,
                                  child: Text(_label(map, 'name'), maxLines: 1, overflow: TextOverflow.ellipsis),
                                );
                              })
                              .whereType<DropdownMenuItem<int>>()
                              .toList(),
                          onChanged: controller.submittingEntry || controller.lockedBranchId != null
                              ? null
                              : (value) => setState(() {
                                  _branchId = value;
                                  _warehouseId = null;
                                }),
                          validator: (value) => value == null ? 'Selecciona la sucursal' : null,
                        ),
                        if (_branchId != null && _branchWarehouseId != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.warehouse_rounded, size: 16, color: Color(0xFF6A8299)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Se guarda en el almacén ${_warehouseName(_branchWarehouseId) ?? 'de la sucursal'}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (_branchId != null)
                          // La sucursal no tiene almacén asignado: se elige a mano.
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: DropdownButtonFormField<int>(
                              initialValue: _warehouseId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Almacén',
                                prefixIcon: const Icon(Icons.warehouse_rounded),
                                helperText: 'Esta sucursal no tiene un almacén asignado',
                                errorText: _fieldError('warehouse_id'),
                              ),
                              items: controller.warehouses
                                  .map((item) {
                                    final map = (item as Map).cast<String, dynamic>();
                                    final id = _id(map['id']);
                                    if (id == null) return null;
                                    return DropdownMenuItem<int>(
                                      value: id,
                                      child: Text(_label(map, 'name'), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    );
                                  })
                                  .whereType<DropdownMenuItem<int>>()
                                  .toList(),
                              onChanged: controller.submittingEntry
                                  ? null
                                  : (value) => setState(() => _warehouseId = value),
                              validator: (value) => value == null ? 'Selecciona el almacén' : null,
                            ),
                          ),
                        const SizedBox(height: 16),
                        // ── Sección: Producto ─────────────────────────────────
                        _FormCard(
                          icon: Icons.inventory_2_rounded,
                          iconColor: AppPalette.deepBlue,
                          title: 'Datos del producto',
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _productCodeCtrl,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: upperCaseFormatters,
                                enabled: !controller.submittingEntry,
                                decoration: InputDecoration(
                                  labelText: 'Código del producto',
                                  hintText: controller.nextProductCode ?? 'PD-00001',
                                  helperText: 'Sugerido: el siguiente correlativo. No se repite en la sucursal.',
                                  prefixIcon: const Icon(Icons.qr_code_rounded),
                                  errorText: _fieldError('product_code'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                initialValue: _categoryId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Categoría',
                                  prefixIcon: const Icon(Icons.category_rounded),
                                  errorText: _fieldError('credit_category_id'),
                                ),
                                items: controller.categories
                                    .map((item) {
                                      final map = (item as Map).cast<String, dynamic>();
                                      final id = _id(map['id']);
                                      if (id == null) return null;
                                      return DropdownMenuItem<int>(
                                        value: id,
                                        child: Text(_label(map, 'name'), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      );
                                    })
                                    .whereType<DropdownMenuItem<int>>()
                                    .toList(),
                                onChanged: controller.submittingEntry
                                    ? null
                                    : (value) => setState(() {
                                        _categoryId = value;
                                        _clearCategoryFields();
                                      }),
                                validator: (value) => value == null ? 'Selecciona una categoría' : null,
                              ),
                              if (_categoryType() != null) ...[
                                if (_categoryType() == 'garrafas' || _categoryType() == 'joyas')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: AppPalette.aqua.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppPalette.aqua.withValues(alpha: 0.25)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.info_outline_rounded, color: AppPalette.aqua, size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _categoryType() == 'joyas'
                                                  ? 'El nombre será el tipo de joya (ej. ANILLO).'
                                                  : 'El nombre se asignará automáticamente.',
                                              style: const TextStyle(fontSize: 12, color: AppPalette.aqua),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (_categoryType() == 'vehiculos' || _categoryType() == 'articulos') ...[
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _productNameCtrl,
                                    textCapitalization: TextCapitalization.characters,
                                    inputFormatters: upperCaseFormatters,
                                    enabled: !controller.submittingEntry,
                                    decoration: InputDecoration(
                                      labelText: 'Nombre del producto',
                                      prefixIcon: const Icon(Icons.label_rounded),
                                      errorText: _fieldError('product_name'),
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                                  ),
                                ],
                                if (_categoryType() == 'vehiculos' || _categoryType() == 'articulos') ...[
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _productBrandCtrl,
                                    textCapitalization: TextCapitalization.characters,
                                    inputFormatters: upperCaseFormatters,
                                    enabled: !controller.submittingEntry,
                                    decoration: InputDecoration(
                                      labelText: 'Marca',
                                      prefixIcon: const Icon(Icons.branding_watermark_rounded),
                                      errorText: _fieldError('product_brand'),
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                                  ),
                                ],
                                if (_categoryType() == 'vehiculos') ...[
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<int>(
                                    initialValue: _selectedModelYear,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'Año del modelo',
                                      prefixIcon: const Icon(Icons.calendar_today_rounded),
                                      errorText: _fieldError('product_model_year'),
                                    ),
                                    items: List.generate(
                                      DateTime.now().year - 1980 + 1,
                                      (i) => DateTime.now().year - i,
                                    ).map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                                    onChanged: controller.submittingEntry
                                        ? null
                                        : (v) => setState(() => _selectedModelYear = v),
                                    validator: (v) => v == null ? 'Requerido' : null,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _plateCtrl,
                                          textCapitalization: TextCapitalization.characters,
                                          inputFormatters: upperCaseFormatters,
                                          enabled: !controller.submittingEntry,
                                          decoration: InputDecoration(
                                            labelText: 'Placa',
                                            errorText: _fieldError('product_plate'),
                                          ),
                                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _chassisCtrl,
                                          textCapitalization: TextCapitalization.characters,
                                          inputFormatters: upperCaseFormatters,
                                          enabled: !controller.submittingEntry,
                                          decoration: InputDecoration(
                                            labelText: 'Chasis',
                                            errorText: _fieldError('product_chassis'),
                                          ),
                                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (_categoryType() == 'joyas') ...[
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _itemTypeCtrl,
                                    textCapitalization: TextCapitalization.characters,
                                    inputFormatters: upperCaseFormatters,
                                    enabled: !controller.submittingEntry,
                                    decoration: InputDecoration(
                                      labelText: 'Tipo de joya',
                                      prefixIcon: const Icon(Icons.diamond_rounded),
                                      errorText: _fieldError('product_item_type'),
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _selectedKarat,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            labelText: 'Kilates',
                                            errorText: _fieldError('product_karat'),
                                          ),
                                          items: const [
                                            '10K',
                                            '14K',
                                            '18K',
                                            '21K',
                                            '22K',
                                            '24K',
                                          ].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                                          onChanged: controller.submittingEntry
                                              ? null
                                              : (v) => setState(() => _selectedKarat = v),
                                          validator: (v) => v == null ? 'Requerido' : null,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _selectedMaterialType,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            labelText: 'Material (opc.)',
                                            errorText: _fieldError('product_material_type'),
                                          ),
                                          items: const [
                                            'Oro',
                                            'Plata',
                                            'Platino',
                                            'Acero',
                                            'Otro',
                                          ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                          onChanged: controller.submittingEntry
                                              ? null
                                              : (v) => setState(() => _selectedMaterialType = v),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (_categoryType() == 'articulos') ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _itemModelCtrl,
                                          textCapitalization: TextCapitalization.characters,
                                          inputFormatters: upperCaseFormatters,
                                          enabled: !controller.submittingEntry,
                                          decoration: InputDecoration(
                                            labelText: 'Modelo (opc.)',
                                            errorText: _fieldError('product_item_model'),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _serialCtrl,
                                          textCapitalization: TextCapitalization.characters,
                                          inputFormatters: upperCaseFormatters,
                                          enabled: !controller.submittingEntry,
                                          decoration: InputDecoration(
                                            labelText: 'Serie',
                                            errorText: _fieldError('product_serial_number'),
                                          ),
                                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _descriptionCtrl,
                                  textCapitalization: TextCapitalization.characters,
                                  inputFormatters: upperCaseFormatters,
                                  enabled: !controller.submittingEntry,
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    labelText: 'Descripción (opcional)',
                                    prefixIcon: const Icon(Icons.notes_rounded),
                                    errorText: _fieldError('product_description'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _unitCostCtrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        labelText: 'Costo (opc.)',
                                        prefixText: Currency.prefix,
                                        errorText: _fieldError('product_cost'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _productPriceCtrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        labelText: 'Precio (opc.)',
                                        prefixText: Currency.prefix,
                                        errorText: _fieldError('product_price'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // ── Sección: Movimiento ───────────────────────────────
                        _FormCard(
                          icon: Icons.receipt_long_rounded,
                          iconColor: AppPalette.aqua,
                          title: 'Detalles del movimiento',
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _movementDateCtrl,
                                readOnly: true,
                                onTap: controller.submittingEntry ? null : _pickMovementDate,
                                decoration: InputDecoration(
                                  labelText: 'Fecha del movimiento',
                                  prefixIcon: const Icon(Icons.calendar_today_rounded),
                                  suffixIcon: const Icon(Icons.edit_calendar_rounded),
                                  errorText: _fieldError('movement_date'),
                                ),
                                validator: (value) => (value == null || value.trim().isEmpty) ? 'Requerido' : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _referenceCtrl,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: upperCaseFormatters,
                                decoration: InputDecoration(
                                  labelText: 'Referencia (opcional)',
                                  prefixIcon: const Icon(Icons.tag_rounded),
                                  errorText: _fieldError('reference'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _notesCtrl,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: upperCaseFormatters,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: 'Notas (opcional)',
                                  prefixIcon: const Icon(Icons.edit_note_rounded),
                                  errorText: _fieldError('notes'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE6EEF5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Imagenes del ingreso',
                                      style: TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink),
                                    ),
                                  ),
                                  Text(
                                    '${_images.length}/$_maxImages',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Puedes tomar fotos o elegir desde galeria (max 20, 5MB c/u).',
                                style: TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                              ),
                              if (_fieldError('images') != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _fieldError('images')!,
                                  style: const TextStyle(fontSize: 12, color: AppPalette.rose),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  GestureDetector(
                                    onTap: controller.submittingEntry ? null : _showImageSourcePicker,
                                    child: Container(
                                      width: 84,
                                      height: 84,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F7FB),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFD4DEE7)),
                                      ),
                                      child: const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_a_photo_rounded, color: AppPalette.deepBlue),
                                          SizedBox(height: 2),
                                          Text('Agregar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ...List.generate(_images.length, (index) {
                                    final file = _images[index];
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.file(File(file.path), width: 84, height: 84, fit: BoxFit.cover),
                                        ),
                                        Positioned(
                                          right: -6,
                                          top: -6,
                                          child: GestureDetector(
                                            onTap: controller.submittingEntry ? null : () => _removeImageAt(index),
                                            child: Container(
                                              width: 22,
                                              height: 22,
                                              decoration: const BoxDecoration(
                                                color: AppPalette.rose,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (controller.submitError != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppPalette.rose.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppPalette.rose.withValues(alpha: 0.3)),
                            ),
                            child: Text(controller.submitError!, style: const TextStyle(color: AppPalette.rose)),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: controller.submittingEntry ? null : _submit,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              backgroundColor: AppPalette.deepBlue,
                            ),
                            icon: controller.submittingEntry
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: Text(controller.submittingEntry ? 'Guardando...' : 'Registrar ingreso'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.icon, required this.iconColor, required this.title, required this.child});

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EEF5)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppPalette.ink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}
