import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/upper_case.dart';
import '../../utils/number_utils.dart';
import '../widgets/common_widgets.dart';
import '../../utils/currency.dart';
import '../payments/payment_detail_screen.dart';

class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({
    super.key,
    required this.api,
    required this.logger,
    required this.loanId,
  });

  final ApiService api;
  final ErrorLogService logger;
  final int loanId;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _loan = {};
  Map<String, dynamic> _computed = {};
  // Acciones permitidas al usuario (las calcula la API según sus permisos).
  Map<String, dynamic> _abilities = {};
  // Periodo de interés que se está eliminando/restaurando (bloquea doble toque).
  String? _busyInterestId;
  List<dynamic> _payments = [];

  final _money = Currency.formatter();
  final _dateFmt = DateFormat('dd/MM/yyyy');

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
      final results = await Future.wait([
        widget.api.loanDetail(widget.loanId),
        widget.api.payments(loanId: widget.loanId, perPage: 50),
      ]);
      setState(() {
        final raw = results[0];
        _loan = (raw['loan'] as Map?)?.cast<String, dynamic>() ?? raw;
        _computed = (raw['computed'] as Map?)?.cast<String, dynamic>() ?? {};
        _abilities = _asMap(raw['abilities']);
        _payments = (results[1]['data'] as List?) ?? <dynamic>[];
      });
    } catch (e, st) {
      await widget.logger.logError(
        module: 'loan_detail',
        error: e,
        stackTrace: st,
        endpoint: '/loans/${widget.loanId}',
      );
      setState(() => _error = 'No se pudo cargar el préstamo');
    } finally {
      setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      return _dateFmt.format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  /// Motivo por el que el préstamo no admite cobros (finalizado, incumplido, eliminado…).
  String? get _lockedReason => _computed['actions_locked_reason']?.toString();

  bool get _canCharge =>
      _lockedReason == null &&
      ['pay_interest', 'pay_penalty', 'amortize', 'liquidate'].any((k) => _abilities[k] == true);

  /// Periodo de interés pendiente más antiguo (el único que se puede pagar).
  Map<String, dynamic>? get _oldestInterest {
    final id = _computed['oldest_pending_interest_id'];
    if (id == null) return null;
    final list = (_loan['interest_payments'] as List?) ?? const [];
    for (final ip in list) {
      final map = _asMap(ip);
      if ('${map['id']}' == '$id') return map;
    }
    return null;
  }

  /// Hay multa o proceso de mora cuando penalty_status no es 'normal' (penalty_paid_at no sirve para esto).
  bool _hasPenalty() {
    final status = _loan['penalty_status']?.toString() ?? 'normal';
    return status.isNotEmpty && status != 'normal';
  }

  List<Map<String, dynamic>> get _interests =>
      ((_loan['interest_payments'] as List?) ?? const []).map(_asMap).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
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
              ),
            )
          else ...[
            if (_lockedReason != null) SliverToBoxAdapter(child: _buildLockedBanner()),
            SliverToBoxAdapter(child: _buildProgressCard()),
            SliverToBoxAdapter(child: _buildMetricGrid()),
            if (asDouble(_computed['liquidation_amount']) > 0)
              SliverToBoxAdapter(child: _buildLiquidationCard()),
            if (_hasPenalty()) SliverToBoxAdapter(child: _buildPenaltyCard()),
            SliverToBoxAdapter(child: _buildInterestSection()),
            SliverToBoxAdapter(child: _buildConditionsCard()),
            SliverToBoxAdapter(child: _buildDatesCard()),
            if (_images.isNotEmpty) SliverToBoxAdapter(child: _buildPhotosSection()),
            SliverToBoxAdapter(child: _buildPaymentsSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ],
      ),
      floatingActionButton: (_loading || _error != null || !_canCharge)
          ? null
          : FloatingActionButton.extended(
              onPressed: _openChargeMenu,
              backgroundColor: AppPalette.deepBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.payments_rounded),
              label: const Text('Cobrar', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
    );
  }

  Widget _buildLockedBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF475569)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$_lockedReason Solo lectura.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    final client = _asMap(_loan['client']);
    final clientName = client['name']?.toString() ?? '';
    final status = _loan['status']?.toString() ?? '';
    final amount = asDouble(_loan['amount']);

    return SliverAppBar(
      expandedHeight: 250,
      pinned: true,
      stretch: true,
      backgroundColor: AppPalette.deepBlue,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          _loan['code']?.toString() ?? 'Préstamo #${widget.loanId}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppPalette.deepBlue, Color(0xFF197A8E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (clientName.isNotEmpty) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            clientName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (status.isNotEmpty) StatusChip(status: status),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    _money.format(amount),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 30,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Text(
                    'Monto original',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Progress card ──────────────────────────────────────────────────────────

  Widget _buildProgressCard() {
    final totalPaid = asDouble(_loan['total_paid']);
    final capital = asDouble(_computed['current_capital']);
    final unpaidInt = asDouble(_computed['unpaid_interest_total']);
    final totalToPay = capital + unpaidInt;
    final progress = totalToPay > 0 ? (totalPaid / totalToPay).clamp(0.0, 1.0) : 0.0;
    final pct = (progress * 100).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x10000000), blurRadius: 14, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Progreso de pago',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppPalette.ink),
                ),
                const Spacer(),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppPalette.deepBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE6EEF5),
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? const Color(0xFF2A9D8F) : AppPalette.deepBlue,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _miniStat('Pagado', _money.format(totalPaid), const Color(0xFF2A9D8F)),
                const SizedBox(width: 20),
                _miniStat('Total a pagar', _money.format(totalToPay), AppPalette.deepBlue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  // ── 2×2 metric grid ────────────────────────────────────────────────────────

  Widget _buildMetricGrid() {
    final capital = asDouble(_computed['current_capital']);
    final unpaidInt = asDouble(_computed['unpaid_interest_total']);
    final totalPaid = asDouble(_loan['total_paid']);
    final pendiente = capital + unpaidInt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              _metricTile(
                'Capital actual',
                _money.format(capital),
                Icons.account_balance_rounded,
                AppPalette.deepBlue,
              ),
              const SizedBox(width: 10),
              _metricTile(
                'Interés impago',
                _money.format(unpaidInt),
                Icons.trending_up_rounded,
                const Color(0xFFF4A261),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _metricTile(
                'Total pagado',
                _money.format(totalPaid),
                Icons.check_circle_rounded,
                const Color(0xFF2A9D8F),
              ),
              const SizedBox(width: 10),
              _metricTile(
                'Pendiente real',
                _money.format(pendiente),
                Icons.warning_amber_rounded,
                AppPalette.rose,
                highlight: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricTile(
    String label,
    String value,
    IconData icon,
    Color color, {
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlight ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: highlight
              ? Border.all(color: color.withValues(alpha: 0.3), width: 1.5)
              : Border.all(color: const Color(0xFFE6EEF5)),
          boxShadow: [
            BoxShadow(
              color: highlight ? color.withValues(alpha: 0.12) : const Color(0x0A000000),
              blurRadius: highlight ? 10 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: highlight ? color : AppPalette.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6A8299))),
          ],
        ),
      ),
    );
  }

  // ── Liquidation card ───────────────────────────────────────────────────────

  Widget _buildLiquidationCard() {
    final amount = asDouble(_computed['liquidation_amount']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppPalette.aqua.withValues(alpha: 0.14),
              AppPalette.aqua.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.aqua.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.aqua.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.bolt_rounded, color: AppPalette.aqua, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Monto de liquidación',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                ),
                Text(
                  _money.format(amount),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.aqua,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Conditions card ────────────────────────────────────────────────────────

  Widget _buildConditionsCard() {
    final rate = _loan['interest_rate']?.toString() ?? '-';
    final term = _loan['term_months']?.toString() ?? '-';
    final product = _asMap(_loan['product']);
    final productCode = '${product['code'] ?? ''}';

    return _InfoCard(
      title: 'Condiciones',
      icon: Icons.tune_rounded,
      rows: [
        if (product['name'] != null) _InfoRow('Prenda', '${product['name']}'),
        if (productCode.isNotEmpty) _InfoRow('Código de la prenda', productCode),
        _InfoRow('Tasa de interés', '$rate%'),
        _InfoRow('Plazo', '$term meses'),
      ],
    );
  }

  // ── Dates card ─────────────────────────────────────────────────────────────

  Widget _buildDatesCard() {
    return _InfoCard(
      title: 'Fechas',
      icon: Icons.calendar_month_rounded,
      rows: [
        _InfoRow('Inicio', _fmtDate(_loan['start_date']?.toString())),
        _InfoRow('Vencimiento', _fmtDate(_loan['end_date']?.toString())),
      ],
    );
  }

  // ── Penalty card ───────────────────────────────────────────────────────────

  Widget _buildPenaltyCard() {
    const stages = {
      'overdue': ('En mora', 'El plazo venció. Corre el periodo de gracia.', Color(0xFFD97706)),
      'grace': ('Periodo de gracia', 'Tiempo extra antes de que el préstamo quede incumplido.', Color(0xFFD97706)),
      'defaulted': ('Incumplido', 'Venció la gracia: la prenda queda disponible para la venta.', AppPalette.rose),
    };
    final status = _loan['penalty_status']?.toString() ?? '';
    final stage = stages[status] ?? (status, '', AppPalette.rose);
    final color = stage.$3;

    final penaltyAmount = asDouble(_loan['penalty_amount']);
    final pendingPenalty = asDouble(_computed['pending_penalty']);
    final graceDays = _asMap(_loan['credit_category'])['penalty_grace_days'];
    final reachedAt = _computed['penalty_reached_at']?.toString();
    final graceEndsAt = _computed['grace_ends_at']?.toString();

    final rows = <_InfoRow>[
      if (penaltyAmount > 0)
        _InfoRow('Multa', '${_money.format(penaltyAmount)} · ${pendingPenalty > 0 ? 'pendiente' : 'pagada'}'),
      if (reachedAt != null) _InfoRow('Plazo tope alcanzado', _fmtDate(reachedAt)),
      if (graceDays != null) _InfoRow('Días de gracia', '$graceDays'),
      if (graceEndsAt != null) _InfoRow('Fin de la gracia', _fmtDate(graceEndsAt)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.warning_amber_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Multa · ${stage.$1}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14)),
                      if (stage.$2.isNotEmpty)
                        Text(stage.$2, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                    ],
                  ),
                ),
              ],
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(row.label, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                      const Spacer(),
                      Text(row.value,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppPalette.ink)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Interest periods ───────────────────────────────────────────────────────

  Widget _buildInterestSection() {
    final interests = _interests;
    final paid = interests.where((i) => i['display_status'] == 'paid').length;
    final overdue = interests.where((i) => i['display_status'] == 'overdue').length;
    final pending = interests.where((i) => i['display_status'] == 'pending').length;
    final oldestId = '${_computed['oldest_pending_interest_id']}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Intereses',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppPalette.ink),
          ),
          if (interests.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                '$paid pagado${paid == 1 ? '' : 's'}',
                if (overdue > 0) '$overdue vencido${overdue == 1 ? '' : 's'}',
                if (pending > 0) '$pending pendiente${pending == 1 ? '' : 's'}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
            ),
          ],
          const SizedBox(height: 10),
          if (interests.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6EEF5)),
              ),
              child: const Text(
                'No hay periodos de interés generados aún.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6A8299)),
              ),
            )
          else
            ...interests.map((ip) {
              final status = ip['display_status'];
              final canDelete = _abilities['delete_interest'] == true &&
                  _lockedReason == null &&
                  (status == 'pending' || status == 'overdue');
              final canRestore = _abilities['restore_interest'] == true &&
                  ip['restorable'] == true &&
                  _loan['deleted_at'] == null &&
                  (_loan['status'] == 'ACTIVO' || _loan['status'] == 'EN_MORA');
              final busy = _busyInterestId == '${ip['id']}';
              return _InterestCard(
                map: ip,
                money: _money,
                fmtDate: _fmtDate,
                fmtDateTime: _fmtDateTime,
                isNext: '${ip['id']}' == oldestId,
                busy: busy,
                onDelete: canDelete && _busyInterestId == null ? () => _changeInterest(ip, restore: false) : null,
                onRestore: canRestore && _busyInterestId == null ? () => _changeInterest(ip, restore: true) : null,
              );
            }),
        ],
      ),
    );
  }

  /// Elimina o restaura un periodo de interés (con confirmación, como en la web).
  Future<void> _changeInterest(Map<String, dynamic> ip, {required bool restore}) async {
    final period = ip['period_number'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(restore ? 'Restaurar interés' : 'Eliminar interés'),
        content: Text(restore
            ? '¿Restaurar el periodo de interés #$period? Volverá a contar como pendiente para la mora.'
            : '¿Eliminar el periodo de interés #$period? Quedará registrado quién lo eliminó y se podrá restaurar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: restore ? const Color(0xFF2A9D8F) : AppPalette.rose),
            child: Text(restore ? 'Restaurar' : 'Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final interestId = int.tryParse('${ip['id']}');
    if (interestId == null) return;
    setState(() => _busyInterestId = '$interestId');
    final endpoint = '/loans/${widget.loanId}/interest-payments/$interestId${restore ? '/restore' : ''}';
    String message;
    bool success = false;
    try {
      final result = restore
          ? await widget.api.restoreInterest(loanId: widget.loanId, interestId: interestId)
          : await widget.api.deleteInterest(loanId: widget.loanId, interestId: interestId);
      message = result['message']?.toString() ?? 'Listo.';
      success = true;
    } on DioException catch (e) {
      message = _apiErrorMessage(e);
      if (e.response == null || (e.response!.statusCode ?? 0) >= 500) {
        await widget.logger.logError(module: 'loan_interest', error: e, stackTrace: StackTrace.current, endpoint: endpoint);
      }
    } catch (e, st) {
      await widget.logger.logError(module: 'loan_interest', error: e, stackTrace: st, endpoint: endpoint);
      message = 'No se pudo completar la operación. Intenta nuevamente.';
    }
    if (!mounted) return;
    setState(() => _busyInterestId = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: success ? const Color(0xFF2A9D8F) : AppPalette.rose,
    ));
    if (success) _load();
  }

  String _fmtDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }


  // ── Payments section ───────────────────────────────────────────────────────

  Widget _buildPaymentsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Historial de pagos',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppPalette.ink),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppPalette.deepBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_payments.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppPalette.deepBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_payments.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6EEF5)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.receipt_long_rounded, size: 36, color: Color(0xFF9DB1C3)),
                  SizedBox(height: 8),
                  Text('Sin pagos registrados', style: TextStyle(color: Color(0xFF6A8299))),
                ],
              ),
            )
          else
            ..._payments.map((p) {
              final map = _asMap(p);
              final id = int.tryParse('${map['id']}');
              return _PaymentCard(
                map: map,
                money: _money,
                onTap: id == null
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PaymentDetailScreen(
                              api: widget.api,
                              logger: widget.logger,
                              paymentId: id,
                              showLoanButton: false,
                            ),
                          ),
                        ),
              );
            }),
        ],
      ),
    );
  }

  // ── Fotos de la prenda ─────────────────────────────────────────────────────

  List<String> get _images => ((_loan['images'] as List?) ?? const [])
      .map((i) => '${_asMap(i)['url'] ?? ''}')
      .where((url) => url.isNotEmpty)
      .toList();

  Widget _buildPhotosSection() {
    final images = _images;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fotos del préstamo (${images.length})',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppPalette.ink),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => _PhotoViewer(urls: images, initial: i)),
                ),
                child: Hero(
                  tag: images[i],
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      images[i],
                      width: 110,
                      height: 110,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) => progress == null
                          ? child
                          : Container(
                              width: 110,
                              color: const Color(0xFFE6EEF5),
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                      errorBuilder: (_, _, _) => Container(
                        width: 110,
                        color: const Color(0xFFE6EEF5),
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined, color: Color(0xFF9DB1C3)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChargeMenu() async {
    final currentCapital = asDouble(_computed['current_capital']);
    final liquidationAmount = asDouble(_computed['liquidation_amount']);
    final pendingPenalty = asDouble(_computed['pending_penalty']);
    final oldestInterest = _oldestInterest;

    final action = await showModalBottomSheet<LoanAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChargeMenuSheet(
        money: _money,
        cashError: _computed['cash_session_error']?.toString(),
        oldestInterest: oldestInterest,
        pendingPenalty: pendingPenalty,
        currentCapital: currentCapital,
        liquidationAmount: liquidationAmount,
        abilities: _abilities,
      ),
    );
    if (action == null || !mounted) return;

    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LoanActionSheet(
        api: widget.api,
        logger: widget.logger,
        loanId: widget.loanId,
        action: action,
        money: _money,
        interest: oldestInterest,
        pendingPenalty: pendingPenalty,
        currentCapital: currentCapital,
        liquidationAmount: liquidationAmount,
      ),
    );
    if (message == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFF2A9D8F)),
    );
    _load();
  }
}

