import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';
import '../payments/payment_detail_screen.dart';
import '../widgets/common_widgets.dart';

/// Pagos de préstamos: buscador, filtros (fechas, sucursal, método, tipo), total de lo filtrado
/// y tarjetas con sucursal, cajero y fecha. Al tocar un pago se abre su detalle (con el recibo).
class PagosScreen extends StatefulWidget {
  const PagosScreen({super.key, required this.api, required this.logger});

  final ApiService api;
  final ErrorLogService logger;

  @override
  State<PagosScreen> createState() => _PagosScreenState();
}

class _PagosScreenState extends State<PagosScreen> {
  final _money = Currency.formatter();
  final _date = DateFormat('dd/MM/yyyy');
  final _time = DateFormat('HH:mm');
  final _searchCtrl = TextEditingController();

  Map<String, dynamic> _filters = {};
  Map<String, dynamic> _options = {};
  final List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _totals = {};
  int _page = 1;
  int _lastPage = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOptions();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final data = await widget.api.paymentOptions();
      if (mounted) setState(() => _options = data);
    } catch (_) {
      // Sin opciones solo se pierden los combos de filtros.
    }
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = more ? _page + 1 : 1;
      final data = await widget.api.payments(query: _searchCtrl.text.trim(), filters: _filters, page: page);
      if (!mounted) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll((data['data'] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
        _totals = data['totals'] is Map ? Map<String, dynamic>.from(data['totals']) : {};
        _page = asInt(data['current_page'], fallback: page);
        _lastPage = asInt(data['last_page'], fallback: 1);
      });
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'payments', error: e, stackTrace: st, endpoint: '/payments');
      }
      if (!mounted) return;
      final message = apiErrorMessage(e, fallback: 'No se pudieron cargar los pagos.');
      if (more) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      } else {
        setState(() => _error = message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _optionList(String key) =>
      (_options[key] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  int get _activeFilterCount => _filters.values.where((v) => v != null && '$v'.isNotEmpty).length;

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PaymentFiltersSheet(
        initial: _filters,
        branches: _optionList('branches'),
        methods: _optionList('methods'),
        types: _optionList('types'),
      ),
    );
    if (result == null) return;
    setState(() => _filters = result);
    _load();
  }

  Future<void> _openPayment(Map<String, dynamic> p) async {
    final id = int.tryParse('${p['id']}');
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PaymentDetailScreen(api: widget.api, logger: widget.logger, paymentId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = asInt(_totals['count']);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        title: const Text('Pagos'),
        backgroundColor: AppPalette.deepBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Filtros',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              child: const Icon(Icons.filter_list_rounded),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Cliente, PR-00012 o referencia…',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _load),
              ),
            ),
            const SizedBox(height: 10),
            if (_activeFilterCount > 0) _activeFiltersBar(),
            if (_loading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              _messageCard(Icons.error_outline_rounded, _error!, retry: true)
            else ...[
              _summaryCard(count),
              const SizedBox(height: 12),
              if (_rows.isEmpty)
                _messageCard(Icons.receipt_long_rounded, 'No hay pagos para los filtros elegidos.')
              else
                ..._rows.map(_paymentCard),
              if (_page < _lastPage)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: _loadingMore ? null : () => _load(more: true),
                    child: _loadingMore
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Ver más (${count - _rows.length} restantes)'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(int count) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppPalette.deepBlue, Color(0xFF1F6FA8)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.payments_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _activeFilterCount > 0 || _searchCtrl.text.trim().isNotEmpty ? 'Total filtrado' : 'Total cobrado',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _money.format(asDouble(_totals['amount'])),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$count ${count == 1 ? 'pago' : 'pagos'}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(Map<String, dynamic> p) {
    final date = DateTime.tryParse('${p['payment_date'] ?? ''}');
    final registered = DateTime.tryParse('${p['registered_at'] ?? ''}')?.toLocal();
    final when = [
      if (date != null) _date.format(date),
      if (registered != null) _time.format(registered),
    ].join(' ');
    const muted = TextStyle(fontSize: 12, color: Color(0xFF6A8299));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EEF5)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPayment(p),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p['client_name'] ?? 'Sin cliente'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [p['loan_code'], p['product_name']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _money.format(asDouble(p['amount'])),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF198754)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PaymentTypeChip(type: '${p['payment_type'] ?? ''}', label: p['type_label']?.toString()),
                    BranchPill.from(p['branch']),
                    if ('${p['method_label'] ?? ''}'.isNotEmpty) Text('${p['method_label']}', style: muted),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 14, color: Color(0xFF9DB1C3)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${p['registered_by_name'] ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                    const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF9DB1C3)),
                    const SizedBox(width: 4),
                    Text(when.isEmpty ? '-' : when, style: muted),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activeFiltersBar() {
    String find(String optionKey, String idField, dynamic value) {
      final match = _optionList(optionKey).where((o) => '${o[idField]}' == '$value');
      return match.isEmpty ? '$value' : '${match.first[optionKey == 'branches' ? 'name' : 'label']}';
    }

    String fmt(dynamic raw) {
      final d = DateTime.tryParse('${raw ?? ''}');
      return d == null ? '-' : _date.format(d);
    }

    final parts = <String>[
      if ('${_filters['date_from'] ?? ''}'.isNotEmpty) 'Desde ${fmt(_filters['date_from'])}',
      if ('${_filters['date_to'] ?? ''}'.isNotEmpty) 'Hasta ${fmt(_filters['date_to'])}',
      if ('${_filters['branch_id'] ?? ''}'.isNotEmpty) find('branches', 'id', _filters['branch_id']),
      if ('${_filters['payment_method'] ?? ''}'.isNotEmpty) find('methods', 'key', _filters['payment_method']),
      if ('${_filters['payment_type'] ?? ''}'.isNotEmpty) find('types', 'key', _filters['payment_type']),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(parts.join(' · '), style: const TextStyle(fontSize: 12, color: AppPalette.deepBlue))),
          TextButton(
            onPressed: () {
              setState(() => _filters = {});
              _load();
            },
            child: const Text('Quitar filtros'),
          ),
        ],
      ),
    );
  }

  Widget _messageCard(IconData icon, String text, {bool retry = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EEF5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: const Color(0xFF9DB1C3)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6A8299))),
          if (retry) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ],
      ),
    );
  }
}

