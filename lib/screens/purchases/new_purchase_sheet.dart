import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/upper_case.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';

/// Registrar una compra (como la web): categoría y datos del producto según la categoría,
/// cliente existente o nuevo, monto pagado (sale de la caja abierta), precio de venta y fotos.
/// El producto entra al almacén de la sucursal de la caja. Devuelve el id de la compra creada.
class NewPurchaseSheet extends StatefulWidget {
  const NewPurchaseSheet({super.key, required this.api, required this.logger});

  final ApiService api;
  final ErrorLogService logger;

  @override
  State<NewPurchaseSheet> createState() => _NewPurchaseSheetState();
}

class _NewPurchaseSheetState extends State<NewPurchaseSheet> {
  final _money = Currency.formatter();
  final _imagePicker = ImagePicker();

  bool _loading = true;
  String? _loadError;
  Map<String, dynamic> _options = {};

  // Categoría y producto
  int? _categoryId;
  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  int? _modelYear;
  final _plateCtrl = TextEditingController();
  final _chassisCtrl = TextEditingController();
  final _itemTypeCtrl = TextEditingController();
  String? _karat;
  String? _material;
  final _serialCtrl = TextEditingController();
  final _itemModelCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();

  // Cliente: existente (búsqueda) o nuevo
  bool _newClient = false;
  final _clientSearchCtrl = TextEditingController();
  Timer? _debounce;
  bool _searchingClients = false;
  List<Map<String, dynamic>> _clientResults = [];
  Map<String, dynamic>? _client;
  final _clientNameCtrl = TextEditingController();
  final _clientIdNumberCtrl = TextEditingController();
  final _clientPhoneCtrl = TextEditingController();

  // Pago
  final _amountCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<String> _imagePaths = [];

