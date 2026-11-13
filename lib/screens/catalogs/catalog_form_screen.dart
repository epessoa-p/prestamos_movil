import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';
import '../../utils/upper_case.dart';
import '../../utils/color_utils.dart';

/// Crear o editar un catálogo (mismas reglas que la web: CatalogService). Devuelve el id al guardar.
class CatalogFormScreen extends StatefulWidget {
  const CatalogFormScreen({super.key, required this.api, required this.logger, this.initial});

  final ApiService api;
  final ErrorLogService logger;

  /// Respuesta de GET /catalogs/{id} para editar; null = nuevo.
  final Map<String, dynamic>? initial;

  @override
  State<CatalogFormScreen> createState() => _CatalogFormScreenState();
}

class _Selected {
  _Selected(this.product, {this.customPrice, this.customName});

  final Map<String, dynamic> product;
  double? customPrice;
  String? customName;

  int get id => asInt(product['id']);
}

class _CatalogFormScreenState extends State<CatalogFormScreen> {
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _money = Currency.formatter();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  Map<String, String> _errors = {};

  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _pool = [];
  List<String> _colors = [];
  int? _lockedBranchId;

  int? _branchId;
  String _color = '#0d6efd';
  bool _showPrices = true;
  bool _showContact = true;
  DateTime? _expiresAt;
  String? _logoPath;
  String? _currentLogoUrl;
  final List<_Selected> _selected = [];

  Map<String, dynamic> get _catalog =>
      widget.initial?['catalog'] is Map ? Map<String, dynamic>.from(widget.initial!['catalog']) : {};
  int? get _catalogId => widget.initial == null ? null : asInt(_catalog['id']);
  bool get _editing => _catalogId != null;

  @override
  void initState() {
    super.initState();
    final c = _catalog;
    if (_editing) {
      _titleCtrl.text = '${c['title'] ?? ''}';
      _descriptionCtrl.text = '${c['description'] ?? ''}';
      _phoneCtrl.text = '${c['contact_phone'] ?? ''}';
      _whatsappCtrl.text = '${c['contact_whatsapp'] ?? ''}';
      _emailCtrl.text = '${c['contact_email'] ?? ''}';
      _branchId = c['branch_id'] == null ? null : asInt(c['branch_id']);
      _color = '${c['cover_color'] ?? '#0d6efd'}';
      _showPrices = c['show_prices'] != false;
      _showContact = c['show_contact'] != false;
      _expiresAt = DateTime.tryParse('${c['expires_at'] ?? ''}')?.toLocal();
      _currentLogoUrl = c['logo_url'] as String?;
    }
    _loadOptions();
  }

