import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/session_controller.dart';
import '../../controllers/purchases_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';
import '../purchases/new_purchase_sheet.dart';
import '../purchases/purchase_detail_screen.dart';

class ComprasScreen extends StatefulWidget {
  const ComprasScreen({super.key, required this.api, required this.logger, required this.session});

  final ApiService api;
  final ErrorLogService logger;
  final SessionController session;

  @override
  State<ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends State<ComprasScreen> {
  late final PurchasesController _controller;
  final _money = Currency.formatter();
  final _searchCtrl = TextEditingController();

  bool get _canCreate => widget.session.permissions.contains('purchases.create');

  @override
  void initState() {
    super.initState();
    _controller = PurchasesController(api: widget.api, logger: widget.logger);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openDetail(int purchaseId) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PurchaseDetailScreen(api: widget.api, logger: widget.logger, purchaseId: purchaseId)),
    );
    if (changed == true && mounted) _controller.load(query: _searchCtrl.text.trim());
  }

  Future<void> _newPurchase() async {
    if (!widget.session.isCashOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aperturar una caja antes de registrar compras.')),
      );
      return;
    }
    final purchaseId = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.94,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (_, _) => NewPurchaseSheet(api: widget.api, logger: widget.logger),
      ),
    );
    if (purchaseId == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Compra registrada exitosamente.'), backgroundColor: Color(0xFF2A9D8F)),
    );
    _controller.load(query: _searchCtrl.text.trim());
    _openDetail(purchaseId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compras'), backgroundColor: AppPalette.deepBlue, foregroundColor: Colors.white),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: _newPurchase,
              backgroundColor: AppPalette.deepBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Nueva compra'),
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
                else if (_controller.purchases.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Text('No hay compras para mostrar.'))
                else
                  ..._controller.purchases.whereType<Map>().map((p) => _purchaseCard(Map<String, dynamic>.from(p))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _purchaseCard(Map<String, dynamic> purchase) {
    final product = purchase['product'] is Map ? purchase['product'] as Map : const {};
    final client = purchase['client'] is Map ? purchase['client'] as Map : const {};
    final category = purchase['credit_category'] is Map ? purchase['credit_category'] as Map : const {};
    final date = DateTime.tryParse('${purchase['purchase_date'] ?? ''}');
    final id = int.tryParse('${purchase['id']}');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: id == null ? null : () => _openDetail(id),
        title: Text(
          '${purchase['code'] ?? 'Compra #${purchase['id']}'} · ${product['name'] ?? 'Sin producto'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              category['name'],
              client['name'] ?? 'Sin cliente',
              if (date != null) DateFormat('dd/MM/yyyy').format(date),
            ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        trailing: Text(_money.format(asDouble(purchase['amount'])), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}