  bool _saving = false;
  String? _serverError;
  Map<String, String> _fieldErrors = {};
  // Se reutiliza en los reintentos: si el primer envío llegó, el servidor no duplica la compra.
  String _requestId = newRequestId();

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() => setState(() {}));
    _priceCtrl.addListener(() => setState(() {}));
    _loadOptions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _nameCtrl, _brandCtrl, _plateCtrl, _chassisCtrl, _itemTypeCtrl, _serialCtrl, _itemModelCtrl, _detailsCtrl,
      _clientSearchCtrl, _clientNameCtrl, _clientIdNumberCtrl, _clientPhoneCtrl, _amountCtrl, _priceCtrl, _notesCtrl,
    ]) {
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
      _options = await widget.api.purchaseOptions();
    } catch (e, st) {
      await widget.logger.logError(module: 'new_purchase', error: e, stackTrace: st, endpoint: '/purchases/options');
      _loadError = apiErrorMessage(e, fallback: 'No se pudieron cargar los datos para la compra.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _categories =>
      ((_options['categories'] as List?) ?? const []).whereType<Map>().map((c) => Map<String, dynamic>.from(c)).toList();

  List<String> _optionList(String key) => ((_options[key] as List?) ?? const []).map((v) => '$v').toList();

  /// Formulario del producto: 1 vehículo, 2 joyas, 3 garrafas, 4 artículos (lo indica la API).
  int? get _form {
    for (final c in _categories) {
      if (int.tryParse('${c['id']}') == _categoryId) return int.tryParse('${c['form']}') ?? 4;
    }
    return null;
  }

  double? get _available => _options['available_cash'] == null ? null : asDouble(_options['available_cash']);
  double get _amount => double.tryParse(_amountCtrl.text.replaceAll(',', '.').trim()) ?? 0;
  double get _price => double.tryParse(_priceCtrl.text.replaceAll(',', '.').trim()) ?? 0;

  void _onCategoryChanged(int? id) {
    setState(() {
      _categoryId = id;
      _modelYear = null;
      _karat = null;
      _material = null;
      _fieldErrors = {};
      for (final c in [_nameCtrl, _brandCtrl, _plateCtrl, _chassisCtrl, _itemTypeCtrl, _serialCtrl, _itemModelCtrl]) {
        c.clear();
      }
    });
  }

  void _onClientSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (value.trim().isEmpty) {
        setState(() => _clientResults = []);
        return;
      }
      setState(() => _searchingClients = true);
      try {
        final data = await widget.api.clients(query: value.trim(), perPage: 10, active: true);
        if (!mounted) return;
        setState(() => _clientResults =
            ((data['data'] as List?) ?? const []).whereType<Map>().map((c) => Map<String, dynamic>.from(c)).toList());
      } catch (_) {
        if (mounted) setState(() => _clientResults = []);
      } finally {
        if (mounted) setState(() => _searchingClients = false);
      }
    });
  }

  Future<void> _addImage() async {
    if (_imagePaths.length >= 20) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _imagePicker.pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (picked != null && mounted) setState(() => _imagePaths.add(picked.path));
  }

  // ── Enviar ────────────────────────────────────────────────────────────────

  /// Mismas reglas que la web (PurchaseService): campos obligatorios según la categoría.
  String? _validate() {
    if (_categoryId == null) return 'Selecciona la categoría del producto.';
    String? req(TextEditingController c, String msg) => c.text.trim().isEmpty ? msg : null;
    final productError = switch (_form) {
      1 => req(_nameCtrl, 'El nombre es obligatorio para vehículos.') ??
          req(_brandCtrl, 'La marca es obligatoria para vehículos.') ??
          (_modelYear == null ? 'El modelo (año) es obligatorio para vehículos.' : null) ??
          req(_plateCtrl, 'La placa es obligatoria para vehículos.') ??
          req(_chassisCtrl, 'El chasis es obligatorio para vehículos.'),
      2 => req(_itemTypeCtrl, 'El tipo de joya es obligatorio.') ??
          (_karat == null ? 'Selecciona el kilataje de la joya.' : null),
      3 => null,
      _ => req(_nameCtrl, 'El nombre es obligatorio para artículos.') ??
          req(_brandCtrl, 'La marca es obligatoria para artículos.') ??
          req(_serialCtrl, 'El serial es obligatorio para artículos.'),
    };
    if (productError != null) return productError;
    if (_newClient ? _clientNameCtrl.text.trim().isEmpty : _client == null) {
      return 'Selecciona un cliente o escribe el nombre del cliente nuevo.';
    }
    if (_amount <= 0) return 'Ingresa el monto de la compra.';
    if (_available != null && _amount > _available! + 0.001) {
      return 'El monto supera el saldo disponible en caja (${_money.format(_available)}).';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final error = _validate();
    if (error != null) {
      setState(() => _serverError = error);
      return;
    }
    setState(() {
      _saving = true;
      _serverError = null;
      _fieldErrors = {};
    });
    final form = _form;
    try {
      final result = await widget.api.createPurchase(
        fields: {
          'credit_category_id': _categoryId,
          if (form == 1 || form == 4) 'product_name': _nameCtrl.text.trim(),
          if (form == 1 || form == 4) 'product_brand': _brandCtrl.text.trim(),
          if (form == 1) 'product_model_year': _modelYear,
          if (form == 1) 'product_plate': _plateCtrl.text.trim(),
          if (form == 1) 'product_chassis': _chassisCtrl.text.trim(),
          if (form == 2) 'product_item_type': _itemTypeCtrl.text.trim(),
          if (form == 2) 'product_karat': _karat,
          if (form == 2) 'product_material_type': _material,
          if (form == 4) 'product_serial_number': _serialCtrl.text.trim(),
          if (form == 4) 'product_item_model': _itemModelCtrl.text.trim(),
          'product_details': _detailsCtrl.text.trim(),
          if (_price > 0) 'product_price': _price,
          if (!_newClient) 'client_id': _client?['id'],
          if (_newClient) 'client_name': _clientNameCtrl.text.trim(),
          if (_newClient) 'client_id_number': _clientIdNumberCtrl.text.trim(),
          if (_newClient) 'client_phone': _clientPhoneCtrl.text.trim(),
          'amount': _amount,
          'notes': _notesCtrl.text.trim(),
        },
        imagePaths: List.unmodifiable(_imagePaths),
        requestId: _requestId,
      );
      _requestId = newRequestId();
      final purchase = result['purchase'];
      if (mounted) Navigator.pop(context, purchase is Map ? int.tryParse('${purchase['id']}') : null);
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'new_purchase', error: e, stackTrace: st, endpoint: '/purchases');
      }
      if (!mounted) return;
      setState(() {
        _serverError = apiErrorMessage(e, fallback: 'No fue posible registrar la compra.');
        _fieldErrors = _errorsByField(e);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Errores 422 por campo, para marcarlos en el formulario (el primero ya se muestra arriba).
  static Map<String, String> _errorsByField(Object e) {
    final response = e is DioException ? e.response?.data : null;
    final errors = response is Map ? response['errors'] : null;
    if (errors is! Map) return {};
    return {
      for (final entry in errors.entries)
        '${entry.key}': entry.value is List && (entry.value as List).isNotEmpty ? '${(entry.value as List).first}' : '${entry.value}',
    };
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final branch = _options['branch'];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF4F8FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: const Color(0xFFCDD8E3), borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Nueva compra',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.ink)),
                      if (branch is Map)
                        Text('Sucursal ${branch['name']} · el producto entra al almacén de tu caja',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    final cashError = _loadError ?? _options['cash_session_error']?.toString();
    if (cashError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(cashError, textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.rose)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _loadOptions, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section('Producto', Icons.inventory_2_rounded, _buildProduct()),
          _section('Cliente (vendedor)', Icons.person_rounded, _buildClient()),
          _section('Pago', Icons.payments_rounded, _buildPayment()),
          _section('Fotos (opcional)', Icons.photo_camera_rounded, _buildImages()),
          if (_serverError != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.rose.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppPalette.rose.withValues(alpha: 0.3)),
              ),
              child: Text(_serverError!, style: const TextStyle(color: AppPalette.rose, fontSize: 13)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: AppPalette.deepBlue, minimumSize: const Size.fromHeight(50)),
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Registrando...' : 'Registrar compra'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, Widget child) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6EEF5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: AppPalette.deepBlue),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _text(TextEditingController ctrl, String label, String field, {int maxLines = 1, bool upper = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          textCapitalization: upper ? TextCapitalization.characters : TextCapitalization.none,
          inputFormatters: upper ? upperCaseFormatters : null,
          decoration: InputDecoration(labelText: label, isDense: true, errorText: _fieldErrors[field]),
        ),
      );

  Widget _buildProduct() {
    final currentYear = DateTime.now().year;
    final form = _form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_categories.isEmpty)
          const Text('La empresa no tiene categorías activas.', style: TextStyle(color: AppPalette.rose))
        else
          DropdownButtonFormField<int>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Categoría *', isDense: true, errorText: _fieldErrors['credit_category_id']),
            items: [
              for (final c in _categories)
                DropdownMenuItem(value: int.tryParse('${c['id']}'), child: Text('${c['name']}')),
            ],
            onChanged: _onCategoryChanged,
          ),
        if (form != null) const SizedBox(height: 10),
        if (form == 1) ...[
          _text(_nameCtrl, 'Nombre / modelo *', 'product_name'),
          _text(_brandCtrl, 'Marca *', 'product_brand'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<int>(
              initialValue: _modelYear,
              decoration: InputDecoration(labelText: 'Año del modelo *', isDense: true, errorText: _fieldErrors['product_model_year']),
              items: [
                for (var y = currentYear + 1; y >= 1980; y--) DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (v) => setState(() => _modelYear = v),
            ),
          ),
          _text(_plateCtrl, 'Placa *', 'product_plate'),
          _text(_chassisCtrl, 'Chasis *', 'product_chassis'),
        ],
        if (form == 2) ...[
          _text(_itemTypeCtrl, 'Tipo de joya * (ej. collar, anillo)', 'product_item_type'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<String>(
              initialValue: _karat,
              decoration: InputDecoration(labelText: 'Kilataje *', isDense: true, errorText: _fieldErrors['product_karat']),
              items: [for (final k in _optionList('karats')) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => setState(() => _karat = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<String>(
              initialValue: _material,
              decoration: InputDecoration(labelText: 'Tipo de material', isDense: true, errorText: _fieldErrors['product_material_type']),
              items: [for (final m in _optionList('materials')) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _material = v),
            ),
          ),
        ],
        if (form == 4) ...[
          _text(_nameCtrl, 'Nombre *', 'product_name'),
          _text(_brandCtrl, 'Marca *', 'product_brand'),
          _text(_itemModelCtrl, 'Modelo (ej. ThinkPad E15)', 'product_item_model'),
          _text(_serialCtrl, 'Serial *', 'product_serial_number'),
        ],
        if (form != null) _text(_detailsCtrl, 'Observaciones / detalles', 'product_details', maxLines: 2),
      ],
    );
  }

  Widget _buildClient() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Existente'), icon: Icon(Icons.search_rounded, size: 16)),
            ButtonSegment(value: true, label: Text('Nuevo'), icon: Icon(Icons.person_add_rounded, size: 16)),
          ],
          selected: {_newClient},
          onSelectionChanged: (s) => setState(() => _newClient = s.first),
        ),
        const SizedBox(height: 10),
        if (_newClient) ...[
          _text(_clientNameCtrl, 'Nombre completo *', 'client_name'),
          _text(_clientIdNumberCtrl, 'Documento', 'client_id_number'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _clientPhoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Teléfono', isDense: true, errorText: _fieldErrors['client_phone']),
            ),
          ),
        ] else if (_client != null)
          Row(
            children: [
              const Icon(Icons.person_rounded, color: AppPalette.deepBlue),
              const SizedBox(width: 8),
              Expanded(child: Text('${_client!['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => setState(() => _client = null), child: const Text('Cambiar')),
            ],
          )
        else ...[
          TextField(
            controller: _clientSearchCtrl,
            onChanged: _onClientSearch,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o documento...',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              errorText: _fieldErrors['client_id'],
              suffixIcon: _searchingClients
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
            ),
          ),
          for (final c in _clientResults.take(6))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${c['name']}'),
              subtitle: c['id_number'] != null ? Text('${c['id_number']}') : null,
              onTap: () => setState(() {
                _client = c;
                _clientResults = [];
                _clientSearchCtrl.clear();
              }),
            ),
        ],
      ],
    );
  }

  Widget _buildPayment() {
    final over = _available != null && _amount > _available! + 0.001;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Monto que se paga al cliente *',
            prefixText: Currency.prefix,
            isDense: true,
            errorText: over ? 'Supera el saldo disponible en caja' : _fieldErrors['amount'],
            helperText: _available == null ? null : 'Disponible en caja: ${_money.format(_available)}',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _priceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Precio de venta (opcional)',
            prefixText: Currency.prefix,
            isDense: true,
            errorText: _fieldErrors['product_price'],
            helperText: _price > 0 && _amount > 0 ? 'Ganancia estimada: ${_money.format(_price - _amount)}' : null,
          ),
        ),
        const SizedBox(height: 10),
        _text(_notesCtrl, 'Notas (opcional)', 'notes', maxLines: 2),
      ],
    );
  }

  Widget _buildImages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_imagePaths.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _imagePaths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_imagePaths[i]), width: 80, height: 80, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _imagePaths.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_imagePaths.isNotEmpty) const SizedBox(height: 8),
        if (_imagePaths.length < 20)
          OutlinedButton.icon(
            onPressed: _addImage,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: Text(_imagePaths.isEmpty ? 'Agregar foto' : 'Agregar otra foto'),
          ),
      ],
    );
  }
}