// ─── Info card ─────────────────────────────────────────────────────────────────

class _InfoRow {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.icon, required this.rows});

  final String title;
  final IconData icon;
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6EEF5)),
          boxShadow: const [
            BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: AppPalette.deepBlue),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppPalette.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      rows[i].label,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6A8299)),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        rows[i].value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.ink,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ─── Payment history card ──────────────────────────────────────────────────────

/// Fotos a pantalla completa: deslizar entre fotos y zoom con dos dedos.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initial});

  final List<String> urls;
  final int initial;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Foto ${_index + 1} de ${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Hero(
              tag: widget.urls[i],
              child: Image.network(
                widget.urls[i],
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.map, required this.money, this.onTap});

  final Map<String, dynamic> map;
  final NumberFormat money;
  final VoidCallback? onTap;

  String _fmtDate(String raw) {
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = asDouble(map['amount']);
    final payType = map['payment_type']?.toString() ?? '';
    final date = map['payment_date']?.toString() ?? '';
    final method = (map['method_label'] ?? map['payment_method'])?.toString() ?? '';
    final ref = map['reference']?.toString() ?? '';
    final capital = asDouble(map['capital']);
    final interest = asDouble(map['interest']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EEF5)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PaymentTypeChip(type: payType, label: map['type_label']?.toString()),
                const SizedBox(width: 8),
                Text(
                  date.isNotEmpty ? _fmtDate(date) : '-',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                ),
                const Spacer(),
                Text(
                  money.format(amount),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
              ],
            ),
            if (payType == 'mixed' && (capital > 0 || interest > 0)) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  _SubAmount('Capital', money.format(capital), AppPalette.deepBlue),
                  const SizedBox(width: 16),
                  _SubAmount('Interés', money.format(interest), const Color(0xFFF4A261)),
                ],
              ),
            ],
            if (method.isNotEmpty || ref.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (method.isNotEmpty) ...[
                    const Icon(Icons.payments_rounded, size: 13, color: Color(0xFF9DB1C3)),
                    const SizedBox(width: 4),
                    Text(method, style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                  ],
                  if (ref.isNotEmpty) ...[
                    if (method.isNotEmpty) const SizedBox(width: 10),
                    const Icon(Icons.tag_rounded, size: 13, color: Color(0xFF9DB1C3)),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        ref,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

class _SubAmount extends StatelessWidget {
  const _SubAmount(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// ─── Cobros ────────────────────────────────────────────────────────────────────

enum LoanAction { interest, penalty, amortize, liquidate }

/// Menú de cobro: las mismas cuatro operaciones que la web.
class _ChargeMenuSheet extends StatelessWidget {
  const _ChargeMenuSheet({
    required this.money,
    required this.cashError,
    required this.oldestInterest,
    required this.pendingPenalty,
    required this.currentCapital,
    required this.liquidationAmount,
    required this.abilities,
  });

  final NumberFormat money;
  final String? cashError;
  final Map<String, dynamic>? oldestInterest;
  final double pendingPenalty;
  final double currentCapital;
  final double liquidationAmount;
  final Map<String, dynamic> abilities;

  bool _can(String key) => abilities[key] == true;

  @override
  Widget build(BuildContext context) {
    final interestRemaining = _remaining(oldestInterest);

    final options = <Widget>[
      if (_can('pay_interest'))
        _ChargeOption(
          icon: Icons.trending_up_rounded,
          color: const Color(0xFFF4A261),
          title: 'Pagar interés',
          subtitle: oldestInterest == null
              ? 'No hay intereses pendientes'
              : 'Periodo #${oldestInterest!['period_number']} · ${money.format(interestRemaining)}',
          enabled: cashError == null && oldestInterest != null,
          onTap: () => Navigator.pop(context, LoanAction.interest),
        ),
      if (_can('pay_penalty') && pendingPenalty > 0)
        _ChargeOption(
          icon: Icons.warning_amber_rounded,
          color: AppPalette.rose,
          title: 'Pagar multa',
          subtitle: money.format(pendingPenalty),
          enabled: cashError == null,
          onTap: () => Navigator.pop(context, LoanAction.penalty),
        ),
      if (_can('amortize'))
        _ChargeOption(
          icon: Icons.account_balance_rounded,
          color: AppPalette.deepBlue,
          title: 'Amortizar capital',
          subtitle: 'Capital vigente ${money.format(currentCapital)}',
          enabled: cashError == null && currentCapital > 0,
          onTap: () => Navigator.pop(context, LoanAction.amortize),
        ),
      if (_can('liquidate'))
        _ChargeOption(
          icon: Icons.bolt_rounded,
          color: AppPalette.aqua,
          title: 'Liquidar préstamo',
          subtitle: 'Total ${money.format(liquidationAmount)}',
          enabled: cashError == null && liquidationAmount > 0,
          onTap: () => Navigator.pop(context, LoanAction.liquidate),
        ),
    ];

    return _SheetFrame(
      title: 'Cobrar',
      children: [
        if (cashError != null) ...[
          _MessageBox(text: cashError!),
          const SizedBox(height: 12),
        ],
        if (options.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No tienes permisos para registrar cobros.', style: TextStyle(color: Color(0xFF6A8299))),
          )
        else
          ...options,
      ],
    );
  }
}

/// Mensaje para el usuario a partir de un error de la API (primer error de validación o `message`).
String _apiErrorMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    final errors = data['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      return (first is List && first.isNotEmpty) ? first.first.toString() : first.toString();
    }
    if (data['message'] != null) return data['message'].toString();
  }
  return 'No se pudo completar la operación. Intenta nuevamente.';
}

/// Lo que falta pagar de un periodo de interés.
double _remaining(Map<String, dynamic>? interest) {
  if (interest == null) return 0;
  final value = asDouble(interest['interest_amount']) - asDouble(interest['paid_amount']);
  return value < 0 ? 0 : double.parse(value.toStringAsFixed(2));
}

class _ChargeOption extends StatelessWidget {
  const _ChargeOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6EEF5)),
        ),
        child: ListTile(
          enabled: enabled,
          onTap: enabled ? onTap : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }
}

