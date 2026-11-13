import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/number_utils.dart';
import '../cash/cash_session_detail_screen.dart';
import '../reports/report_detail_screen.dart';
import '../widgets/common_widgets.dart';

/// Movimientos de caja (mismos datos que el reporte de movimientos de la web): buscador, filtros
/// (fechas, tipo, categoría, sucursal, caja), totales de lo filtrado y movimientos agrupados por día.
/// Al tocar un movimiento se ve su detalle y se puede ir al préstamo, venta o compra que lo originó.
class MovimientosTab extends StatefulWidget {
  const MovimientosTab({super.key, required this.api, required this.logger, required this.money});

  final ApiService api;
  final ErrorLogService logger;
  final NumberFormat money;

  @override
  State<MovimientosTab> createState() => _MovimientosTabState();
}

class _MovimientosTabState extends State<MovimientosTab> {
  final _searchCtrl = TextEditingController();
  final _shortFmt = DateFormat('dd/MM/yyyy');

  Map<String, dynamic> _filters = {};
  Map<String, dynamic> _options = {};
  Map<String, dynamic> _totals = {};
  final List<Map<String, dynamic>> _rows = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
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
      final data = await widget.api.reportOptions();
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
      final data = await widget.api.report(
        'movements',
        filters: {..._filters, 'q': _searchCtrl.text.trim()},
        page: page,
      );
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
        await widget.logger.logError(module: 'movements', error: e, stackTrace: st, endpoint: '/reports/movements');
      }
      if (!mounted) return;
      final message = apiErrorMessage(e, fallback: 'No se pudieron cargar los movimientos.');
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
      builder: (_) => ReportFiltersSheet(
        kind: ReportKind.movements,
        initial: _filters,
        statuses: const [],
        branches: _optionList('branches'),
        cashRegisters: _optionList('cash_registers'),
        methods: const [],
        categories: _optionList('movement_categories'),
      ),
    );
    if (result == null) return;
    setState(() => _filters = Map<String, dynamic>.from(result)..remove('q'));
    _load();
  }

  String _filtersText() {
    String find(String key, String idField, String labelField, dynamic value) {
      final match = _optionList(key).where((o) => '${o[idField]}' == '$value');
      return match.isEmpty ? '$value' : '${match.first[labelField]}';
    }

    String date(dynamic raw) {
      final d = DateTime.tryParse('${raw ?? ''}');
      return d == null ? '-' : _shortFmt.format(d);
    }

    final f = _filters;
    bool has(String k) => '${f[k] ?? ''}'.isNotEmpty;
    return [
      if (has('date_from')) 'Desde ${date(f['date_from'])}',
      if (has('date_to')) 'Hasta ${date(f['date_to'])}',
      if (has('type')) f['type'] == 'income' ? 'Ingresos' : 'Egresos',
      if (has('category')) find('movement_categories', 'key', 'label', f['category']),
      if (has('branch_id')) find('branches', 'id', 'name', f['branch_id']),
      if (has('cash_register_id')) find('cash_registers', 'id', 'name', f['cash_register_id']),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          const AppHeader(title: 'Movimientos', subtitle: 'Ingresos y egresos de caja'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      hintText: 'Buscar por descripción…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _load),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _FilterButton(count: _activeFilterCount, onPressed: _openFilters),
              ],
            ),
          ),
          if (_activeFilterCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_filtersText(), style: const TextStyle(fontSize: 12, color: AppPalette.deepBlue)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _filters = {});
                      _load();
                    },
                    child: const Text('Quitar filtros'),
                  ),
                ],
              ),
            ),
          if (_loading)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
                ],
              ),
            )
          else ...[
            Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 4), child: _totalsRow()),
            if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hay movimientos para los filtros elegidos.', textAlign: TextAlign.center),
              )
            else
              ..._groupedRows(),
            if (_page < _lastPage)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
    );
  }

  Widget _totalsRow() {
    final utilidad = asDouble(_totals['utilidad']);
    Widget box(String label, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6EEF5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        box('Ingresos', widget.money.format(asDouble(_totals['ingresos'])), const Color(0xFF198754)),
        const SizedBox(width: 8),
        box('Egresos', widget.money.format(asDouble(_totals['egresos'])), AppPalette.rose),
        const SizedBox(width: 8),
        box('Utilidad', widget.money.format(utilidad), utilidad >= 0 ? const Color(0xFF198754) : AppPalette.rose),
      ],
    );
  }

  /// Movimientos agrupados por día, con el encabezado de la fecha.
  List<Widget> _groupedRows() {
    final widgets = <Widget>[];
    String? lastDay;
    for (final m in _rows) {
      final date = DateTime.tryParse('${m['date'] ?? ''}')?.toLocal();
      final day = date == null ? 'Sin fecha' : _dayLabel(date);
      if (day != lastDay) {
        lastDay = day;
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 20, 6),
          child: Text(
            day,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6A8299)),
          ),
        ));
      }
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: MovementTile(
          movement: m,
          money: widget.money,
          showRegister: true,
          onTap: () => showMovementSheet(context, api: widget.api, logger: widget.logger, movement: m),
        ),
      ));
    }
    return widgets;
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'HOY';
    if (day == today.subtract(const Duration(days: 1))) return 'AYER';
    // La app no carga los datos de idioma de intl: nombres en español a mano.
    const days = ['LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO', 'DOMINGO'];
    const months = [
      'ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO',
      'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE',
    ];
    final year = d.year == now.year ? '' : ' DE ${d.year}';
    return '${days[d.weekday - 1]} ${d.day} DE ${months[d.month - 1]}$year';
  }
}

/// Botón de filtros con la cantidad de filtros activos.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: 'Filtros',
      onPressed: onPressed,
      icon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.filter_list_rounded)),
    );
  }
}
