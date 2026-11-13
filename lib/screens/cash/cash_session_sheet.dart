import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/session_controller.dart';
import '../../controllers/cash_session_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/upper_case.dart';
import '../../utils/number_utils.dart';
import '../widgets/client_rating.dart' show hexColor;
import '../../utils/currency.dart';

/// Hoja de caja: estado, apertura y cierre (igual que los modales de la web).
class CashSessionSheet extends StatefulWidget {
  const CashSessionSheet({super.key, required this.api, required this.logger, required this.session});

  final ApiService api;
  final ErrorLogService logger;
  /// Se refresca al abrir/cerrar para que el resto de la app vea el nuevo estado de caja.
  final SessionController session;

  @override
  State<CashSessionSheet> createState() => _CashSessionSheetState();
}

class _CashSessionSheetState extends State<CashSessionSheet> {
  late final CashSessionController _ctrl;
  final _money = Currency.formatter();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final Map<String, TextEditingController> _qtyCtrls = {};

  bool _closing = false; // mostrando el formulario de cierre
  bool _expensing = false; // mostrando el formulario de gasto
  final _expAmountCtrl = TextEditingController();
  final _expNotesCtrl = TextEditingController();
  String? _expCategory;
  int? _expPersonalId;
  bool _countByDenomination = false;
  int? _registerId; // caja elegida por el gerente

  @override
  void initState() {
    super.initState();
    _ctrl = CashSessionController(api: widget.api, logger: widget.logger)..addListener(_onChange);
    _ctrl.load();
  }

