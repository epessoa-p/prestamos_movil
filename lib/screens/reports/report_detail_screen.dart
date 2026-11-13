import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:path_provider/path_provider.dart';

import '../../app/session_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';
import '../cash/cash_session_detail_screen.dart';
import '../clients/client_detail_screen.dart';
import '../loans/loan_detail_screen.dart';
import '../payments/payment_detail_screen.dart';
import '../widgets/common_widgets.dart';
import '../widgets/file_ready_sheet.dart';

/// Los reportes de la web (`/reports/{key}` en la API) y qué filtros usa cada uno.
enum ReportKind {
  loans(
    'loans',
    'Préstamos',
    'Cartera por estado, sucursal y fechas: montos, pagos y pendiente.',
    Icons.account_balance_wallet_rounded,
    search: true,
    status: 'loan_statuses',
    branch: true,
    dates: true,
  ),
  payments(
    'payments',
    'Pagos',
    'Cobros recibidos por fecha y método, con capital e intereses.',
    Icons.payments_rounded,
    search: true,
    method: true,
    dates: true,
  ),
  movements(
    'movements',
    'Movimientos de caja',
    'Ingresos, egresos y utilidad operativa, por categoría.',
    Icons.swap_vert_rounded,
    search: true,
    branch: true,
    cashRegister: true,
    movementType: true,
    dates: true,
  ),
  closures(
    'closures',
    'Cierres de caja',
    'Sesiones de caja: apertura, cierre, esperado y descuadres.',
    Icons.point_of_sale_rounded,
    status: 'closure_statuses',
    branch: true,
    cashRegister: true,
    dates: true,
  ),
  clients(
    'clients',
    'Cartera de clientes',
    'Préstamos, total prestado, pagado y pendiente por cliente.',
    Icons.people_alt_rounded,
    search: true,
    status: 'client_statuses',
  ),
  warehouses(
    'warehouses',
    'Almacenes',
    'Prendas en custodia por almacén: retenidas, en mora y para venta.',
    Icons.warehouse_rounded,
  );

  const ReportKind(
    this.key,
    this.title,
    this.description,
    this.icon, {
    this.search = false,
    this.status,
    this.branch = false,
    this.cashRegister = false,
    this.method = false,
    this.movementType = false,
    this.dates = false,
  });

  final String key;
  final String title;
  final String description;
  final IconData icon;
  final bool search;
  final String? status; // clave de las opciones de estado en /reports/options
  final bool branch;
  final bool cashRegister;
  final bool method;
  final bool movementType;
  final bool dates;

