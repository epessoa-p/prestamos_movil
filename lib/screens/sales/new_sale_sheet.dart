import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/upper_case.dart';
import '../../utils/api_errors.dart';
import '../../utils/number_utils.dart';
import '../../utils/currency.dart';

/// Registrar una venta (como la web): producto disponible en el almacén de la caja abierta,
/// cliente existente o nuevo, contado o crédito (recargo, cuota inicial y cuotas).
/// Devuelve el id de la venta creada.
class NewSaleSheet extends StatefulWidget {
  const NewSaleSheet({super.key, required this.api, required this.logger});

  final ApiService api;
  final ErrorLogService logger;

  @override
  State<NewSaleSheet> createState() => _NewSaleSheetState();
}

class _NewSaleSheetState extends State<NewSaleSheet> {
  final _money = Currency.formatter();
  final _dateFmt = DateFormat('dd/MM/yyyy');

  bool _loading = true;
  String? _loadError;
  Map<String, dynamic> _options = {};

  // Producto
  final _productSearchCtrl = TextEditingController();
  Map<String, dynamic>? _product;

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
  String _paymentType = 'CONTADO';
  final _amountCtrl = TextEditingController();
  final _surchargeCtrl = TextEditingController();
  final _downPaymentCtrl = TextEditingController();
  int _installmentsCount = 3;
  DateTime _firstDueDate = DateTime(DateTime.now().year, DateTime.now().month + 1, DateTime.now().day);
  final _notesCtrl = TextEditingController();

  bool _saving = false;
  String? _serverError;
  // Se reutiliza en los reintentos: si el primer envío llegó, el servidor no duplica la venta.
  String _requestId = newRequestId();

