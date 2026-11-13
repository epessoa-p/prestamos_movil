import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';
import '../loans/loan_detail_screen.dart';
import '../widgets/common_widgets.dart';
import '../widgets/file_ready_sheet.dart';

/// Detalle de un pago de préstamo: monto y desglose, préstamo y cliente, quién cobró,
/// comprobante adjunto y recibo en PDF (ticket o carta) para abrir o compartir.
class PaymentDetailScreen extends StatefulWidget {
  const PaymentDetailScreen({
    super.key,
    required this.api,
    required this.logger,
    required this.paymentId,
    this.showLoanButton = true,
  });

  final ApiService api;
  final ErrorLogService logger;
  final int paymentId;

  /// false cuando se abre desde el propio préstamo (evita ir y volver al mismo detalle).
  final bool showLoanButton;

  @override
  State<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentDetailScreenState extends State<PaymentDetailScreen> {
  final _money = Currency.formatter();
  Map<String, dynamic> _p = {};
  bool _loading = true;
  bool _downloading = false;
  String? _error;

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
      final data = await widget.api.paymentDetail(widget.paymentId);
      if (!mounted) return;
      setState(() => _p = data['payment'] is Map ? Map<String, dynamic>.from(data['payment']) : {});
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'payment_detail', error: e, stackTrace: st, endpoint: '/payments/${widget.paymentId}');
      }
      if (mounted) setState(() => _error = apiErrorMessage(e, fallback: 'No se pudo cargar el pago.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : {};

  String _fmtDateTime(dynamic raw, {bool time = true}) {
    final d = DateTime.tryParse('${raw ?? ''}');
    if (d == null) return '-';
    return DateFormat(time ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy').format(time ? d.toLocal() : d);
  }

  Future<void> _receipt() async {
    final size = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Recibo de pago', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'Se descarga en PDF. Luego puedes abrirlo para imprimir o compartirlo (WhatsApp, correo…).',
                style: TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.receipt_rounded, color: AppPalette.deepBlue),
                title: const Text('Ticket (80 mm)'),
                subtitle: const Text('Para impresora de tickets'),
                onTap: () => Navigator.pop(ctx, 'ticket'),
              ),
              ListTile(
                leading: const Icon(Icons.description_rounded, color: AppPalette.deepBlue),
                title: const Text('Hoja carta'),
                subtitle: const Text('Para impresora común o para enviar'),
                onTap: () => Navigator.pop(ctx, 'carta'),
              ),
            ],
          ),
        ),
      ),
    );
    if (size == null || !mounted) return;

    setState(() => _downloading = true);
    try {
      final dir = await getTemporaryDirectory();
      final path = await widget.api.downloadPaymentReceipt(widget.paymentId, size: size, dir: dir.path);
      if (!mounted) return;
      await showFileReadySheet(
        context,
        path: path,
        title: 'Recibo listo',
        shareText: 'Recibo de pago ${_p['loan_code'] ?? ''}',
      );
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(
          module: 'payment_receipt',
          error: e,
          stackTrace: st,
          endpoint: '/payments/${widget.paymentId}/receipt',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiErrorMessage(e, fallback: 'No se pudo descargar el recibo.')),
          backgroundColor: AppPalette.rose,
        ));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _openLoan() {
    final loanId = int.tryParse('${_map(_p['loan'])['id'] ?? _p['loan_id']}');
    if (loanId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LoanDetailScreen(api: widget.api, logger: widget.logger, loanId: loanId),
      ),
    );
  }

  Future<void> _openAttachment() async {
    final url = '${_p['receipt_url'] ?? ''}';
    if (url.isEmpty) return;
    if (_p['receipt_is_pdf'] == true) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Comprobante')),
          body: Center(child: InteractiveViewer(maxScale: 5, child: Image.network(url))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        title: Text(_p['loan_code'] != null ? 'Pago · ${_p['loan_code']}' : 'Pago'),
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
                )
              : RefreshIndicator(onRefresh: _load, child: _content()),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    if (widget.showLoanButton) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openLoan,
                          icon: const Icon(Icons.account_balance_wallet_rounded),
                          label: const Text('Ver préstamo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _downloading ? null : _receipt,
                        icon: _downloading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.print_rounded),
                        label: const Text('Recibo PDF'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _content() {
    final type = '${_p['payment_type'] ?? ''}';
    final capital = asDouble(_p['capital']);
    final interest = asDouble(_p['interest']);
    final loan = _map(_p['loan']);
    final client = _map(_p['client']);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Monto
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6EEF5)),
          ),
          child: Column(
            children: [
              PaymentTypeChip(type: type, label: _p['type_label']?.toString()),
              const SizedBox(height: 10),
              Text(
                _money.format(asDouble(_p['amount'])),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF198754)),
              ),
              const SizedBox(height: 4),
              Text(
                _fmtDateTime(_p['registered_at']),
                style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
              ),
              const SizedBox(height: 10),
              BranchPill.from(_p['branch']),
            ],
          ),
        ),
        _section('Pago', Icons.payments_rounded, [
          ('Fecha de pago', _fmtDateTime(_p['payment_date'], time: false)),
          ('Método', '${_p['method_label'] ?? '-'}'),
          if ('${_p['reference'] ?? ''}'.isNotEmpty) ('Referencia', '${_p['reference']}'),
          if (capital > 0 && interest > 0) ...[
            ('Capital', _money.format(capital)),
            ('Interés', _money.format(interest)),
          ],
          ('Cobrado por', '${_p['registered_by_name'] ?? '-'}'),
          if ('${_p['cash_register'] ?? ''}'.isNotEmpty) ('Caja', '${_p['cash_register']}'),
          ('N.º de recibo', '${_p['id'] ?? '-'}'.padLeft(6, '0')),
        ]),
        _section('Préstamo', Icons.account_balance_wallet_rounded, [
          ('Código', '${loan['code'] ?? _p['loan_code'] ?? '-'}'),
          if ('${loan['product'] ?? ''}'.isNotEmpty) ('Prenda', '${loan['product']}'),
          ('Monto prestado', _money.format(asDouble(loan['amount']))),
          ('Saldo pendiente', _money.format(asDouble(loan['pending']))),
          ('Estado', '${loan['status_label'] ?? '-'}'),
        ]),
        if (client.isNotEmpty)
          _section('Cliente', Icons.person_rounded, [
            ('Nombre', '${client['name'] ?? '-'}'),
            if ('${client['id_number'] ?? ''}'.isNotEmpty) ('CI', '${client['id_number']}'),
            if ('${client['phone'] ?? ''}'.isNotEmpty) ('Teléfono', '${client['phone']}'),
          ]),
        if ('${_p['notes'] ?? ''}'.trim().isNotEmpty) _section('Notas', Icons.notes_rounded, [('', '${_p['notes']}'.trim())]),
        if ('${_p['receipt_url'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: _openAttachment,
              icon: Icon(_p['receipt_is_pdf'] == true ? Icons.picture_as_pdf_rounded : Icons.image_rounded),
              label: const Text('Ver comprobante adjunto'),
            ),
          ),
      ],
    );
  }

  Widget _section(String title, IconData icon, List<(String, String)> rows) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EEF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppPalette.deepBlue),
                const SizedBox(width: 6),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppPalette.ink)),
              ],
            ),
          ),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: rows[i].$1.isEmpty
                  ? Text(rows[i].$2, style: const TextStyle(fontSize: 13, color: AppPalette.ink))
                  : Row(
                      children: [
                        Text(rows[i].$1, style: const TextStyle(fontSize: 13, color: Color(0xFF6A8299))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            rows[i].$2,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.ink),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
