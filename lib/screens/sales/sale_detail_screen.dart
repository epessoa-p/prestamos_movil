import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/upper_case.dart';
import '../../utils/api_errors.dart';
import '../../utils/number_utils.dart';
import '../../utils/currency.dart';

/// Detalle de una venta: datos, plan de cuotas (cobrar), liquidación y devolución (como la web).
class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({super.key, required this.api, required this.logger, required this.saleId});

  final ApiService api;
  final ErrorLogService logger;
  final int saleId;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  final _money = Currency.formatter();
  final _dateFmt = DateFormat('dd/MM/yyyy');

  bool _loading = true;
  String? _error;
  bool _busy = false;
  // Se cambió algo (para que la lista se recargue al volver).
  bool _changed = false;
  Map<String, dynamic> _sale = {};
  Map<String, dynamic> _computed = {};
  Map<String, dynamic> _abilities = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.saleDetail(widget.saleId);
      setState(() {
        _sale = _map(data['sale']);
        _computed = _map(data['computed']);
        _abilities = _map(data['abilities']);
      });
    } catch (e, st) {
      await widget.logger.logError(module: 'sale_detail', error: e, stackTrace: st, endpoint: '/sales/${widget.saleId}');
      setState(() => _error = apiErrorMessage(e, fallback: 'No se pudo cargar la venta.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}');
    return d == null ? '-' : _dateFmt.format(d);
  }

  String? get _cashError => _computed['cash_session_error']?.toString();
  bool get _isCredit => _sale['payment_type'] == 'CREDITO';

  /// Ejecuta una acción con confirmación previa opcional, spinner y mensaje del servidor.
  Future<void> _run(String endpoint, Future<Map<String, dynamic>> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await call();
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['message']?.toString() ?? 'Listo.'),
          backgroundColor: const Color(0xFF2A9D8F),
        ));
      }
      await _load();
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'sale_detail', error: e, stackTrace: st, endpoint: endpoint);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e)), backgroundColor: AppPalette.rose),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action, {Color color = AppPalette.deepBlue}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: color),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _payInstallment(Map<String, dynamic> inst) async {
    final id = int.tryParse('${inst['id']}');
    if (id == null) return;
    final ok = await _confirm(
      'Cobrar cuota ${inst['installment_no']}',
      'Se registrará el pago de ${_money.format(asDouble(inst['amount']))} en tu caja.',
      'Cobrar',
      color: const Color(0xFF2A9D8F),
    );
    if (!ok || !mounted) return;
    final requestId = newRequestId();
    await _run('/sales/installments/$id/pay',
        () => widget.api.paySaleInstallment(installmentId: id, requestId: requestId));
  }

  Future<void> _liquidate() async {
    final liq = _map(_computed['liquidation']);
    final ok = await _confirm(
      'Liquidar saldo pendiente',
      'Capital pendiente: ${_money.format(asDouble(liq['principal']))}\n'
          'Interés de cuotas vencidas: ${_money.format(asDouble(liq['interest']))}\n'
          'Total a cobrar: ${_money.format(asDouble(liq['total']))}\n\n'
          'Todas las cuotas pendientes quedarán pagadas.',
      'Liquidar',
    );
    if (!ok || !mounted) return;
    final requestId = newRequestId();
    await _run('/sales/${widget.saleId}/liquidate',
        () => widget.api.liquidateSale(saleId: widget.saleId, requestId: requestId));
  }

  Future<void> _return() async {
    final reasons = _map(_computed['return_reasons']);
    final result = await showModalBottomSheet<({String reason, String notes})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReturnSheet(reasons: reasons, isCredit: _isCredit),
    );
    if (result == null || !mounted) return;
    final requestId = newRequestId();
    await _run('/sales/${widget.saleId}/return', () => widget.api.returnSale(
          saleId: widget.saleId,
          reason: result.reason,
          notes: result.notes,
          requestId: requestId,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F7FB),
        appBar: AppBar(
          title: Text(_sale['code']?.toString() ?? 'Venta'),
          backgroundColor: AppPalette.deepBlue,
          foregroundColor: Colors.white,
          actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded))],
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
                          FilledButton(onPressed: _load, child: const Text('Reintentar')),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        if (_busy) const LinearProgressIndicator(minHeight: 3),
                        _buildHeader(),
                        if (_sale['status'] == 'returned') _buildReturnedCard(),
                        if (_isCredit) _buildInstallments(),
                        _buildActions(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets margin = const EdgeInsets.only(top: 12)}) => Container(
        margin: margin,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6EEF5)),
        ),
        child: child,
      );

  Widget _row(String label, String value, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6A8299))),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                  color: color ?? AppPalette.ink,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildHeader() {
    final product = _map(_sale['product']);
    final client = _map(_sale['client']);
    final branch = _map(_sale['branch']);
    final status = _sale['status']?.toString() ?? '';
    final statusColor = switch (status) {
      'completed' => const Color(0xFF15803D),
      'returned' => AppPalette.rose,
      _ => const Color(0xFF64748B),
    };

    return _card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _chip(_computed['status_label']?.toString() ?? status, statusColor),
              const SizedBox(width: 8),
              _chip(_isCredit ? 'Crédito' : 'Contado', _isCredit ? const Color(0xFF7C3AED) : AppPalette.deepBlue),
              const Spacer(),
              Text(_money.format(asDouble(_sale['amount'])),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppPalette.ink)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            [product['name'], product['brand']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppPalette.ink),
          ),
          const SizedBox(height: 8),
          _row('Cliente', client['name']?.toString() ?? 'Sin cliente'),
          _row('Sucursal', branch['name']?.toString() ?? '-'),
          _row('Fecha', _fmtDate(_sale['sale_date'])),
          if (_isCredit) ...[
            const Divider(height: 18),
            _row('Recargo de crédito',
                '${asDouble(_sale['credit_additional_percentage']).toStringAsFixed(2)}% · ${_money.format(asDouble(_sale['credit_additional_amount']))}'),
            _row('Total a crédito', _money.format(asDouble(_computed['credit_total'])), bold: true),
            if (asDouble(_sale['down_payment']) > 0) _row('Cuota inicial', _money.format(asDouble(_sale['down_payment']))),
          ],
          if ((_sale['notes']?.toString() ?? '').isNotEmpty) ...[
            const Divider(height: 18),
            Text(_sale['notes'].toString(), style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      );

  Widget _buildReturnedCard() {
    final reasons = _map(_computed['return_reasons']);
    final reason = _sale['return_reason']?.toString() ?? '';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Venta devuelta', style: TextStyle(fontWeight: FontWeight.w800, color: AppPalette.rose)),
          const SizedBox(height: 6),
          _row('Motivo', reasons[reason]?.toString() ?? reason),
          _row('Fecha', _fmtDate(_sale['returned_at'])),
          if (_map(_sale['returned_by'])['name'] != null) _row('Por', _map(_sale['returned_by'])['name'].toString()),
          if ((_sale['return_notes']?.toString() ?? '').isNotEmpty) _row('Notas', _sale['return_notes'].toString()),
        ],
      ),
    );
  }

  Widget _buildInstallments() {
    final installments = ((_sale['installments'] as List?) ?? const []).map(_map).toList();
    final canPay = _abilities['pay_installment'] == true && _cashError == null;
    final today = DateTime.now();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Plan de cuotas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppPalette.ink)),
          const SizedBox(height: 8),
          if (installments.isEmpty)
            const Text('Sin cuotas (pagada con la cuota inicial).', style: TextStyle(color: Color(0xFF6A8299)))
          else
            for (final inst in installments) _installmentRow(inst, canPay, today),
        ],
      ),
    );
  }

  Widget _installmentRow(Map<String, dynamic> inst, bool canPay, DateTime today) {
    final status = inst['status']?.toString() ?? '';
    final due = DateTime.tryParse('${inst['due_date'] ?? ''}');
    final overdue = (status == 'PENDIENTE' && due != null && due.isBefore(DateTime(today.year, today.month, today.day))) ||
        status == 'VENCIDA';
    final (label, color) = switch (status) {
      'PAGADA' => ('Pagada', const Color(0xFF15803D)),
      'ANULADA' => ('Anulada', const Color(0xFF64748B)),
      _ => overdue ? ('Vencida', AppPalette.rose) : ('Pendiente', const Color(0xFFD97706)),
    };
    final unpaid = status == 'PENDIENTE' || status == 'VENCIDA';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text('${inst['installment_no']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_money.format(asDouble(inst['amount'])),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
                Text(
                  status == 'PAGADA' && inst['paid_at'] != null
                      ? '$label el ${_fmtDate(inst['paid_at'])}'
                      : '$label · vence ${_fmtDate(inst['due_date'])}',
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (unpaid && canPay)
            FilledButton(
              onPressed: _busy ? null : () => _payInstallment(inst),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2A9D8F),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Cobrar'),
            ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final canLiquidate = _abilities['liquidate'] == true;
    final canReturn = _abilities['return'] == true;
    if (!canLiquidate && !canReturn && _abilities['pay_installment'] != true) return const SizedBox.shrink();
    final liq = _map(_computed['liquidation']);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_cashError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.rose.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppPalette.rose.withValues(alpha: 0.3)),
              ),
              child: Text(_cashError!, style: const TextStyle(color: AppPalette.rose, fontSize: 13)),
            ),
          if (canLiquidate)
            FilledButton.icon(
              onPressed: _busy || _cashError != null ? null : _liquidate,
              style: FilledButton.styleFrom(backgroundColor: AppPalette.deepBlue, minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.bolt_rounded),
              label: Text('Liquidar · ${_money.format(asDouble(liq['total']))}'),
            ),
          if (canLiquidate && canReturn) const SizedBox(height: 10),
          if (canReturn)
            OutlinedButton.icon(
              onPressed: _busy || _cashError != null ? null : _return,
              style: OutlinedButton.styleFrom(foregroundColor: AppPalette.rose, minimumSize: const Size.fromHeight(46)),
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Devolver venta'),
            ),
        ],
      ),
    );
  }
}

/// Motivo y notas de la devolución.
class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({required this.reasons, required this.isCredit});

  final Map<String, dynamic> reasons;
  final bool isCredit;

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  String? _reason;
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Devolver venta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.ink)),
            const SizedBox(height: 6),
            Text(
              widget.isCredit
                  ? 'El producto vuelve al almacén, se devuelve en caja la cuota inicial y las cuotas pagadas, y se anulan las pendientes.'
                  : 'El producto vuelve al almacén y se devuelve en caja el importe de la venta.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Motivo *', border: OutlineInputBorder()),
              items: [
                for (final e in widget.reasons.entries) DropdownMenuItem(value: e.key, child: Text('${e.value}')),
              ],
              onChanged: (v) => setState(() => _reason = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              maxLength: 1000,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: upperCaseFormatters,
              decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _reason == null
                  ? null
                  : () => Navigator.pop(context, (reason: _reason!, notes: _notesCtrl.text.trim())),
              style: FilledButton.styleFrom(backgroundColor: AppPalette.rose, minimumSize: const Size.fromHeight(48)),
              child: const Text('Confirmar devolución'),
            ),
          ],
        ),
      ),
    );
  }
}
