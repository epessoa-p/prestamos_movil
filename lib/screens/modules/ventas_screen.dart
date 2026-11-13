import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/session_controller.dart';
import '../../controllers/sales_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_utils.dart';
import '../sales/new_sale_sheet.dart';
import '../sales/sale_detail_screen.dart';
import '../../utils/currency.dart';

class VentasScreen extends StatefulWidget {
  const VentasScreen({super.key, required this.api, required this.logger, required this.session});

  final ApiService api;
  final ErrorLogService logger;
  final SessionController session;

  @override
  State<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends State<VentasScreen> {
  late final SalesController _controller;
  final _money = Currency.formatter();
  final _searchCtrl = TextEditingController();

  bool get _canCreate => widget.session.permissions.contains('sales.create');

  @override
  void initState() {
    super.initState();
    _controller = SalesController(api: widget.api, logger: widget.logger);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openDetail(int saleId) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SaleDetailScreen(api: widget.api, logger: widget.logger, saleId: saleId)),
    );
    if (changed == true && mounted) _controller.load(query: _searchCtrl.text.trim());
  }

  Future<void> _newSale() async {
    if (!widget.session.isCashOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aperturar una caja antes de registrar ventas.')),
      );
      return;
    }
    final saleId = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.94,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (_, _) => NewSaleSheet(api: widget.api, logger: widget.logger),
      ),
    );
    if (saleId == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Venta registrada exitosamente.'), backgroundColor: Color(0xFF2A9D8F)),
    );
    _controller.load(query: _searchCtrl.text.trim());
    _openDetail(saleId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ventas'), backgroundColor: AppPalette.deepBlue, foregroundColor: Colors.white),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: _newSale,
              backgroundColor: AppPalette.deepBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Nueva venta'),
            )
          : null,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: () => _controller.load(query: _searchCtrl.text.trim()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (q) => _controller.load(query: q.trim()),
                  decoration: InputDecoration(
                    hintText: 'Buscar por cliente o producto...',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () => _controller.load(query: _searchCtrl.text.trim()),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_controller.loading)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                else if (_controller.error != null)
                  Padding(padding: const EdgeInsets.all(24), child: Text(_controller.error!))
                else if (_controller.sales.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Text('No hay ventas para mostrar.'))
                else
                  ..._controller.sales.whereType<Map>().map((s) => _saleCard(Map<String, dynamic>.from(s))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _saleCard(Map<String, dynamic> sale) {
    final product = sale['product'] is Map ? sale['product'] as Map : const {};
    final client = sale['client'] is Map ? sale['client'] as Map : const {};
    final isCredit = sale['payment_type'] == 'CREDITO';
    final status = sale['status']?.toString() ?? '';
    final (statusLabel, statusColor) = switch (status) {
      'completed' => ('Completada', const Color(0xFF15803D)),
      'returned' => ('Devuelta', AppPalette.rose),
      'cancelled' => ('Anulada', const Color(0xFF64748B)),
      _ => (status, const Color(0xFF64748B)),
    };
    final date = DateTime.tryParse('${sale['sale_date'] ?? ''}');
    final id = int.tryParse('${sale['id']}');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: id == null ? null : () => _openDetail(id),
        title: Text(
          '${sale['code'] ?? 'Venta #${sale['id']}'} · ${product['name'] ?? 'Sin producto'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(statusLabel, statusColor),
              _chip(isCredit ? 'Crédito' : 'Contado', isCredit ? const Color(0xFF7C3AED) : AppPalette.deepBlue),
              Text(
                '${client['name'] ?? 'Sin cliente'}${date != null ? ' · ${DateFormat('dd/MM/yyyy').format(date)}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        trailing: Text(_money.format(asDouble(sale['amount'])), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
      );
}
