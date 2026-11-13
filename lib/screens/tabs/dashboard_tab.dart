import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../controllers/dashboard_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../utils/number_utils.dart';
import '../loans/loan_detail_screen.dart';
import '../widgets/common_widgets.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({
    super.key,
    required this.controller,
    required this.money,
    required this.api,
    required this.logger,
  });

  final DashboardController controller;
  final NumberFormat money;
  final ApiService api;
  final ErrorLogService logger;

  static Color _hexColor(String? hex) {
    if (hex == null) return const Color(0xFF6A8299);
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF6A8299);
    }
  }

  static String _loanTitle(Map<String, dynamic> map) {
    if (map['code'] != null) return map['code'].toString();
    if (map['numero'] != null) {
      final n = (map['numero'] as num).toInt();
      return 'PR-${n.toString().padLeft(5, '0')}';
    }
    return 'Préstamo #${map['id'] ?? '-'}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final summary = (controller.dashboard?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
        final company = (controller.dashboard?['company'] as Map?)?.cast<String, dynamic>() ?? {};
        final recent = (controller.dashboard?['recent_loans'] as List?) ?? <dynamic>[];

        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              AppHeader(
                title: 'Panel de control',
                subtitle: company['name']?.toString() ?? 'Empresa no definida',
              ),
              if (controller.loading)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    runSpacing: 12,
                    spacing: 12,
                    children: [
                      MetricCard(label: 'Prestamos activos', value: '${summary['active_loans'] ?? 0}', color: const Color(0xFF1E5E9D)),
                      MetricCard(label: 'Atrasados', value: '${summary['overdue_loans'] ?? 0}', color: const Color(0xFFFF6B6B)),
                      MetricCard(
                        label: 'Capital prestado por recuperar',
                        value: money.format(asDouble(summary['current_capital'])),
                        color: const Color(0xFF19C5B6),
                        wide: true,
                        hint: 'Lo que falta devolver de los ${summary['current_loans'] ?? 0} préstamos '
                            'activos y en mora (sin intereses).',
                      ),
                      MetricCard(
                        label: 'Total por cobrar hoy',
                        value: money.format(asDouble(summary['current_receivable'])),
                        color: const Color(0xFF6A8299),
                        wide: true,
                        hint: 'Capital por recuperar + ${money.format(asDouble(summary['current_interest']))} '
                            'de intereses sin pagar.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Prestamos recientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                ...recent.take(8).map((loan) {
                  final map = (loan as Map).cast<String, dynamic>();
                  final amount    = asDouble(map['amount']);
                  final capital   = asDouble(map['current_capital']);
                  final unpaidInt = asDouble(map['unpaid_interest_total']);
                  final pendiente = capital + unpaidInt;
                  final clientName = (map['client'] as Map?)?.cast<String, dynamic>()['name']?.toString() ?? '';
                  final branch = (map['branch'] as Map?)?.cast<String, dynamic>();
                  final branchName  = branch?['name']?.toString();
                  final branchColor = _hexColor(branch?['color']?.toString());
                  final loanId = (map['id'] as num?)?.toInt() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      clipBehavior: Clip.hardEdge,
                      child: InkWell(
                        onTap: loanId > 0
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LoanDetailScreen(
                                      api: api,
                                      logger: logger,
                                      loanId: loanId,
                                    ),
                                  ),
                                )
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _loanTitle(map),
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                    if (clientName.isNotEmpty)
                                      Text(clientName, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                                    if (branchName != null) ...[
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(color: branchColor, shape: BoxShape.circle),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            branchName,
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: branchColor),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    StatusChip(status: (map['status'] ?? '').toString()),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(money.format(amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Pend. ${money.format(pendiente)}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}
