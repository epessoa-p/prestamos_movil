import 'package:flutter/material.dart';

import '../../app/session_controller.dart';
import '../../controllers/loans_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_utils.dart';
import '../loans/loan_detail_screen.dart';
import '../loans/new_loan_sheet.dart';
import '../widgets/common_widgets.dart';
import '../../utils/currency.dart';

class PrestamosScreen extends StatefulWidget {
  const PrestamosScreen({
    super.key,
    required this.api,
    required this.logger,
    required this.session,
    this.embedded = false,
  });

  final ApiService api;
  final ErrorLogService logger;
  final SessionController session;

  /// true cuando es una pestaña de la pantalla principal (sin barra superior propia).
  final bool embedded;

  @override
  State<PrestamosScreen> createState() => _PrestamosScreenState();
}

class _PrestamosScreenState extends State<PrestamosScreen> {
  late final LoansController _controller;
  final _money = Currency.formatter();
  int? _selectedBranchId;

  @override
  void initState() {
    super.initState();
    _controller = LoansController(api: widget.api, logger: widget.logger);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Color _hexColor(String? hex, {Color fallback = AppPalette.deepBlue}) {
    if (hex == null) return fallback;
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  List<Map<String, dynamic>> get _branches {
    final seen = <int>{};
    final result = <Map<String, dynamic>>[];
    for (final loan in _controller.loans) {
      final b = ((loan as Map).cast<String, dynamic>()['branch'] as Map?)?.cast<String, dynamic>();
      if (b == null) continue;
      final id = (b['id'] as num?)?.toInt();
      if (id != null && seen.add(id)) result.add(b);
    }
    return result;
  }

  List<dynamic> get _filteredLoans {
    if (_selectedBranchId == null) return _controller.loans;
    return _controller.loans.where((loan) {
      final b = ((loan as Map).cast<String, dynamic>()['branch'] as Map?)?.cast<String, dynamic>();
      return (b?['id'] as num?)?.toInt() == _selectedBranchId;
    }).toList();
  }

  // ── Loan card ──────────────────────────────────────────────────────────────

  Widget _amountCol(String label, double value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6A8299), fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(_money.format(value),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppPalette.ink),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );

  Widget _colDivider() => Container(width: 1, height: 28, color: const Color(0xFFE6EEF5), margin: const EdgeInsets.symmetric(horizontal: 6));

  Widget _buildLoanCard(Map<String, dynamic> map) {
    final amount    = asDouble(map['amount']);
    final capital   = asDouble(map['current_capital']);
    final unpaidInt = asDouble(map['unpaid_interest_total']);
    final pendiente = capital + unpaidInt;
    final loanId    = (map['id'] as num?)?.toInt() ?? 0;
    final branch    = (map['branch'] as Map?)?.cast<String, dynamic>();
    final branchName  = branch?['name']?.toString();
    final branchColor = _hexColor(branch?['color']?.toString());
    final clientName  = (map['client'] as Map?)?.cast<String, dynamic>()['name']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.hardEdge,
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        onTap: loanId > 0
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => LoanDetailScreen(api: widget.api, logger: widget.logger, loanId: loanId)))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(map['code']?.toString() ?? 'Préstamo #${map['id']}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppPalette.ink)),
                  const Spacer(),
                  StatusChip(status: map['status']?.toString() ?? 'unknown'),
                ],
              ),
              if (clientName.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(clientName, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
              ],
              if (branchName != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: branchColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(branchName,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: branchColor)),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                _amountCol('Monto', amount),
                _colDivider(),
                _amountCol('Capital actual', capital),
                _colDivider(),
                _amountCol('Pendiente', pendiente),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── Branch tabs ────────────────────────────────────────────────────────────

  Widget _buildBranchTabs(List<Map<String, dynamic>> branches) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                _BranchChip(
                  label: 'Todos',
                  color: AppPalette.deepBlue,
                  selected: _selectedBranchId == null,
                  onTap: () => setState(() => _selectedBranchId = null),
                ),
                ...branches.map((b) {
                  final id = (b['id'] as num?)?.toInt();
                  return _BranchChip(
                    label: b['name']?.toString() ?? '',
                    color: _hexColor(b['color']?.toString()),
                    selected: _selectedBranchId == id,
                    onTap: () => setState(() => _selectedBranchId = id),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  // ── New loan sheet ─────────────────────────────────────────────────────────

  Future<void> _openNewLoanSheet() async {
    final loanCode = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, _) => NewLoanSheet(
          api: widget.api,
          logger: widget.logger,
          permissions: widget.session.permissions,
          cashBranch: (widget.session.cashRegister?['branch'] as Map?)?.cast<String, dynamic>(),
        ),
      ),
    );

    if (!mounted) return;
    if (loanCode != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Préstamo $loanCode registrado exitosamente')),
      );
      _controller.load();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  Widget? _buildCashBanner() {
    if (widget.session.isCashOpen) return null;
    return const _CashBanner(
      icon: Icons.point_of_sale_rounded,
      color: Color(0xFFEF4444),
      message: 'No tienes una caja abierta. El registro de préstamos no está disponible.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = widget.session.permissions.contains('loans.create') && widget.session.isCashOpen;
    final cashBanner = _buildCashBanner();
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : const Color(0xFFF4F8FC),
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Préstamos'),
              backgroundColor: AppPalette.deepBlue,
              foregroundColor: Colors.white,
            ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _openNewLoanSheet,
              backgroundColor: AppPalette.deepBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo préstamo'),
            )
          : null,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.loading) return const Center(child: CircularProgressIndicator());

          final branches = _branches;
          final loans    = _filteredLoans;

          return Column(
            children: [
              if (widget.embedded) const AppHeader(title: 'Préstamos', subtitle: 'Préstamos por sucursal'),
              ?cashBanner,
              if (branches.isNotEmpty) _buildBranchTabs(branches),
              Expanded(
                child: loans.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_rounded, size: 44, color: Colors.grey.shade300),
                            const SizedBox(height: 10),
                            Text(
                              _selectedBranchId != null ? 'Sin préstamos en esta sucursal' : 'Sin préstamos',
                              style: const TextStyle(color: Color(0xFF6A8299)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                        itemCount: loans.length,
                        itemBuilder: (_, i) {
                          final map = (loans[i] as Map).cast<String, dynamic>();
                          return _buildLoanCard(map);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Branch chip widget ────────────────────────────────────────────────────────

class _BranchChip extends StatelessWidget {
  const _BranchChip({required this.label, required this.color, required this.selected, required this.onTap});

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? color : color.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!selected) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cash banner widget ────────────────────────────────────────────────────────

class _CashBanner extends StatelessWidget {
  const _CashBanner({required this.icon, required this.color, required this.message});

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