  bool get hasFilters => status != null || branch || cashRegister || method || movementType || dates;
}

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({
    super.key,
    required this.api,
    required this.logger,
    required this.session,
    required this.kind,
  });

  final ApiService api;
  final ErrorLogService logger;
  final SessionController session;
  final ReportKind kind;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final _money = Currency.formatter();
  final _date = DateFormat('dd/MM/yyyy');
  final _dateTime = DateFormat('dd/MM/yyyy HH:mm');
  final _searchCtrl = TextEditingController();

  Map<String, dynamic> _filters = {};
  Map<String, dynamic> _options = {};
  Map<String, dynamic> _totals = {};
  final List<Map<String, dynamic>> _rows = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _downloading = false;
  String? _error;

  ReportKind get kind => widget.kind;

  @override
  void initState() {
    super.initState();
    _load();
    if (kind.hasFilters) _loadOptions();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final data = await widget.api.reportOptions();
      if (mounted) setState(() => _options = data);
    } catch (_) {
      // Sin opciones solo se pierden los combos de filtros; el reporte se ve igual.
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
      final data = await widget.api.report(kind.key, filters: _filters, page: page);
      if (!mounted) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll((data['data'] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
        _totals = data['totals'] is Map ? Map<String, dynamic>.from(data['totals']) : {};
        _page = asInt(data['current_page'], fallback: page);
        _lastPage = asInt(data['last_page'], fallback: 1);
        _total = asInt(data['total']);
      });
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'reports', error: e, stackTrace: st, endpoint: '/reports/${kind.key}');
      }
      if (!mounted) return;
      final message = apiErrorMessage(e, fallback: 'No se pudo cargar el reporte.');
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

  void _search() {
    _filters = {..._filters, 'q': _searchCtrl.text.trim()};
    _load();
  }

  // ── Filtros ───────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _optionList(String key) =>
      (_options[key] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  List<(String, String)> _statusChoices() {
    if (kind.status == 'closure_statuses') return const [('open', 'Abiertas'), ('closed', 'Cerradas')];
    return _optionList(kind.status ?? '').map((s) => ('${s['key']}', '${s['label']}')).toList();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReportFiltersSheet(
        kind: kind,
        initial: _filters,
        statuses: _statusChoices(),
        branches: _optionList('branches'),
        cashRegisters: _optionList('cash_registers'),
        methods: (_options['payment_methods'] as List? ?? const []).map((m) => '$m').toList(),
        categories: _optionList('movement_categories'),
      ),
    );
    if (result == null) return;
    setState(() => _filters = {...result, 'q': _filters['q']});
    _load();
  }

  int get _activeFilterCount =>
      _filters.entries.where((e) => e.key != 'q' && e.value != null && '${e.value}'.isNotEmpty).length;

  // ── Exportar ──────────────────────────────────────────────────────────────

  Future<void> _export() async {
    final choice = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Descargar reporte', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'Con los filtros aplicados. Luego puedes abrirlo o compartirlo (WhatsApp, correo…).',
                style: TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
              ),
              const SizedBox(height: 10),
              for (final (format, detail, label, icon, color) in const [
                ('pdf', 'summary', 'PDF resumen', Icons.picture_as_pdf_rounded, Color(0xFFD32F2F)),
                ('pdf', 'detailed', 'PDF detallado', Icons.picture_as_pdf_rounded, Color(0xFFD32F2F)),
                ('excel', 'summary', 'Excel resumen', Icons.grid_on_rounded, Color(0xFF2E7D32)),
                ('excel', 'detailed', 'Excel detallado', Icons.grid_on_rounded, Color(0xFF2E7D32)),
              ])
                ListTile(
                  leading: Icon(icon, color: color),
                  title: Text(label),
                  onTap: () => Navigator.pop(ctx, (format, detail)),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _downloading = true);
    try {
      final dir = await getTemporaryDirectory();
      final path = await widget.api.downloadReport(
        kind.key,
        format: choice.$1,
        detail: choice.$2,
        dir: dir.path,
        filters: _filters,
      );
      if (!mounted) return;
      await _afterDownload(path);
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(
          module: 'reports_export',
          error: e,
          stackTrace: st,
          endpoint: '/reports/${kind.key}/export',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(e, fallback: 'No se pudo descargar el reporte.')),
            backgroundColor: AppPalette.rose,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _afterDownload(String path) =>
      showFileReadySheet(context, path: path, title: 'Reporte listo', shareText: kind.title);

  // ── Vista ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        title: Text(kind.title),
        backgroundColor: AppPalette.deepBlue,
        foregroundColor: Colors.white,
        actions: [
          if (kind.hasFilters)
            IconButton(
              tooltip: 'Filtros',
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: _activeFilterCount > 0,
                label: Text('$_activeFilterCount'),
                child: const Icon(Icons.filter_list_rounded),
              ),
            ),
          IconButton(
            tooltip: 'Descargar PDF / Excel',
            onPressed: _downloading ? null : _export,
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (kind.search)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Buscar…',
                    isDense: true,
                    suffixIcon: IconButton(icon: const Icon(Icons.search_rounded), onPressed: _search),
                  ),
                ),
              ),
            if (_activeFilterCount > 0) _activeFiltersBar(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
              )
            else ...[
              _totalsGrid(),
              const SizedBox(height: 12),
              Text(
                '$_total ${_total == 1 ? 'registro' : 'registros'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              if (_rows.isEmpty)
                const Card(
                  child: Padding(padding: EdgeInsets.all(16), child: Text('Sin registros para los filtros elegidos.')),
                )
              else
                ..._rows.map(_rowCard),
              if (_page < _lastPage)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: _loadingMore ? null : () => _load(more: true),
                    child: _loadingMore
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Ver más (${_total - _rows.length} restantes)'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _activeFiltersBar() {
    final parts = <String>[];
    if ('${_filters['date_from'] ?? ''}'.isNotEmpty) parts.add('Desde ${_fmtDate(_filters['date_from'])}');
    if ('${_filters['date_to'] ?? ''}'.isNotEmpty) parts.add('Hasta ${_fmtDate(_filters['date_to'])}');
    for (final key in ['status', 'branch_id', 'cash_register_id', 'payment_method', 'type', 'category']) {
      if ('${_filters[key] ?? ''}'.isNotEmpty) parts.add(_filterLabel(key, _filters[key]));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(parts.join(' · '), style: const TextStyle(fontSize: 12, color: AppPalette.deepBlue)),
          ),
          TextButton(
            onPressed: () {
              setState(() => _filters = {'q': _filters['q']});
              _load();
            },
            child: const Text('Quitar filtros'),
          ),
        ],
      ),
    );
  }

  String _filterLabel(String key, dynamic value) {
    String find(String optionKey, String idField, String labelField) {
      final match = _optionList(optionKey).where((o) => '${o[idField]}' == '$value');
      return match.isEmpty ? '$value' : '${match.first[labelField]}';
    }

    return switch (key) {
      'status' => _statusChoices().where((s) => s.$1 == '$value').map((s) => s.$2).firstOrNull ?? '$value',
      'branch_id' => find('branches', 'id', 'name'),
      'cash_register_id' => find('cash_registers', 'id', 'name'),
      'category' => find('movement_categories', 'key', 'label'),
      'type' => value == 'income' ? 'Ingresos' : 'Egresos',
      _ => '$value',
    };
  }

  String _fmtDate(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}');
    return d == null ? '-' : _date.format(d);
  }

  String _fmtDateTime(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}');
    return d == null ? '-' : _dateTime.format(d.toLocal());
  }

  Widget _totalsGrid() {
    final t = _totals;
    String m(String k) => _money.format(asDouble(t[k]));
    final items = <(String, String, Color)>[
      ...switch (kind) {
        ReportKind.loans => [
          ('Préstamos', '${t['count'] ?? 0}', AppPalette.deepBlue),
          ('Monto', m('amount'), const Color(0xFF198754)),
          ('Pagado', m('paid'), const Color(0xFF198754)),
          ('Pendiente', m('pending'), AppPalette.rose),
        ],
        ReportKind.payments => [
          ('Pagos', '${t['count'] ?? 0}', AppPalette.deepBlue),
          ('Total cobrado', m('amount'), const Color(0xFF198754)),
          ('Capital', m('capital'), AppPalette.deepBlue),
          ('Intereses', m('interest'), const Color(0xFF6F42C1)),
        ],
        ReportKind.movements => [
          ('Ingresos', m('ingresos'), const Color(0xFF198754)),
          ('Egresos', m('egresos'), AppPalette.rose),
          ('Utilidad', m('utilidad'), asDouble(t['utilidad']) >= 0 ? const Color(0xFF198754) : AppPalette.rose),
          ('Movimientos', '${t['transacciones'] ?? 0}', AppPalette.deepBlue),
          if (asDouble(t['aportes']) > 0) ('Aportes (no operativo)', m('aportes'), const Color(0xFF6C757D)),
        ],
        ReportKind.closures => [
          ('Sesiones', '${t['sessions'] ?? 0}', AppPalette.deepBlue),
          ('Abiertas', '${t['open_sessions'] ?? 0}', const Color(0xFF198754)),
          ('Cerradas', '${t['closed_sessions'] ?? 0}', const Color(0xFF6C757D)),
          (
            'Descuadres',
            '${t['mismatches'] ?? 0}',
            asInt(t['mismatches']) > 0 ? AppPalette.rose : const Color(0xFF198754),
          ),
        ],
        ReportKind.clients => [
          ('Clientes', '${t['clients'] ?? 0}', AppPalette.deepBlue),
          ('Préstamos', '${t['loans'] ?? 0}', const Color(0xFF6F42C1)),
          ('Prestado', m('borrowed'), const Color(0xFF198754)),
          ('Pendiente', m('pending'), AppPalette.rose),
        ],
        ReportKind.warehouses => [
          ('Almacenes', '${t['warehouses'] ?? 0}', AppPalette.deepBlue),
          ('En custodia', '${t['total_collateral'] ?? 0}', const Color(0xFF6F42C1)),
          ('En mora', '${t['total_stored'] ?? 0}', const Color(0xFFE76F51)),
          ('Para la venta', '${t['total_sellable'] ?? 0}', AppPalette.rose),
        ],
      },
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.6,
      children: [
        for (final (label, value, color) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6EEF5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Qué se abre al tocar una fila del reporte (null = nada, p. ej. almacenes).
  VoidCallback? _onTapFor(Map<String, dynamic> r) {
    final id = int.tryParse('${r['id'] ?? ''}');
    if (id == null) return null;
    final api = widget.api;
    final logger = widget.logger;
    void open(Widget Function() builder) =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => builder()));

    return switch (kind) {
      ReportKind.loans => () => open(() => LoanDetailScreen(api: api, logger: logger, loanId: id)),
      ReportKind.payments => () => open(() => PaymentDetailScreen(api: api, logger: logger, paymentId: id)),
      ReportKind.movements => () => showMovementSheet(context, api: api, logger: logger, movement: r),
      ReportKind.closures => () => open(() => CashSessionDetailScreen(api: api, logger: logger, sessionId: id)),
      ReportKind.clients => () =>
          open(() => ClientDetailScreen(api: api, logger: logger, clientId: id, session: widget.session)),
      ReportKind.warehouses => null,
    };
  }

  Widget _rowCard(Map<String, dynamic> r) {
    const muted = TextStyle(fontSize: 12, color: Color(0xFF6A8299));
    Widget tile(String title, String subtitle, Widget trailing, {Widget? extra}) => Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        onTap: _onTapFor(r),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: extra == null
            ? Text(subtitle, style: muted)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  extra,
                  const SizedBox(height: 2),
                  Text(subtitle, style: muted),
                ],
              ),
        trailing: trailing,
      ),
    );
    Widget amounts(String main, {String? second, Color mainColor = AppPalette.ink, Color? secondColor}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          main,
          style: TextStyle(fontWeight: FontWeight.w800, color: mainColor),
        ),
        if (second != null) Text(second, style: TextStyle(fontSize: 11, color: secondColor ?? const Color(0xFF6A8299))),
      ],
    );

    return switch (kind) {
      ReportKind.loans => tile(
        '${r['code']} · ${r['client'] ?? 'Sin cliente'}',
        [r['product'], r['branch'], r['status_label'], _fmtDate(r['date'])].where((v) => v != null).join(' · '),
        amounts(
          _money.format(asDouble(r['amount'])),
          second: 'Pend. ${_money.format(asDouble(r['pending']))}',
          secondColor: asDouble(r['pending']) > 0 ? AppPalette.rose : null,
        ),
      ),
      ReportKind.payments => tile(
        '${r['loan_code'] ?? '-'} · ${r['client'] ?? 'Sin cliente'}',
        [
          _fmtDate(r['date']),
          r['type_label'] ?? PaymentTypeChip.labels[r['type']] ?? r['type'],
          r['method_label'] ?? r['method'],
          r['registered_by'],
        ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
        amounts(_money.format(asDouble(r['amount'])), mainColor: const Color(0xFF198754)),
        extra: r['branch'] is Map ? Align(alignment: Alignment.centerLeft, child: BranchPill.from(r['branch'], dense: true)) : null,
      ),
      ReportKind.movements => MovementTile(movement: r, money: _money, showRegister: true, onTap: _onTapFor(r)),
      ReportKind.closures => tile(
        '${r['cash_register'] ?? 'Caja'}',
        '${_fmtDateTime(r['opened_at'])} → ${r['closed_at'] == null ? 'En curso' : _fmtDateTime(r['closed_at'])}\n'
            '+${_money.format(asDouble(r['income']))}  −${_money.format(asDouble(r['expense']))} · ${r['closed_by'] ?? r['opened_by'] ?? ''}',
        r['mismatch'] == null
            ? amounts(r['closed_at'] == null ? 'Abierta' : '-', mainColor: const Color(0xFF198754))
            : asDouble(r['mismatch']).abs() < 0.01
                // Cuadra: solo la etiqueta en verde, sin la palabra "descuadre".
                ? amounts('Cuadra', mainColor: const Color(0xFF198754))
                // Descuadre: monto y tipo (sobrante o faltante) en rojo.
                : amounts(
                    '${asDouble(r['mismatch']) > 0 ? '+' : ''}${_money.format(asDouble(r['mismatch']))}',
                    second: asDouble(r['mismatch']) > 0 ? 'Sobrante' : 'Faltante',
                    mainColor: AppPalette.rose,
                    secondColor: AppPalette.rose,
                  ),
      ),
      ReportKind.clients => tile(
        '${r['name']}',
        [
          if ('${r['id_number'] ?? ''}'.isNotEmpty) 'CI ${r['id_number']}',
          '${r['loans_count']} préstamos',
          if (asInt(r['overdue_loans']) > 0) '${r['overdue_loans']} en mora',
        ].join(' · '),
        amounts(
          _money.format(asDouble(r['borrowed'])),
          second: 'Pend. ${_money.format(asDouble(r['pending']))}',
          secondColor: asDouble(r['pending']) > 0 ? AppPalette.rose : null,
        ),
      ),
      ReportKind.warehouses => tile(
        '${r['name']}',
        '${r['branch'] ?? 'Sin sucursal'} · retenidas ${r['retained']} · en mora ${r['stored']}',
        amounts('${r['total']} prendas', second: '${r['sellable']} para venta', secondColor: AppPalette.rose),
      ),
    };
  }
}