  @override
  void dispose() {
    for (final c in [_titleCtrl, _descriptionCtrl, _phoneCtrl, _whatsappCtrl, _emailCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await widget.api.catalogOptions(catalogId: _catalogId);
      if (!mounted) return;
      List<Map<String, dynamic>> list(String k) =>
          (data[k] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      setState(() {
        _branches = list('branches');
        _pool = list('products');
        _colors = (data['colors'] as List? ?? const []).map((c) => '$c').toList();
        _lockedBranchId = data['locked_branch_id'] == null ? null : asInt(data['locked_branch_id']);
        if (_lockedBranchId != null) _branchId = _lockedBranchId;
        if (_editing && _selected.isEmpty) {
          final byId = {for (final p in _pool) asInt(p['id']): p};
          for (final item in (_catalog['items'] as List? ?? const []).whereType<Map>()) {
            final pid = asInt(item['product_id']);
            final product = byId[pid] ??
                {'id': pid, 'name': item['product_name'] ?? item['name'], 'price': item['price'], 'image': item['image'], 'available': false};
            _selected.add(_Selected(
              product,
              customPrice: item['custom_price'] == null ? null : asDouble(item['custom_price']),
              customName: item['custom_name'] as String?,
            ));
          }
        }
      });
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'catalog_form', error: e, stackTrace: st, endpoint: '/catalogs/options');
      }
      if (mounted) setState(() => _loadError = apiErrorMessage(e, fallback: 'No se pudieron cargar los productos.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onBranchChanged(int? id) {
    setState(() => _branchId = id);
    // Como la web: al elegir sucursal se sugieren su teléfono y correo si están vacíos.
    final branch = _branches.where((b) => asInt(b['id']) == id).firstOrNull;
    if (branch == null) return;
    if (_phoneCtrl.text.isEmpty && '${branch['phone'] ?? ''}'.isNotEmpty) _phoneCtrl.text = '${branch['phone']}';
    if (_whatsappCtrl.text.isEmpty && '${branch['phone'] ?? ''}'.isNotEmpty) _whatsappCtrl.text = '${branch['phone']}';
    if (_emailCtrl.text.isEmpty && '${branch['email'] ?? ''}'.isNotEmpty) _emailCtrl.text = '${branch['email']}';
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (file != null) setState(() => _logoPath = file.path);
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 30)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'El enlace funciona hasta…',
    );
    if (picked != null) setState(() => _expiresAt = DateTime(picked.year, picked.month, picked.day, 23, 59));
  }

  Future<void> _addProducts() async {
    final chosen = await Navigator.push<Set<int>>(
      context,
      MaterialPageRoute(
        builder: (_) => _ProductPicker(pool: _pool, selected: _selected.map((s) => s.id).toSet()),
      ),
    );
    if (chosen == null) return;
    setState(() {
      _selected.removeWhere((s) => !chosen.contains(s.id));
      final existing = _selected.map((s) => s.id).toSet();
      for (final p in _pool) {
        final id = asInt(p['id']);
        if (chosen.contains(id) && !existing.contains(id)) _selected.add(_Selected(p));
      }
      _errors.remove('products');
    });
  }

  Future<void> _editItem(_Selected s) async {
    final priceCtrl = TextEditingController(text: s.customPrice?.toStringAsFixed(2) ?? '');
    final nameCtrl = TextEditingController(text: s.customName ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.product['name'] ?? 'Producto'}', maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: upperCaseFormatters,
              decoration: const InputDecoration(labelText: 'Nombre en el catálogo (opcional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Precio en el catálogo (opcional)',
                prefixText: Currency.prefix,
                helperText: 'Vacío = precio del producto (${_money.format(asDouble(s.product['price']))})',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aceptar')),
        ],
      ),
    );
    if (save == true) {
      setState(() {
        final price = double.tryParse(priceCtrl.text.trim().replaceAll(',', '.'));
        s.customPrice = price != null && price >= 0 ? price : null;
        s.customName = nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim();
      });
    }
    priceCtrl.dispose();
    nameCtrl.dispose();
  }

  Future<void> _save() async {
    if (_saving) return; // evita doble envío
    final errors = <String, String>{};
    if (_titleCtrl.text.trim().isEmpty) errors['title'] = 'Escribe el título del catálogo.';
    if (_selected.isEmpty) errors['products'] = 'Agrega al menos un producto al catálogo.';
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }

    setState(() {
      _saving = true;
      _errors = {};
    });
    final data = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'description': _descriptionCtrl.text.trim(),
      'branch_id': _branchId,
      'cover_color': _color,
      'show_prices': _showPrices,
      'show_contact': _showContact,
      'contact_phone': _phoneCtrl.text.trim(),
      'contact_whatsapp': _whatsappCtrl.text.trim(),
      'contact_email': _emailCtrl.text.trim(),
      'expires_at': _expiresAt == null ? null : DateFormat('yyyy-MM-dd HH:mm:ss').format(_expiresAt!),
      'products': [
        for (final s in _selected)
          {
            'product_id': s.id,
            if (s.customPrice != null) 'custom_price': s.customPrice,
            if (s.customName != null) 'custom_name': s.customName,
          },
      ],
    };
    try {
      final result = await widget.api.saveCatalog(data, catalogId: _catalogId, logoPath: _logoPath);
      if (!mounted) return;
      final id = asInt((result['catalog'] as Map?)?['id'], fallback: _catalogId ?? 0);
      Navigator.pop(context, id);
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'catalog_save', error: e, stackTrace: st, endpoint: '/catalogs');
      }
      if (!mounted) return;
      final fieldErrors = <String, String>{};
      if (e is DioException && e.response?.data is Map && (e.response!.data as Map)['errors'] is Map) {
        ((e.response!.data as Map)['errors'] as Map).forEach((k, v) {
          final key = '$k'.startsWith('products') ? 'products' : '$k';
          fieldErrors.putIfAbsent(key, () => v is List && v.isNotEmpty ? '${v.first}' : '$v');
        });
      }
      setState(() {
        _saving = false;
        _errors = fieldErrors;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(e, fallback: 'No se pudo guardar el catálogo.')),
        backgroundColor: AppPalette.rose,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(_color) ?? AppPalette.deepBlue;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        title: Text(_editing ? 'Editar catálogo' : 'Nuevo catálogo'),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: color),
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Guardando…' : (_editing ? 'Guardar cambios' : 'Crear catálogo')),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(padding: const EdgeInsets.all(16), child: Text(_loadError!, textAlign: TextAlign.center)),
                      FilledButton(onPressed: _loadOptions, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    _section('Datos del catálogo', [
                      TextField(
                        controller: _titleCtrl,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: upperCaseFormatters,
                        decoration: InputDecoration(labelText: 'Título *', errorText: _errors['title']),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _descriptionCtrl,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: upperCaseFormatters,
                        decoration: InputDecoration(labelText: 'Descripción (opcional)', errorText: _errors['description']),
                      ),
                      const SizedBox(height: 10),
                      if (_lockedBranchId != null)
                        Text(
                          'Sucursal: ${_branches.where((b) => asInt(b['id']) == _lockedBranchId).map((b) => b['name']).firstOrNull ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )
                      else
                        DropdownButtonFormField<int?>(
                          initialValue: _branchId,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: 'Sucursal', errorText: _errors['branch_id']),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('Todas las sucursales')),
                            for (final b in _branches) DropdownMenuItem<int?>(value: asInt(b['id']), child: Text('${b['name']}')),
                          ],
                          onChanged: _onBranchChanged,
                        ),
                    ]),
                    _section('Apariencia', [
                      const Text('Color', style: TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final hex in _colors)
                            GestureDetector(
                              onTap: () => setState(() => _color = hex),
                              child: CircleAvatar(
                                radius: 17,
                                backgroundColor: parseHexColor(hex) ?? Colors.grey,
                                child: hex.toLowerCase() == _color.toLowerCase()
                                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (_logoPath != null || _currentLogoUrl != null)
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF2A9D8F), size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _logoPath != null
                                  ? 'Logo nuevo elegido'
                                  : _currentLogoUrl != null
                                      ? 'Tiene logo (puedes cambiarlo)'
                                      : 'Sin logo',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          TextButton.icon(onPressed: _pickLogo, icon: const Icon(Icons.image_rounded), label: const Text('Logo')),
                        ],
                      ),
                      if (_errors['logo'] != null) Text(_errors['logo']!, style: const TextStyle(color: AppPalette.rose, fontSize: 12)),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostrar precios'),
                        value: _showPrices,
                        onChanged: (v) => setState(() => _showPrices = v),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _expiresAt == null
                                  ? 'El enlace no vence'
                                  : 'Disponible hasta ${DateFormat('dd/MM/yyyy').format(_expiresAt!)}',
                            ),
                          ),
                          if (_expiresAt != null)
                            IconButton(
                              tooltip: 'Quitar vencimiento',
                              onPressed: () => setState(() => _expiresAt = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          TextButton(onPressed: _pickExpiry, child: const Text('Elegir fecha')),
                        ],
                      ),
                      if (_errors['expires_at'] != null)
                        Text(_errors['expires_at']!, style: const TextStyle(color: AppPalette.rose, fontSize: 12)),
                    ]),
                    _section('Contacto', [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostrar contacto'),
                        value: _showContact,
                        onChanged: (v) => setState(() => _showContact = v),
                      ),
                      if (_showContact) ...[
                        TextField(
                          controller: _whatsappCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(labelText: 'WhatsApp', errorText: _errors['contact_whatsapp']),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(labelText: 'Teléfono', errorText: _errors['contact_phone']),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(labelText: 'Email', errorText: _errors['contact_email']),
                        ),
                      ],
                    ]),
                    _productsSection(color),
                  ],
                ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _productsSection(Color color) {
    return _section('Productos (${_selected.length})', [
      if (_errors['products'] != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_errors['products']!, style: const TextStyle(color: AppPalette.rose, fontWeight: FontWeight.w600)),
        ),
      OutlinedButton.icon(
        onPressed: _addProducts,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: Text(_selected.isEmpty ? 'Elegir productos' : 'Agregar o quitar productos'),
      ),
      if (_pool.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('No hay productos disponibles para la venta en el inventario.', style: TextStyle(fontSize: 12)),
        ),
      if (_selected.isNotEmpty) ...[
        const SizedBox(height: 6),
        const Text('Mantén presionado y arrastra para ordenar. Toca para poner un nombre o precio propio.',
            style: TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (oldIndex, newIndex) => setState(() {
            if (newIndex > oldIndex) newIndex--;
            _selected.insert(newIndex, _selected.removeAt(oldIndex));
          }),
          children: [
            for (var i = 0; i < _selected.length; i++)
              ReorderableDelayedDragStartListener(
                key: ValueKey(_selected[i].id),
                index: i,
                child: _selectedTile(_selected[i], color),
              ),
          ],
        ),
      ],
    ]);
  }

  Widget _selectedTile(_Selected s, Color color) {
    final p = s.product;
    final image = '${p['image'] ?? ''}';
    final price = s.customPrice ?? asDouble(p['price']);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _editItem(s),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: image.isEmpty
              ? Container(color: const Color(0xFFF0F4F8), child: const Icon(Icons.inventory_2_outlined, size: 20))
              : Image.network(image, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: const Color(0xFFF0F4F8), child: const Icon(Icons.image_outlined))),
        ),
      ),
      title: Text(s.customName ?? '${p['name'] ?? 'Producto'}', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          _money.format(price),
          if (s.customPrice != null) 'precio propio',
          if (p['available'] == false) 'ya no disponible',
        ].join(' · '),
        style: TextStyle(fontSize: 12, color: p['available'] == false ? AppPalette.rose : color),
      ),
      trailing: IconButton(
        tooltip: 'Quitar',
        onPressed: () => setState(() => _selected.remove(s)),
        icon: const Icon(Icons.remove_circle_outline_rounded),
      ),
    );
  }
}