/// Formulario de una operación de cobro. Fecha = hoy y método = efectivo, como en la web.
class _LoanActionSheet extends StatefulWidget {
  const _LoanActionSheet({
    required this.api,
    required this.logger,
    required this.loanId,
    required this.action,
    required this.money,
    this.interest,
    this.pendingPenalty = 0,
    this.currentCapital = 0,
    this.liquidationAmount = 0,
  });

  final ApiService api;
  final ErrorLogService logger;
  final int loanId;
  final LoanAction action;
  final NumberFormat money;
  final Map<String, dynamic>? interest;
  final double pendingPenalty;
  final double currentCapital;
  final double liquidationAmount;

  @override
  State<_LoanActionSheet> createState() => _LoanActionSheetState();
}

class _LoanActionSheetState extends State<_LoanActionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  // Un id por intento: si el envío se repite, el servidor no cobra dos veces.
  final _requestId = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
  bool _saving = false;
  String? _serverError;

  double get _interestRemaining => _remaining(widget.interest);

  @override
  void initState() {
    super.initState();
    if (widget.action == LoanAction.interest) {
      _amountCtrl.text = _interestRemaining.toStringAsFixed(2);
    } else if (widget.action == LoanAction.liquidate) {
      _amountCtrl.text = widget.liquidationAmount.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _title => switch (widget.action) {
        LoanAction.interest => 'Pagar interés',
        LoanAction.penalty => 'Pagar multa',
        LoanAction.amortize => 'Amortizar capital',
        LoanAction.liquidate => 'Liquidar préstamo',
      };

  String get _endpoint => switch (widget.action) {
        LoanAction.interest => 'interest-payments',
        LoanAction.penalty => 'penalty-payment',
        LoanAction.amortize => 'amortization',
        LoanAction.liquidate => 'liquidation',
      };

  double? _parsedAmount() => double.tryParse(_amountCtrl.text.replaceAll(',', '.').trim());

  String? _validateAmount(String? _) {
    final n = _parsedAmount();
    if (n == null || n <= 0) return 'Ingresa un monto mayor a 0';
    final money = widget.money;
    switch (widget.action) {
      case LoanAction.interest:
        if (n > _interestRemaining + 0.001) return 'Máximo ${money.format(_interestRemaining)}';
      case LoanAction.amortize:
        if (n > widget.currentCapital + 0.001) return 'Máximo ${money.format(widget.currentCapital)}';
      case LoanAction.liquidate:
        if (n + 0.001 < widget.liquidationAmount) return 'Mínimo ${money.format(widget.liquidationAmount)}';
      case LoanAction.penalty:
        break;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _serverError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (widget.action == LoanAction.liquidate) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Liquidar préstamo'),
          content: Text(
            'Se cobrará ${widget.money.format(_parsedAmount() ?? 0)}, el préstamo quedará FINALIZADO '
            'y se liberará la prenda. ¿Continuar?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Liquidar')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final result = await widget.api.loanAction(
        loanId: widget.loanId,
        action: _endpoint,
        requestId: _requestId,
        amount: widget.action == LoanAction.penalty ? null : _parsedAmount(),
        interestPaymentId:
            widget.action == LoanAction.interest ? int.tryParse('${widget.interest?['id']}') : null,
        notes: _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, result['message']?.toString() ?? 'Operación registrada.');
    } on DioException catch (e) {
      final msg = _apiErrorMessage(e);
      if (e.response == null || (e.response!.statusCode ?? 0) >= 500) {
        await widget.logger.logError(
          module: 'loan_action',
          error: e,
          stackTrace: StackTrace.current,
          endpoint: '/loans/${widget.loanId}/$_endpoint',
        );
      }
      if (mounted) setState(() => _serverError = msg);
    } catch (e, st) {
      await widget.logger.logError(
        module: 'loan_action',
        error: e,
        stackTrace: st,
        endpoint: '/loans/${widget.loanId}/$_endpoint',
      );
      if (mounted) setState(() => _serverError = 'No se pudo registrar la operación. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = widget.money;
    final interest = widget.interest;
    final summary = <_InfoRow>[
      if (widget.action == LoanAction.interest) ...[
        _InfoRow('Periodo', '#${interest?['period_number'] ?? '-'}'),
        _InfoRow('Interés del periodo', money.format(asDouble(interest?['interest_amount']))),
        if (asDouble(interest?['paid_amount']) > 0)
          _InfoRow('Ya pagado', money.format(asDouble(interest?['paid_amount']))),
        _InfoRow('Pendiente', money.format(_interestRemaining)),
      ],
      if (widget.action == LoanAction.penalty) _InfoRow('Multa a cobrar', money.format(widget.pendingPenalty)),
      if (widget.action == LoanAction.amortize) _InfoRow('Capital vigente', money.format(widget.currentCapital)),
      if (widget.action == LoanAction.liquidate)
        _InfoRow('Monto de liquidación', money.format(widget.liquidationAmount)),
      _InfoRow('Fecha', DateFormat('dd/MM/yyyy').format(DateTime.now())),
      const _InfoRow('Método', 'Efectivo'),
    ];

    return _SheetFrame(
      title: _title,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE6EEF5)),
                ),
                child: Column(
                  children: [
                    for (final row in summary)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text(row.label, style: const TextStyle(fontSize: 13, color: Color(0xFF6A8299))),
                            const Spacer(),
                            Text(
                              row.value,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.ink),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (widget.action != LoanAction.penalty) ...[
                TextFormField(
                  controller: _amountCtrl,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Monto',
                    prefixText: Currency.prefix,
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _notesCtrl,
                enabled: !_saving,
                maxLines: 2,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: upperCaseFormatters,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_serverError != null) ...[
                const SizedBox(height: 10),
                _MessageBox(text: _serverError!),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: AppPalette.deepBlue),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(
                          widget.action == LoanAction.liquidate ? 'Liquidar' : 'Confirmar cobro',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0DBE5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.ink)),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.rose.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.rose.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppPalette.rose, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppPalette.rose, fontSize: 13))),
        ],
      ),
    );
  }
}