/// Hoja de filtros de pagos: rango de fechas, sucursal, método y tipo.
class _PaymentFiltersSheet extends StatefulWidget {
  const _PaymentFiltersSheet({
    required this.initial,
    required this.branches,
    required this.methods,
    required this.types,
  });

  final Map<String, dynamic> initial;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> methods;
  final List<Map<String, dynamic>> types;

  @override
  State<_PaymentFiltersSheet> createState() => _PaymentFiltersSheetState();
}

class _PaymentFiltersSheetState extends State<_PaymentFiltersSheet> {
  late final Map<String, dynamic> _f = Map<String, dynamic>.from(widget.initial);
  final _fmt = DateFormat('dd/MM/yyyy');
  final _iso = DateFormat('yyyy-MM-dd');

  Future<void> _pickDate(String key) async {
    final current = DateTime.tryParse('${_f[key] ?? ''}') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _f[key] = _iso.format(picked));
  }

  void _quickRange(String range) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final (from, to) = switch (range) {
      'today' => (today, today),
      'week' => (today.subtract(Duration(days: today.weekday - 1)), today),
      'month' => (DateTime(today.year, today.month, 1), today),
      _ => (DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 0)),
    };
    setState(() {
      _f['date_from'] = _iso.format(from);
      _f['date_to'] = _iso.format(to);
    });
  }

  Widget _dropdown(String key, String label, List<(String, String)> items) {
    final value = '${_f[key] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: items.any((i) => i.$1 == value) ? value : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => _f[key] = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String dateText(String key) {
      final d = DateTime.tryParse('${_f[key] ?? ''}');
      return d == null ? 'Sin fecha' : _fmt.format(d);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Filtrar pagos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final (key, label) in const [
                    ('today', 'Hoy'),
                    ('week', 'Esta semana'),
                    ('month', 'Este mes'),
                    ('last', 'Mes pasado'),
                  ])
                    ActionChip(label: Text(label), onPressed: () => _quickRange(key)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate('date_from'),
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text('Desde: ${dateText('date_from')}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate('date_to'),
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text('Hasta: ${dateText('date_to')}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.branches.length > 1)
                _dropdown('branch_id', 'Sucursal', [for (final b in widget.branches) ('${b['id']}', '${b['name']}')]),
              _dropdown('payment_type', 'Tipo de pago', [for (final t in widget.types) ('${t['key']}', '${t['label']}')]),
              _dropdown('payment_method', 'Método de pago', [
                for (final m in widget.methods) ('${m['key']}', '${m['label']}'),
              ]),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, <String, dynamic>{}),
                      child: const Text('Limpiar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(onPressed: () => Navigator.pop(context, _f), child: const Text('Aplicar')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
