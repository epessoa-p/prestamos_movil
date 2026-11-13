import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';

/// Detalle de una compra (como la web): producto, cliente, monto, caja y fotos.
/// Permite eliminarla (permiso purchases.delete): lo pagado vuelve a la caja abierta del
/// usuario y el producto sale del almacén. Devuelve true si se eliminó.
class PurchaseDetailScreen extends StatefulWidget {
  const PurchaseDetailScreen({super.key, required this.api, required this.logger, required this.purchaseId});

  final ApiService api;
  final ErrorLogService logger;
  final int purchaseId;

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  final _money = Currency.formatter();
  final _dateFmt = DateFormat('dd/MM/yyyy');

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};
  bool _deleting = false;

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
      _data = await widget.api.purchaseDetail(widget.purchaseId);
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'purchase_detail', error: e, stackTrace: st, endpoint: '/purchases/${widget.purchaseId}');
      }
      _error = apiErrorMessage(e, fallback: 'No se pudo cargar la compra.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  Future<void> _delete() async {
    final purchase = _map(_data['purchase']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar compra'),
        content: Text(
          '¿Eliminar la compra ${purchase['code']}?\n\n'
          'Se devolverán ${_money.format(asDouble(purchase['amount']))} a tu caja abierta y el producto saldrá del almacén.',
        ),
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
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final result = await widget.api.deletePurchase(purchaseId: widget.purchaseId, requestId: newRequestId());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result['message'] ?? 'Compra eliminada.'}'), backgroundColor: const Color(0xFF2A9D8F)),
      );
      Navigator.pop(context, true);
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'purchase_delete', error: e, stackTrace: st, endpoint: '/purchases/${widget.purchaseId}');
      }
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'No se pudo eliminar la compra.')), backgroundColor: AppPalette.rose),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchase = _map(_data['purchase']);
    return Scaffold(
      appBar: AppBar(
        title: Text(purchase['code']?.toString() ?? 'Compra'),
        backgroundColor: AppPalette.deepBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(onRefresh: _load, child: _buildContent(purchase)),
    );
  }

  Widget _buildContent(Map<String, dynamic> purchase) {
    final product = _map(purchase['product']);
    final client = _map(purchase['client']);
    final abilities = _map(_data['abilities']);
    final computed = _map(_data['computed']);
    final images = ((purchase['images'] as List?) ?? const []).whereType<Map>().toList();
    final date = DateTime.tryParse('${purchase['purchase_date'] ?? ''}');
    final price = asDouble(product['price']);
    final amount = asDouble(purchase['amount']);

    final productLines = <(String, dynamic)>[
      ('Categoría', _map(purchase['credit_category'])['name']),
      ('Nombre', product['name']),
      ('Marca', product['brand']),
      ('Modelo', product['item_model']),
      ('Año', product['model_year']),
      ('Placa', product['plate']),
      ('Chasis', product['chassis']),
      ('Serial', product['serial_number']),
      ('Tipo de joya', product['item_type']),
      ('Kilataje', product['karat']),
      ('Material', product['material_type']),
      ('Detalles', product['description']),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppPalette.deepBlue, Color(0xFF1E5E9D)]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Monto pagado', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text(_money.format(amount), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                [
                  if (date != null) _dateFmt.format(date),
                  _map(purchase['branch'])['name'],
                  purchase['status'] == 'completed' ? 'Completada' : purchase['status'],
                ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              if (price > 0) ...[
                const SizedBox(height: 4),
                Text('Precio de venta ${_money.format(price)} · ganancia estimada ${_money.format(price - amount)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ],
          ),
        ),
        _card('Producto', Icons.inventory_2_rounded, [
          for (final (label, value) in productLines)
            if (value != null && '$value'.trim().isNotEmpty) _line(label, '$value'),
        ]),
        _card('Cliente (vendedor)', Icons.person_rounded, [
          _line('Nombre', '${client['name'] ?? '-'}'),
          if (client['id_number'] != null) _line('Documento', '${client['id_number']}'),
          if (client['phone'] != null) _line('Teléfono', '${client['phone']}'),
        ]),
        _card('Registro', Icons.receipt_long_rounded, [
          _line('Registrado por', '${_map(purchase['created_by'])['name'] ?? '-'}'),
          if (_map(purchase['cash_register'])['name'] != null) _line('Caja', '${_map(purchase['cash_register'])['name']}'),
          if (purchase['notes'] != null && '${purchase['notes']}'.trim().isNotEmpty) _line('Notas', '${purchase['notes']}'),
        ]),
        if (images.isNotEmpty)
          _card('Fotos', Icons.photo_library_rounded, [
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final url = '${images[i]['url'] ?? ''}';
                  return GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url))),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(url, width: 110, height: 110, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                              width: 110, height: 110, color: const Color(0xFFE6EEF5), child: const Icon(Icons.broken_image_rounded))),
                    ),
                  );
                },
              ),
            ),
          ]),
        const SizedBox(height: 16),
        if (abilities['delete'] == true)
          OutlinedButton.icon(
            onPressed: _deleting ? null : _delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.rose,
              side: const BorderSide(color: AppPalette.rose),
              minimumSize: const Size.fromHeight(48),
            ),
            icon: _deleting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_outline_rounded),
            label: Text(_deleting ? 'Eliminando...' : 'Eliminar compra'),
          )
        else if (computed['delete_blocked_reason'] != null)
          Text('${computed['delete_blocked_reason']}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
        if (abilities['delete'] == true && computed['cash_session_error'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Para eliminarla necesitas una caja abierta: ${computed['cash_session_error']}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppPalette.rose)),
          ),
      ],
    );
  }

  Widget _card(String title, IconData icon, List<Widget> children) => Container(
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
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.ink))),
          ],
        ),
      );
}