// ─── Interest period card ──────────────────────────────────────────────────────

class _InterestCard extends StatelessWidget {
  const _InterestCard({
    required this.map,
    required this.money,
    required this.fmtDate,
    required this.fmtDateTime,
    required this.isNext,
    this.busy = false,
    this.onDelete,
    this.onRestore,
  });

  final Map<String, dynamic> map;
  final NumberFormat money;
  final String Function(String?) fmtDate;
  final String Function(String?) fmtDateTime;
  /// Es el periodo pendiente más antiguo: el próximo a cobrar.
  final bool isNext;
  final bool busy;
  /// null = el botón no se muestra (sin permiso o no aplica).
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final status = map['display_status']?.toString() ?? 'pending';
    final (label, color, icon) = switch (status) {
      'paid' => ('Pagado', const Color(0xFF2A9D8F), Icons.check_circle_rounded),
      'overdue' => ('Vencido', AppPalette.rose, Icons.error_rounded),
      'deleted' => ('Eliminado', const Color(0xFF64748B), Icons.delete_outline_rounded),
      _ => ('Pendiente', const Color(0xFFD97706), Icons.schedule_rounded),
    };
    final isDeleted = status == 'deleted';
    final interest = asDouble(map['interest_amount']);
    final paid = asDouble(map['paid_amount']);
    final remaining = asDouble(map['remaining_amount']);

