import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';
import '../loans/loan_detail_screen.dart';
import '../purchases/purchase_detail_screen.dart';
import '../sales/sale_detail_screen.dart';

const _muted = Color(0xFF6A8299);
const _green = Color(0xFF198754);

String _fmtDateTime(dynamic raw) {
  final d = DateTime.tryParse('${raw ?? ''}');
  return d == null ? '-' : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
}

/// Detalle de una sesión de caja (desde el reporte de cierres): resumen del cierre y sus movimientos.
class CashSessionDetailScreen extends StatefulWidget {
  const CashSessionDetailScreen({super.key, required this.api, required this.logger, required this.sessionId});

  final ApiService api;
  final ErrorLogService logger;
  final int sessionId;

  @override
  State<CashSessionDetailScreen> createState() => _CashSessionDetailScreenState();
}

class _CashSessionDetailScreenState extends State<CashSessionDetailScreen> {
  final _money = Currency.formatter();
  Map<String, dynamic> _s = {};
  List<Map<String, dynamic>> _movements = [];
  bool _loading = true;
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
      final data = await widget.api.closureDetail(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _s = data['session'] is Map ? Map<String, dynamic>.from(data['session']) : {};
        _movements = (data['movements'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      });
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(
          module: 'cash_session_detail',
          error: e,
          stackTrace: st,
          endpoint: '/reports/closures/${widget.sessionId}',
        );
      }
      if (mounted) setState(() => _error = apiErrorMessage(e, fallback: 'No se pudo cargar la sesión de caja.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        title: Text('${_s['cash_register'] ?? 'Sesión de caja'}'),
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _summary(),
                      const SizedBox(height: 18),
                      Text(
                        'Movimientos (${_movements.length})',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppPalette.ink),
                      ),
                      const SizedBox(height: 8),
                      if (_movements.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Esta sesión no tiene movimientos.'),
                          ),
                        )
                      else
                        for (final m in _movements)
                          MovementTile(
                            movement: m,
                            money: _money,
                            onTap: () => showMovementSheet(context, api: widget.api, logger: widget.logger, movement: m),
                          ),
                    ],
                  ),
                ),
    );
  }

  Widget _summary() {
    final open = _s['closed_at'] == null;
    final mismatch = _s['mismatch'] == null ? null : asDouble(_s['mismatch']);
    final (statusLabel, statusColor) = open
        ? ('Abierta', _green)
        : mismatch == null
            ? ('Cerrada', const Color(0xFF6C757D))
            : mismatch.abs() < 0.01
                ? ('Cuadra', _green)
                : (mismatch > 0 ? 'Sobrante' : 'Faltante', AppPalette.rose);

    final rows = <(String, String, Color?)>[
      ('Apertura', _fmtDateTime(_s['opened_at']), null),
      ('Abrió', '${_s['opened_by'] ?? '-'}', null),
      ('Cierre', open ? 'En curso' : _fmtDateTime(_s['closed_at']), null),
      if (!open) ('Cerró', '${_s['closed_by'] ?? '-'}', null),
      ('Monto de apertura', _money.format(asDouble(_s['opening_amount'])), null),
      ('Ingresos', '+${_money.format(asDouble(_s['income']))}', _green),
      ('Egresos', '−${_money.format(asDouble(_s['expense']))}', AppPalette.rose),
      ('Esperado en caja', _money.format(asDouble(_s['expected'])), AppPalette.deepBlue),
      if (_s['closing_amount'] != null) ('Contado al cerrar', _money.format(asDouble(_s['closing_amount'])), null),
      if (mismatch != null && mismatch.abs() >= 0.01)
        ('Descuadre', _money.format(mismatch), AppPalette.rose),
    ];
    final notes = [
      if ('${_s['opening_notes'] ?? ''}'.trim().isNotEmpty) 'Apertura: ${_s['opening_notes']}',
      if ('${_s['closing_notes'] ?? ''}'.trim().isNotEmpty) 'Cierre: ${_s['closing_notes']}',
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EEF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(
              children: [
                const Icon(Icons.point_of_sale_rounded, size: 18, color: AppPalette.deepBlue),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Resumen de la sesión', style: TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          for (final (label, value, color) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                children: [
                  Text(label, style: const TextStyle(fontSize: 13, color: _muted)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? AppPalette.ink),
                    ),
                  ),
                ],
              ),
            ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Text(notes.join('\n'), style: const TextStyle(fontSize: 12, color: _muted)),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// Fila de movimiento de caja (reporte de movimientos y detalle de una sesión).
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement, required this.money, this.onTap, this.showRegister = false});

  final Map<String, dynamic> movement;
  final NumberFormat money;
  final VoidCallback? onTap;
  final bool showRegister;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final expense = m['type'] == 'expense';
    final color = expense ? AppPalette.rose : _green;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(expense ? Icons.south_west_rounded : Icons.north_east_rounded, size: 16, color: color),
        ),
        title: Text(
          '${m['description'] ?? m['category_label'] ?? 'Movimiento'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            _fmtDateTime(m['date']),
            m['category_label'],
            if (showRegister) m['cash_register'],
            m['user'],
          ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
        trailing: Text(
          '${expense ? '-' : '+'}${money.format(asDouble(m['amount']))}',
          style: TextStyle(fontWeight: FontWeight.w800, color: color),
        ),
      ),
    );
  }
}

/// Hoja con el detalle de un movimiento de caja y acceso al préstamo, venta o compra que lo originó.
Future<void> showMovementSheet(
  BuildContext context, {
  required ApiService api,
  required ErrorLogService logger,
  required Map<String, dynamic> movement,
}) {
  final m = movement;
  final money = Currency.formatter();
  final expense = m['type'] == 'expense';
  final kind = '${m['reference_kind'] ?? ''}';
  final refId = int.tryParse('${m['reference_id'] ?? ''}');

  final (String, Widget Function())? target = switch (kind) {
    'loan' when refId != null => ('Ver préstamo', () => LoanDetailScreen(api: api, logger: logger, loanId: refId)),
    'sale' when refId != null => ('Ver venta', () => SaleDetailScreen(api: api, logger: logger, saleId: refId)),
    'purchase' when refId != null =>
      ('Ver compra', () => PurchaseDetailScreen(api: api, logger: logger, purchaseId: refId)),
    _ => null,
  };

  final rows = <(String, String)>[
    ('Tipo', expense ? 'Egreso' : 'Ingreso'),
    ('Categoría', '${m['category_label'] ?? '-'}'),
    ('Fecha', _fmtDateTime(m['date'])),
    ('Caja', '${m['cash_register'] ?? '-'}'),
    ('Registrado por', '${m['user'] ?? '-'}'),
    if ('${m['reference_label'] ?? ''}'.isNotEmpty) ('Referencia', '${m['reference_label']}'),
  ];

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${expense ? '-' : '+'}${money.format(asDouble(m['amount']))}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: expense ? AppPalette.rose : _green),
            ),
            if ('${m['description'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${m['description']}', textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.ink)),
            ],
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(label, style: const TextStyle(fontSize: 13, color: _muted)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.ink),
                      ),
                    ),
                  ],
                ),
              ),
            if (target != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => target.$2()));
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(target.$1),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
