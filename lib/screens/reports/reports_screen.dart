import 'package:flutter/material.dart';

import '../../app/session_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_errors.dart';
import '../../utils/currency.dart';
import '../../utils/number_utils.dart';
import 'report_detail_screen.dart';

/// Centro de reportes (como Reportes de la web): resumen y acceso a cada reporte.
class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key, required this.api, required this.logger, required this.session});

  final ApiService api;
  final ErrorLogService logger;
  final SessionController session;

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  final _money = Currency.formatter();

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
      final data = await widget.api.reportsSummary();
      if (!mounted) return;
      setState(() => _summary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary']) : {});
    } catch (e, st) {
      if (isUnexpectedApiError(e)) {
        await widget.logger.logError(module: 'reports', error: e, stackTrace: st, endpoint: '/reports/summary');
      }
      if (mounted) setState(() => _error = apiErrorMessage(e, fallback: 'No se pudo cargar el resumen.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(ReportKind kind) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => ReportDetailScreen(api: widget.api, logger: widget.logger, session: widget.session, kind: kind)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(title: const Text('Reportes'), backgroundColor: AppPalette.deepBlue, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.1,
                children: [
                  _stat('Préstamos', '${s['total_loans'] ?? 0}', '${s['active_loans'] ?? 0} activos', AppPalette.deepBlue),
                  _stat('Clientes', '${s['total_clients'] ?? 0}', 'registrados', const Color(0xFF6F42C1)),
                  _stat('Desembolsado', _money.format(asDouble(s['total_disbursed'])), 'total prestado', const Color(0xFF198754)),
                  _stat('Recaudado', _money.format(asDouble(s['total_collected'])), 'total cobrado', const Color(0xFF198754)),
                  _stat('Por cobrar', _money.format(asDouble(s['total_pending'])), 'préstamos abiertos', AppPalette.rose),
                  _stat(
                    'En mora / incumpl.',
                    '${s['overdue_loans'] ?? 0} / ${s['defaulted_loans'] ?? 0}',
                    'préstamos',
                    const Color(0xFFE76F51),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            const Text('Reportes disponibles',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppPalette.ink)),
            const SizedBox(height: 8),
            for (final kind in ReportKind.values)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _open(kind),
                  leading: CircleAvatar(
                    backgroundColor: AppPalette.deepBlue.withValues(alpha: 0.1),
                    child: Icon(kind.icon, color: AppPalette.deepBlue),
                  ),
                  title: Text(kind.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(kind.description, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, String hint, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
            child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
          ),
          Text(hint, style: const TextStyle(fontSize: 10, color: Color(0xFF9DB1C3))),
        ],
      ),
    );
  }
}