    final details = <(String, String)>[
      ('Base capital', money.format(asDouble(map['base_amount']))),
      ('Interés (${asDouble(map['interest_rate']).toStringAsFixed(2)}%)', money.format(interest)),
      if (paid > 0) ('Pagado', money.format(paid)),
      if (status != 'paid' && !isDeleted && paid > 0) ('Falta', money.format(remaining)),
      if (status == 'paid' && map['paid_at'] != null) ('Fecha de pago', fmtDateTime(map['paid_at']?.toString())),
      if (isDeleted) ...[
        ('Eliminado por', map['deleted_by_name']?.toString() ?? 'No registrado'),
        ('Fecha', fmtDateTime(map['deleted_at']?.toString())),
        if (map['deletion_reason_label'] != null) ('Motivo', map['deletion_reason_label'].toString()),
      ],
      if (!isDeleted && map['restored_at'] != null)
        ('Restaurado', '${map['restored_by_name'] ?? '—'} · ${fmtDateTime(map['restored_at']?.toString())}'),
    ];

    return Opacity(
      opacity: isDeleted ? 0.75 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isNext ? color : const Color(0xFFE6EEF5), width: isNext ? 1.5 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '#${map['period_number'] ?? '-'}',
                      style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${fmtDate(map['period_start']?.toString())} — ${fmtDate(map['period_end']?.toString())}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(icon, size: 14, color: color),
                            const SizedBox(width: 4),
                            Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13)),
                            if (isNext) ...[
                              const SizedBox(width: 6),
                              const Text('· próximo a cobrar',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    money.format(isDeleted || status == 'paid' ? interest : remaining),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: isDeleted ? const Color(0xFF64748B) : AppPalette.ink,
                      decoration: isDeleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final (k, v) in details)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          v,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppPalette.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              else if (onDelete != null || onRestore != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: onRestore != null
                      ? OutlinedButton.icon(
                          onPressed: onRestore,
                          icon: const Icon(Icons.restore_rounded, size: 16),
                          label: const Text('Restaurar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2A9D8F),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline_rounded, size: 16),
                          label: const Text('Eliminar periodo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.rose,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