  @override
  void initState() {
    super.initState();
    for (final c in [_amountCtrl, _surchargeCtrl, _downPaymentCtrl, _productSearchCtrl]) {
      c.addListener(() => setState(() {}));
    }
    _loadOptions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _productSearchCtrl, _clientSearchCtrl, _clientNameCtrl, _clientIdNumberCtrl, _clientPhoneCtrl,
      _amountCtrl, _surchargeCtrl, _downPaymentCtrl, _notesCtrl,
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
      _options = await widget.api.saleOptions();
    } catch (e, st) {
      await widget.logger.logError(module: 'new_sale', error: e, stackTrace: st, endpoint: '/sales/options');
      _loadError = apiErrorMessage(e, fallback: 'No se pudieron cargar los productos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _products =>
      ((_options['products'] as List?) ?? const []).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim());

  // ── Cálculos del crédito (mismos que la web) ──────────────────────────────

  double get _amount => _num(_amountCtrl) ?? 0;
  double get _surchargePct => _num(_surchargeCtrl) ?? 0;
  double get _surchargeAmount => _round2(_amount * _surchargePct / 100);
  double get _creditTotal => _round2(_amount + _surchargeAmount);
  double get _downPayment => _num(_downPaymentCtrl) ?? 0;
  double get _financed => _round2((_creditTotal - _downPayment).clamp(0, double.infinity).toDouble());

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  /// Cuotas iguales mensuales que suman exactamente el saldo a financiar (la última ajusta el redondeo).
  List<Map<String, dynamic>> get _installments {
    final n = _installmentsCount;
    if (_financed <= 0 || n <= 0) return [];
    final base = (_financed / n * 100).floorToDouble() / 100;
    final basePct = (100 / n * 10000).floorToDouble() / 10000;
    return List.generate(n, (i) {
      final last = i == n - 1;
      final due = DateTime(_firstDueDate.year, _firstDueDate.month + i, _firstDueDate.day);
      return {
        'due_date': DateFormat('yyyy-MM-dd').format(due),
        'percentage': last ? double.parse((100 - basePct * (n - 1)).toStringAsFixed(4)) : basePct,
        'amount': last ? _round2(_financed - base * (n - 1)) : base,
      };
    });
  }

  // ── Clientes ──────────────────────────────────────────────────────────────

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

  // ── Enviar ────────────────────────────────────────────────────────────────

  String? _validate() {
    if (_product == null) return 'Selecciona el producto a vender.';
    if (_newClient ? _clientNameCtrl.text.trim().isEmpty : _client == null) {
      return 'Selecciona un cliente o escribe el nombre del cliente nuevo.';
    }
    if (_amount <= 0) return 'Ingresa el precio de venta.';
    if (_paymentType == 'CREDITO') {
      if (_surchargePct <= 0) return 'El recargo de crédito es obligatorio y debe ser mayor a 0.';
      if (_downPayment < 0) return 'La cuota inicial no puede ser negativa.';
      if (_downPayment > _creditTotal) return 'La cuota inicial no puede superar el total a crédito.';
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
    });
    final isCredit = _paymentType == 'CREDITO';
    try {
      final result = await widget.api.createSale(
        productId: int.parse('${_product!['id']}'),
        paymentType: _paymentType,
        amount: _amount,
        clientId: _newClient ? null : int.tryParse('${_client?['id']}'),
        clientName: _newClient ? _clientNameCtrl.text.trim() : null,
        clientIdNumber: _newClient ? _clientIdNumberCtrl.text.trim() : null,
        clientPhone: _newClient ? _clientPhoneCtrl.text.trim() : null,
        creditAdditionalPercentage: isCredit ? _surchargePct : null,
        downPayment: isCredit ? _downPayment : null,
        installments: isCredit ? _installments : const [],
        notes: _notesCtrl.text.trim(),
        requestId: _requestId,
      );
      _requestId = newRequestId();
      final sale = result['sale'];
      if (mounted) Navigator.pop(context, sale is Map ? int.tryParse('${sale['id']}') : null);
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'new_sale', error: e, stackTrace: st, endpoint: '/sales');
      }
      if (mounted) setState(() => _serverError = apiErrorMessage(e, fallback: 'No fue posible registrar la venta.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                      const Text('Nueva venta',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.ink)),
                      if (_options['branch'] is Map)
                        Text('Sucursal ${(_options['branch'] as Map)['name']} · almacén de tu caja',
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
          _section('Cliente', Icons.person_rounded, _buildClient()),
          _section('Pago', Icons.payments_rounded, _buildPayment()),
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
            label: Text(_saving ? 'Registrando...' : 'Registrar venta'),
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

  Widget _buildProduct() {
    if (_product != null) {
      final p = _product!;
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text([p['name'], p['brand']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
                Text('${p['category_name']} · ${p['origin_label']} · costo ${_money.format(asDouble(p['cost']))}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
              ],
            ),
          ),
          TextButton(onPressed: () => setState(() => _product = null), child: const Text('Cambiar')),
        ],
      );
    }

    final q = _productSearchCtrl.text.trim().toLowerCase();
    final list = _products.where((p) {
      if (q.isEmpty) return true;
      return [p['name'], p['brand'], p['category_name'], p['serial_number'], p['plate'], p['description']]
          .any((v) => v != null && '$v'.toLowerCase().contains(q));
    }).take(30).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _productSearchCtrl,
          decoration: const InputDecoration(
            hintText: 'Buscar producto (nombre, marca, serie, placa)...',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        if (_products.isEmpty)
          const Text('No hay productos disponibles para la venta en el almacén de tu caja.',
              style: TextStyle(color: Color(0xFF6A8299)))
        else if (list.isEmpty)
          const Text('Ningún producto coincide con la búsqueda.', style: TextStyle(color: Color(0xFF6A8299)))
        else
          for (final p in list)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: p['image_url'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network('${p['image_url']}', width: 40, height: 40, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.inventory_2_rounded)),
                    )
                  : const Icon(Icons.inventory_2_rounded, color: Color(0xFF9DB1C3)),
              title: Text([p['name'], p['brand']].where((v) => v != null && '$v'.isNotEmpty).join(' · ')),
              subtitle: Text('${p['category_name']} · ${p['origin_label']} · stock ${asDouble(p['stock']).toStringAsFixed(0)}'),
              trailing: asDouble(p['price']) > 0 ? Text(_money.format(asDouble(p['price']))) : null,
              onTap: () => setState(() {
                _product = p;
                if (_amountCtrl.text.trim().isEmpty && asDouble(p['price']) > 0) {
                  _amountCtrl.text = asDouble(p['price']).toStringAsFixed(2);
                }
              }),
            ),
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
          TextField(
            controller: _clientNameCtrl,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: upperCaseFormatters,
            decoration: const InputDecoration(labelText: 'Nombre completo *', isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _clientIdNumberCtrl,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: upperCaseFormatters,
            decoration: const InputDecoration(labelText: 'Documento', isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _clientPhoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono', isDense: true),
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
    final isCredit = _paymentType == 'CREDITO';
    final installments = isCredit ? _installments : const <Map<String, dynamic>>[];
    final cost = asDouble(_product?['cost']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'CONTADO', label: Text('Contado')),
            ButtonSegment(value: 'CREDITO', label: Text('Crédito')),
          ],
          selected: {_paymentType},
          onSelectionChanged: (s) => setState(() => _paymentType = s.first),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Precio de venta *',
            prefixText: Currency.prefix,
            isDense: true,
            helperText: _product != null && _amount > 0
                ? 'Ganancia estimada: ${_money.format(_amount - cost)}'
                : null,
          ),
        ),
        if (isCredit) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _surchargeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(labelText: 'Recargo *', suffixText: '%', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _downPaymentCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(labelText: 'Cuota inicial', prefixText: Currency.prefix, isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _installmentsCount,
                  decoration: const InputDecoration(labelText: 'Nº de cuotas', isDense: true),
                  items: [for (var i = 1; i <= 24; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() => _installmentsCount = v ?? 1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _firstDueDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) setState(() => _firstDueDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Primera cuota', isDense: true),
                    child: Text(_dateFmt.format(_firstDueDate)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.deepBlue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _line('Recargo', _money.format(_surchargeAmount)),
                _line('Total a crédito', _money.format(_creditTotal), bold: true),
                _line('Saldo a financiar', _money.format(_financed)),
                if (installments.isNotEmpty) ...[
                  const Divider(height: 14),
                  for (var i = 0; i < installments.length; i++)
                    _line(
                      'Cuota ${i + 1} · ${_dateFmt.format(DateTime.parse('${installments[i]['due_date']}'))}',
                      _money.format(asDouble(installments[i]['amount'])),
                    ),
                  const Text('Cuotas mensuales iguales; la última ajusta los centavos.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8EA5BC))),
                ] else if (_amount > 0)
                  const Text('La cuota inicial cubre todo: no se generan cuotas.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8EA5BC))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: upperCaseFormatters,
          decoration: const InputDecoration(labelText: 'Notas (opcional)', isDense: true),
        ),
      ],
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)))),
            Text(value,
                style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: AppPalette.ink)),
          ],
        ),
      );
}