  void _onChange() {
    // Gerente con una sola caja: queda elegida.
    if (_registerId == null && _ctrl.registers.length == 1) {
      _registerId = int.tryParse('${_ctrl.registers.first['id']}');
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _expAmountCtrl.dispose();
    _expNotesCtrl.dispose();
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(String text) => double.tryParse(text.replaceAll(',', '.').trim());

  TextEditingController _qtyCtrl(String key) => _qtyCtrls.putIfAbsent(key, TextEditingController.new);

  Map<String, int> get _breakdown => {
        for (final d in _ctrl.denominations) '${d['key']}': int.tryParse(_qtyCtrl('${d['key']}').text.trim()) ?? 0,
      };

  double get _breakdownTotal {
    var total = 0.0;
    for (final d in _ctrl.denominations) {
      total += (int.tryParse(_qtyCtrl('${d['key']}').text.trim()) ?? 0) * asDouble(d['value']);
    }
    return double.parse(total.toStringAsFixed(2));
  }

  /// Monto que se cerraría: el conteo si se usan denominaciones, si no el ingresado.
  double? get _closingAmount => _countByDenomination ? _breakdownTotal : _parse(_amountCtrl.text);

  String _denominationLabel(Map<String, dynamic> d) {
    final key = '${d['key']}';
    final value = asDouble(d['value']);
    if (key.startsWith('c')) return '${(value * 100).round()} ctvs';
    return '${Currency.symbol} ${value.toStringAsFixed(0)} ${key.startsWith('b') ? 'billete' : 'moneda'}';
  }

  void _showMessage(String message, bool ok) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: ok ? const Color(0xFF2A9D8F) : AppPalette.rose,
    ));
  }

  /// Actualiza el estado de caja del resto de la app (/auth/me) tras abrir o cerrar.
  Future<void> _refreshSessionCash() async {
    final ok = await widget.session.refreshProfile();
    if (!ok && mounted) {
      _showMessage('No se pudo actualizar el estado de la caja en la app. Revisa la conexión y toca Actualizar.', false);
    }
  }

  Future<void> _open() async {
    final amount = _parse(_amountCtrl.text.isEmpty ? '0' : _amountCtrl.text);
    if (amount == null || amount < 0) {
      _showMessage('Ingresa un monto de apertura válido.', false);
      return;
    }
    if (_ctrl.isManager && _registerId == null) {
      _showMessage('Selecciona la caja a aperturar.', false);
      return;
    }
    final result = await _ctrl.open(
      amount: amount,
      cashRegisterId: _ctrl.isManager ? _registerId : null,
      notes: _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    _showMessage(result.message, result.ok);
    if (result.ok) {
      _amountCtrl.clear();
      _notesCtrl.clear();
      await _refreshSessionCash();
    }
  }

  Future<void> _close() async {
    final amount = _closingAmount;
    if (amount == null || amount < 0) {
      _showMessage('Ingresa el monto contado o completa las denominaciones.', false);
      return;
    }
    final expected = asDouble(_ctrl.session?['summary']?['expected']);
    final diff = double.parse((amount - expected).toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar caja'),
        content: Text(
          'Se cerrará la caja con ${_money.format(amount)}.\n'
          '${diff == 0 ? 'Cuadra con lo esperado.' : diff > 0 ? 'Sobra ${_money.format(diff)} respecto a lo esperado.' : 'Falta ${_money.format(-diff)} respecto a lo esperado.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar caja')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final result = await _ctrl.close(
      amount: _countByDenomination ? null : amount,
      breakdown: _countByDenomination ? _breakdown : null,
      notes: _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    _showMessage(result.message, result.ok);
    if (result.ok) {
      setState(() {
        _closing = false;
        _amountCtrl.clear();
        _notesCtrl.clear();
        for (final c in _qtyCtrls.values) {
          c.clear();
        }
      });
      await _refreshSessionCash();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFCDD8E3), borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
              child: Row(
                children: [
                  const Text('Caja', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.ink)),
                  const Spacer(),
                  if (_ctrl.loading)
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: _ctrl.saving
                          ? null
                          : () {
                              _ctrl.load();
                              widget.session.refreshProfile();
                            },
                      tooltip: 'Actualizar',
                      color: const Color(0xFF6A8299),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_ctrl.loading && _ctrl.data.isEmpty) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (_ctrl.error != null && _ctrl.data.isEmpty) {
      return Column(
        children: [
          Text(_ctrl.error!, style: const TextStyle(color: AppPalette.rose)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _ctrl.load, child: const Text('Reintentar')),
        ],
      );
    }
    return _ctrl.isOpen ? _buildOpen() : _buildClosed();
  }

  // ── Caja abierta ───────────────────────────────────────────────────────────

  Widget _buildOpen() {
    final session = _ctrl.session!;
    final register = (session['cash_register'] as Map?)?.cast<String, dynamic>() ?? {};
    final summary = (session['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final expected = asDouble(summary['expected']);
    final openedAt = DateTime.tryParse('${session['opened_at']}')?.toLocal();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusBadge(open: true),
        const SizedBox(height: 14),
        _registerCard(register, subtitle: openedAt == null ? null : 'Abierta desde ${DateFormat('dd/MM/yyyy HH:mm').format(openedAt)}'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Deberías tener en caja',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8))),
                  const Spacer(),
                  Text(_money.format(expected),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8))),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('Apertura: ${_money.format(asDouble(summary['opening_amount']))}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                  Text('+ Ingresos: ${_money.format(asDouble(summary['income']))}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF15803D))),
                  Text('− Egresos: ${_money.format(asDouble(summary['expense']))}',
                      style: const TextStyle(fontSize: 12, color: AppPalette.rose)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_closing)
          _buildCloseForm(expected)
        else if (_expensing)
          _buildExpenseForm(expected)
        else ...[
          if (_ctrl.canRegisterExpense)
            OutlinedButton.icon(
              onPressed: () => setState(() => _expensing = true),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.rose,
                minimumSize: const Size.fromHeight(46),
              ),
              icon: const Icon(Icons.remove_circle_outline_rounded),
              label: const Text('Registrar gasto'),
            ),
          if (_ctrl.canRegisterExpense) const SizedBox(height: 10),
          if (_ctrl.canOperate)
            FilledButton.icon(
              onPressed: () => setState(() => _closing = true),
              style: FilledButton.styleFrom(backgroundColor: AppPalette.rose, minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.lock_rounded),
              label: const Text('Cerrar caja'),
            )
          else
            const Text('No tienes permiso para cerrar la caja.',
                textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6A8299))),
        ],
      ],
    );
  }

  // ── Registrar gasto ────────────────────────────────────────────────────────

  Widget _buildExpenseForm(double available) {
    final amount = _parse(_expAmountCtrl.text);
    final isStaff = _expCategory == 'staff_payment';
    final personals = _ctrl.expensePersonals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Registrar gasto', style: TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
        const SizedBox(height: 4),
        Text('Disponible en caja: ${_money.format(available)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppPalette.rose)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _expCategory,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Tipo de gasto *', border: OutlineInputBorder(), isDense: true),
          items: [
            for (final c in _ctrl.expenseCategories)
              DropdownMenuItem(value: '${c['key']}', child: Text(_expenseLabel(c))),
          ],
          onChanged: (v) => setState(() {
            _expCategory = v;
            if (v != 'staff_payment') _expPersonalId = null;
          }),
        ),
        if (isStaff) ...[
          const SizedBox(height: 10),
          if (personals.isEmpty)
            const Text('No hay personal activo registrado en la empresa.',
                style: TextStyle(fontSize: 12, color: AppPalette.rose))
          else
            DropdownButtonFormField<int>(
              initialValue: _expPersonalId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Personal *', border: OutlineInputBorder(), isDense: true),
              items: [
                for (final p in personals)
                  if (int.tryParse('${p['id']}') != null)
                    DropdownMenuItem(value: int.parse('${p['id']}'), child: Text('${p['name']}')),
              ],
              onChanged: (v) => setState(() => _expPersonalId = v),
            ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _expAmountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Monto *', prefixText: Currency.prefix, border: OutlineInputBorder(), isDense: true),
          onChanged: (_) => setState(() {}),
        ),
        if (amount != null && amount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              amount > available + 0.001
                  ? 'Supera el efectivo disponible (${_money.format(available)}).'
                  : 'La caja quedará con ${_money.format(available - amount)}.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: amount > available + 0.001 ? AppPalette.rose : const Color(0xFF6A8299),
              ),
            ),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: _expNotesCtrl,
          maxLines: 2,
          maxLength: 500,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: upperCaseFormatters,
          decoration: const InputDecoration(
            labelText: 'Notas (opcional)',
            hintText: 'Ej. pago de luz del mes',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _ctrl.saving ? null : () => setState(() => _expensing = false),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _ctrl.saving ? null : () => _registerExpense(available),
                style: FilledButton.styleFrom(backgroundColor: AppPalette.rose),
                child: _ctrl.saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Registrar gasto'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Etiquetas como en el selector de la web.
  String _expenseLabel(Map<String, dynamic> c) => switch ('${c['key']}') {
        'service_expense' => 'Servicio (básico / externo)',
        'staff_payment' => 'Pago a personal',
        'operating_expense' => 'Otro gasto operativo',
        _ => '${c['label'] ?? c['key']}',
      };

  Future<void> _registerExpense(double available) async {
    final amount = _parse(_expAmountCtrl.text);
    if (_expCategory == null) {
      _showMessage('Selecciona el tipo de gasto.', false);
      return;
    }
    if (_expCategory == 'staff_payment' && _expPersonalId == null) {
      _showMessage('Selecciona el personal al que se realiza el pago.', false);
      return;
    }
    if (amount == null || amount <= 0) {
      _showMessage('Ingresa un monto mayor a 0.', false);
      return;
    }
    if (amount > available + 0.001) {
      _showMessage('No hay suficiente efectivo en la caja; disponible ${_money.format(available)}.', false);
      return;
    }

    final result = await _ctrl.registerExpense(
      category: _expCategory!,
      personalId: _expCategory == 'staff_payment' ? _expPersonalId : null,
      amount: amount,
      notes: _expNotesCtrl.text.trim(),
    );
    if (!mounted) return;
    _showMessage(result.message, result.ok);
    if (result.ok) {
      setState(() {
        _expensing = false;
        _expCategory = null;
        _expPersonalId = null;
        _expAmountCtrl.clear();
        _expNotesCtrl.clear();
      });
    }
  }

  Widget _buildCloseForm(double expected) {
    final amount = _closingAmount;
    final diff = amount == null ? null : double.parse((amount - expected).toStringAsFixed(2));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Monto contado en caja', style: TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
        const SizedBox(height: 8),
        if (!_countByDenomination)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixText: Currency.prefix, border: OutlineInputBorder(), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => setState(() => _amountCtrl.text = expected.toStringAsFixed(2)),
                child: const Text('Usar esperado'),
              ),
            ],
          )
        else
          Column(
            children: [
              for (final d in _ctrl.denominations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(_denominationLabel(d), style: const TextStyle(fontSize: 13))),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _qtyCtrl('${d['key']}'),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            hintText: '0',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Total contado: ${_money.format(_breakdownTotal)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: () => setState(() => _countByDenomination = !_countByDenomination),
          icon: Icon(_countByDenomination ? Icons.edit_rounded : Icons.payments_rounded, size: 16),
          label: Text(_countByDenomination ? 'Ingresar el monto directamente' : 'Contar billetes y monedas'),
        ),
        if (diff != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              diff == 0
                  ? 'Cuadra con lo esperado.'
                  : diff > 0
                      ? 'Sobra ${_money.format(diff)} respecto a lo esperado.'
                      : 'Falta ${_money.format(-diff)} respecto a lo esperado.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: diff == 0 ? const Color(0xFF15803D) : diff > 0 ? const Color(0xFFD97706) : AppPalette.rose,
              ),
            ),
          ),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: upperCaseFormatters,
          decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _ctrl.saving ? null : () => setState(() => _closing = false),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _ctrl.saving ? null : _close,
                style: FilledButton.styleFrom(backgroundColor: AppPalette.rose),
                child: _ctrl.saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Cerrar caja'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Sin caja abierta ───────────────────────────────────────────────────────

  Widget _buildClosed() {
    final openError = _ctrl.openError;
    final registers = _ctrl.registers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusBadge(open: false),
        const SizedBox(height: 16),
        if (openError != null)
          Text(openError, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9B1C1C)))
        else if (!_ctrl.canOperate)
          const Text('No tienes permiso para aperturar caja.',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6A8299)))
        else ...[
          if (_ctrl.isManager && registers.length > 1) ...[
            const Text('Selecciona la caja a aperturar',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
            const SizedBox(height: 8),
            for (final r in registers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _registerCard(
                  r,
                  selected: '${r['id']}' == '$_registerId',
                  onTap: () => setState(() => _registerId = int.tryParse('${r['id']}')),
                ),
              ),
          ] else if (registers.isNotEmpty)
            _registerCard(registers.first),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto de apertura',
              hintText: '0',
              prefixText: Currency.prefix,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: upperCaseFormatters,
            decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _ctrl.saving ? null : _open,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              minimumSize: const Size.fromHeight(48),
            ),
            icon: _ctrl.saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.lock_open_rounded),
            label: const Text('Aperturar caja'),
          ),
        ],
      ],
    );
  }

  // ── Piezas ─────────────────────────────────────────────────────────────────

  Widget _statusBadge({required bool open}) {
    final color = open ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: open ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(open ? Icons.lock_open_rounded : Icons.lock_rounded, color: color),
          const SizedBox(width: 8),
          Text(
            open ? 'CAJA ABIERTA' : 'SIN CAJA ABIERTA',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: open ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }

  Widget _registerCard(Map<String, dynamic> register, {String? subtitle, bool selected = false, VoidCallback? onTap}) {
    final branch = (register['branch'] as Map?)?.cast<String, dynamic>();
    final color = hexColor(branch?['color']?.toString(), fallback: AppPalette.deepBlue);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : const Color(0xFFE2ECF5), width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(width: 8, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(register['name']?.toString() ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink)),
                  if (branch != null)
                    Text(branch['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                  if (subtitle != null)
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                ],
              ),
            ),
            if (onTap != null)
              Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? color : const Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }
}
