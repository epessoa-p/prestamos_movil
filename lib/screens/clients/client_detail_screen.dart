import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app/session_controller.dart';
import '../../controllers/client_detail_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_utils.dart';
import '../loans/new_loan_sheet.dart';
import 'new_client_sheet.dart';
import '../widgets/client_rating.dart';
import '../widgets/common_widgets.dart';
import '../../utils/currency.dart';

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({
    super.key,
    required this.api,
    required this.logger,
    required this.clientId,
    required this.session,
  });

  final ApiService api;
  final ErrorLogService logger;
  final int clientId;
  final SessionController session;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen>
    with SingleTickerProviderStateMixin {
  late final ClientDetailController _controller;
  late final TabController _tabController;
  final _money = Currency.formatter();

  int _int(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

  String _ratingSummary(Map<String, dynamic> r) {
    final loans = _int(r['loans_count']);
    final punctuality = r['punctuality'];
    return [
      if (punctuality != null) 'Puntualidad $punctuality%',
      '$loans préstamo${loans == 1 ? '' : 's'}',
    ].join(' · ');
  }

  /// Historial de pagos del cliente (como la tarjeta de la ficha web).
  void _showRatingDetail(Map<String, dynamic> r) {
    final rows = <(String, String)>[
      ('Puntualidad', r['punctuality'] == null ? 'Sin intereses pagados' : '${r['punctuality']}%'),
      ('Préstamos', '${_int(r['loans_count'])}'),
      ('Finalizados', '${_int(r['finished_count'])}'),
      ('Monto prestado', _money.format(asDouble(r['total_borrowed']))),
      ('Intereses pagados a tiempo', '${_int(r['on_time_interests'])}'),
      ('Intereses pagados con atraso', '${_int(r['late_interests'])}'),
      ('Préstamos con multa', '${_int(r['penalty_loans_count'])}'),
      ('En mora o incumplidos hoy', '${_int(r['risk_open_count'])}'),
      ('Incumplidos', '${_int(r['defaulted_count'])}'),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Historial de pagos',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.ink),
                    ),
                  ),
                  ClientRatingChip(rating: r),
                ],
              ),
              const SizedBox(height: 12),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6A8299))),
                      const Spacer(),
                      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.ink)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'La categoría se calcula con las reglas configuradas por la empresa en la web '
                '(Clientes → Categorías).',
                style: TextStyle(fontSize: 11, color: Color(0xFF8EA5BC)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEdit() async {
    final client = _controller.client;
    if (client == null) return;
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, _) => NewClientSheet(
          api: widget.api,
          logger: widget.logger,
          permissions: widget.session.permissions,
          initialClient: client,
        ),
      ),
    );
    if (!mounted || result?['updated'] != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cliente actualizado'), backgroundColor: Color(0xFF2A9D8F)),
    );
    _controller.load(widget.clientId);
  }

  /// Etiqueta actual y, con permiso "Etiquetar clientes", acceso al selector.
  Widget _buildTagRow(String tag, String? color) {
    if (_controller.savingTag) {
      return const SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 3));
    }
    final chip = tag.isNotEmpty ? ClientTagChip(name: tag, color: color) : null;
    if (!_controller.canTag) return chip ?? const SizedBox.shrink();

    return InkWell(
      onTap: _pickTag,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?chip,
          const SizedBox(width: 6),
          Icon(tag.isEmpty ? Icons.sell_outlined : Icons.edit_rounded, size: 15, color: AppPalette.deepBlue),
          if (tag.isEmpty) ...[
            const SizedBox(width: 4),
            const Text(
              'Etiquetar',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppPalette.deepBlue),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickTag() async {
    final current = _controller.client?['tag']?.toString() ?? '';
    final options = _controller.tagOptions;

    // '' = quitar la etiqueta; null = cancelado.
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Etiqueta del cliente',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.ink)),
              const SizedBox(height: 8),
              if (options.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'La empresa no tiene etiquetas. Se crean en la web: Clientes → Categorías.',
                    style: TextStyle(color: Color(0xFF6A8299)),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in options)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(radius: 8, backgroundColor: hexColor(t['color']?.toString())),
                        title: Text(t['name']?.toString() ?? ''),
                        trailing: t['name'] == current
                            ? const Icon(Icons.check_rounded, color: AppPalette.deepBlue)
                            : null,
                        onTap: () => Navigator.pop(ctx, t['name']?.toString() ?? ''),
                      ),
                    if (current.isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.close_rounded, color: AppPalette.rose),
                        title: const Text('Quitar etiqueta', style: TextStyle(color: AppPalette.rose)),
                        onTap: () => Navigator.pop(ctx, ''),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == current || !mounted) return;

    final result = await _controller.updateTag(widget.clientId, selected.isEmpty ? null : selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.message),
      backgroundColor: result.ok ? const Color(0xFF2A9D8F) : AppPalette.rose,
    ));
  }

  Future<void> _copyValue(String label, String value) async {
    if (value.trim().isEmpty || value == '-') return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado')),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6EEF5)),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppPalette.deepBlue, size: 20),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EEF5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppPalette.deepBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, color: AppPalette.ink, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  Widget _amountCol(String label, double value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6A8299), fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(
            _money.format(value),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppPalette.ink),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _colDivider() {
    return Container(width: 1, height: 28, color: const Color(0xFFE6EEF5), margin: const EdgeInsets.symmetric(horizontal: 6));
  }

  Widget _loanCard(Map<String, dynamic> map) {
    final amount      = asDouble(map['amount']);
    final capital     = asDouble(map['current_capital']);
    final unpaidInt   = asDouble(map['unpaid_interest_total']);
    final pendiente   = capital + unpaidInt;
    final totalPaid   = asDouble(map['total_paid']);
    final totalToPay  = asDouble(map['total_to_pay']);
    final progress    = totalToPay > 0 ? (totalPaid / totalToPay).clamp(0.0, 1.0) : 0.0;
    final status = map['status']?.toString() ?? '';
    final startDate = (map['start_date'] ?? map['created_at'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EEF5)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF0F7FF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.deepBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    map['code']?.toString() ?? '# ${map['id']}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
                if (startDate.isNotEmpty) ...
                  [
                    const SizedBox(width: 10),
                    const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF9DB1C3)),
                    const SizedBox(width: 4),
                    Text(_formatDate(startDate), style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299))),
                  ],
                const Spacer(),
                StatusChip(status: status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    _amountCol('Monto', amount),
                    _colDivider(),
                    _amountCol('Capital actual', capital),
                    _colDivider(),
                    _amountCol('Pendiente', pendiente),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFEEF2F6),
                    valueColor: AlwaysStoppedAnimation(
                      progress >= 1.0 ? const Color(0xFF2A9D8F) : AppPalette.deepBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(progress * 100).toStringAsFixed(0)}% pagado',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6A8299), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tradeCard({
    required String title,
    required IconData icon,
    required Color color,
    required Map<String, dynamic> map,
  }) {
    final dateRaw = (map['purchase_date'] ?? map['sale_date'] ?? map['created_at'] ?? '').toString();
    final dateLabel = dateRaw.isNotEmpty ? _formatDate(dateRaw) : '-';
    final status = map['status']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EEF5)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        map['code']?.toString() ?? '$title #${map['id']}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppPalette.ink),
                      ),
                      const Spacer(),
                      if (status.isNotEmpty) StatusChip(status: status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF9DB1C3)),
                      const SizedBox(width: 4),
                      Text(dateLabel, style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299))),
                      const Spacer(),
                      Text(
                        _money.format(asDouble(map['amount'])),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(IconData icon, String label, int count) {
    return Tab(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Text('$label  '),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppPalette.deepBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_rounded, size: 34, color: Color(0xFF9DB1C3)),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: Color(0xFF6A8299))),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = ClientDetailController(api: widget.api, logger: widget.logger);
    _controller.load(widget.clientId);
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() { if (!_tabController.indexIsChanging) setState(() {}); });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openNewLoanSheet() async {
    final client = _controller.client;
    if (client == null || !mounted) return;
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
          preselectedClient: client,
        ),
      ),
    );
    if (!mounted) return;
    if (loanCode != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Préstamo $loanCode registrado exitosamente')),
      );
      _controller.load(widget.clientId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreateLoan = widget.session.permissions.contains('loans.create') &&
        widget.session.isCashOpen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Cliente'),
        backgroundColor: AppPalette.deepBlue,
        foregroundColor: Colors.white,
        actions: [
          if (widget.session.permissions.contains('clients.edit'))
            AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => IconButton(
                tooltip: 'Editar cliente',
                icon: const Icon(Icons.edit_rounded),
                onPressed: _controller.client == null ? null : _openEdit,
              ),
            ),
        ],
      ),
      floatingActionButton: (_tabController.index == 0 && canCreateLoan)
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
          if (_controller.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_controller.client == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_search_rounded, size: 44, color: Color(0xFF9DB1C3)),
                    const SizedBox(height: 10),
                    Text(_controller.error ?? 'Cliente no encontrado'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _controller.load(widget.clientId),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          final client = _controller.client!;
          final phone = (client['phone'] ?? '').toString();
          final email = (client['email'] ?? '').toString();
          final address = (client['address'] ?? '').toString();
          final photoUrl = client['photo_url']?.toString();
          final rating = client['rating'] is Map ? (client['rating'] as Map).cast<String, dynamic>() : null;
          final tag = client['tag']?.toString() ?? '';
          final initial = (client['name']?.toString().isNotEmpty ?? false)
              ? client['name'].toString().substring(0, 1).toUpperCase()
              : 'C';

          return Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFEAF6FF), Color(0xFFFFF8EE)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          photoUrl != null && photoUrl.isNotEmpty
                              ? CircleAvatar(
                                  radius: 28,
                                  backgroundColor: AppPalette.deepBlue.withValues(alpha: 0.15),
                                  backgroundImage: NetworkImage(photoUrl),
                                  onBackgroundImageError: (_, _) {},
                                )
                              : CircleAvatar(
                                  radius: 28,
                                  backgroundColor: AppPalette.deepBlue,
                                  child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
                                ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  client['name']?.toString() ?? 'Sin nombre',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppPalette.ink),
                                ),
                                if (rating != null) ...[
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () => _showRatingDetail(rating),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        ClientRatingChip(rating: rating),
                                        Text(
                                          _ratingSummary(rating),
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                                        ),
                                        const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF8EA5BC)),
                                      ],
                                    ),
                                  ),
                                ],
                                if (tag.isNotEmpty || _controller.canTag) ...[
                                  const SizedBox(height: 6),
                                  _buildTagRow(tag, client['tag_color']?.toString()),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _infoChip(
                              icon: Icons.badge_rounded,
                              label: 'CI / RUC',
                              value: (client['id_number'] ?? '-').toString(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _infoChip(
                              icon: Icons.phone_rounded,
                              label: 'Teléfono',
                              value: (client['phone'] ?? '-').toString(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _infoChip(
                        icon: Icons.email_rounded,
                        label: 'Email',
                        value: (client['email'] ?? '-').toString(),
                      ),
                      const SizedBox(height: 10),
                      _infoChip(
                        icon: Icons.location_on_rounded,
                        label: 'Dirección',
                        value: (client['address'] ?? '-').toString(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _quickAction(
                            icon: Icons.phone_rounded,
                            label: 'Copiar teléfono',
                            onTap: () => _copyValue('Teléfono', phone),
                          ),
                          const SizedBox(width: 8),
                          _quickAction(
                            icon: Icons.email_rounded,
                            label: 'Copiar email',
                            onTap: () => _copyValue('Email', email),
                          ),
                          const SizedBox(width: 8),
                          _quickAction(
                            icon: Icons.copy_rounded,
                            label: 'Copiar dirección',
                            onTap: () => _copyValue('Dirección', address),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF4FB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppPalette.deepBlue,
                    unselectedLabelColor: const Color(0xFF8EA5BC),
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2)),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelPadding: EdgeInsets.zero,
                    tabs: [
                      _buildTab(Icons.account_balance_wallet_rounded, 'Préstamos', _controller.loans.length),
                      _buildTab(Icons.shopping_bag_rounded, 'Compras', _controller.purchases.length),
                      _buildTab(Icons.point_of_sale_rounded, 'Ventas', _controller.sales.length),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _controller.loans.isEmpty
                          ? _emptyState('Este cliente no tiene préstamos aún')
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                              itemCount: _controller.loans.length,
                              itemBuilder: (context, index) {
                                final map = (_controller.loans[index] as Map).cast<String, dynamic>();
                                return _loanCard(map);
                              },
                            ),
                      _controller.purchases.isEmpty
                          ? _emptyState('Este cliente no tiene compras registradas')
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                              itemCount: _controller.purchases.length,
                              itemBuilder: (context, index) {
                                final map = (_controller.purchases[index] as Map).cast<String, dynamic>();
                                return _tradeCard(
                                  title: 'Compra',
                                  icon: Icons.shopping_bag_rounded,
                                  color: const Color(0xFF6C47FF),
                                  map: map,
                                );
                              },
                            ),
                      _controller.sales.isEmpty
                          ? _emptyState('Este cliente no tiene ventas registradas')
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                              itemCount: _controller.sales.length,
                              itemBuilder: (context, index) {
                                final map = (_controller.sales[index] as Map).cast<String, dynamic>();
                                return _tradeCard(
                                  title: 'Venta',
                                  icon: Icons.point_of_sale_rounded,
                                  color: const Color(0xFF19C5B6),
                                  map: map,
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            );
        },
      ),
    );
  }
}