/// Selector de productos disponibles: buscador, filtro por categoría y "seleccionar todos".
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.pool, required this.selected});

  final List<Map<String, dynamic>> pool;
  final Set<int> selected;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  late final Set<int> _chosen = {...widget.selected};
  final _money = Currency.formatter();
  String _q = '';
  String? _category;

  List<Map<String, dynamic>> get _visible {
    final q = _q.toLowerCase();
    return widget.pool.where((p) {
      if (p['available'] == false && !_chosen.contains(asInt(p['id']))) return false;
      if (_category != null && '${p['category'] ?? ''}' != _category) return false;
      if (q.isEmpty) return true;
      return '${p['name']} ${p['detail']} ${p['category']}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final categories = widget.pool.map((p) => '${p['category'] ?? ''}').where((c) => c.isNotEmpty).toSet().toList()..sort();
    final allVisibleChosen = visible.isNotEmpty && visible.every((p) => _chosen.contains(asInt(p['id'])));

    return Scaffold(
      appBar: AppBar(
        title: Text('Productos (${_chosen.length})'),
        backgroundColor: AppPalette.deepBlue,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _chosen),
            child: const Text('Listo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'Buscar producto...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(label: const Text('Todas'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
                ),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
                  ),
              ],
            ),
          ),
          CheckboxListTile(
            dense: true,
            title: Text('Seleccionar los ${visible.length} visibles'),
            value: allVisibleChosen,
            onChanged: visible.isEmpty
                ? null
                : (v) => setState(() {
                      for (final p in visible) {
                        v == true ? _chosen.add(asInt(p['id'])) : _chosen.remove(asInt(p['id']));
                      }
                    }),
          ),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('No hay productos con ese criterio.'))
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final p = visible[i];
                      final id = asInt(p['id']);
                      final image = '${p['image'] ?? ''}';
                      return CheckboxListTile(
                        value: _chosen.contains(id),
                        onChanged: (v) => setState(() => v == true ? _chosen.add(id) : _chosen.remove(id)),
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: image.isEmpty
                                ? Container(color: const Color(0xFFF0F4F8), child: const Icon(Icons.inventory_2_outlined, size: 20))
                                : Image.network(image, fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        Container(color: const Color(0xFFF0F4F8), child: const Icon(Icons.image_outlined))),
                          ),
                        ),
                        title: Text('${p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            _money.format(asDouble(p['price'])),
                            if ('${p['category'] ?? ''}'.isNotEmpty) '${p['category']}',
                            if (p['origin'] != null) '${p['origin']}',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