/// Hoja de filtros: solo muestra los que usa el reporte (también la usa la pestaña Movimientos).
class ReportFiltersSheet extends StatefulWidget {
  const ReportFiltersSheet({
    super.key,
    required this.kind,
    required this.initial,
    required this.statuses,
    required this.branches,
    required this.cashRegisters,
    required this.methods,
    required this.categories,
  });

  final ReportKind kind;
  final Map<String, dynamic> initial;
  final List<(String, String)> statuses;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> cashRegisters;
  final List<String> methods;
  final List<Map<String, dynamic>> categories;

  @override
  State<ReportFiltersSheet> createState() => _ReportFiltersSheetState();
}

class _ReportFiltersSheetState extends State<ReportFiltersSheet> {
  late final Map<String, dynamic> _f = Map<String, dynamic>.from(widget.initial)..remove('q');
  final _fmt = DateFormat('dd/MM/yyyy');

  Future<void> _pickDate(String key) async {
    final current = DateTime.tryParse('${_f[key] ?? ''}') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _f[key] = DateFormat('yyyy-MM-dd').format(picked));
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
      _f['date_from'] = DateFormat('yyyy-MM-dd').format(from);
      _f['date_to'] = DateFormat('yyyy-MM-dd').format(to);
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
          for (final (v, l) in items)
            DropdownMenuItem(
              value: v,
              child: Text(l, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _f[key] = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
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
              const Text('Filtros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (k.dates) ...[
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
              ],
              if (k.status != null) _dropdown('status', 'Estado', widget.statuses),
              if (k.branch)
                _dropdown('branch_id', 'Sucursal', [for (final b in widget.branches) ('${b['id']}', '${b['name']}')]),
              if (k.cashRegister)
                _dropdown('cash_register_id', 'Caja', [
                  for (final c in widget.cashRegisters) ('${c['id']}', '${c['name']}'),
                ]),
              if (k.method) _dropdown('payment_method', 'Método de pago', [for (final m in widget.methods) (m, m)]),
              if (k.movementType) ...[
                _dropdown('type', 'Tipo', const [('income', 'Ingresos'), ('expense', 'Egresos')]),
                _dropdown('category', 'Categoría', [
                  for (final c in widget.categories) ('${c['key']}', '${c['label']}'),
                ]),
              ],
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
