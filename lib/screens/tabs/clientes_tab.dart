import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/session_controller.dart';
import '../../controllers/clients_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../clients/client_detail_screen.dart';
import '../clients/new_client_sheet.dart';
import '../loans/new_loan_sheet.dart';
import '../widgets/client_rating.dart';
import '../widgets/common_widgets.dart';

class ClientesTab extends StatefulWidget {
  const ClientesTab({
    super.key,
    required this.controller,
    required this.money,
    required this.api,
    required this.logger,
    required this.session,
  });

  final ClientsController controller;
  final NumberFormat money;
  final ApiService api;
  final ErrorLogService logger;
  final SessionController session;

  @override
  State<ClientesTab> createState() => _ClientesTabState();
}

class _ClientesTabState extends State<ClientesTab> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openNewClientSheet() async {
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
          isCashOpen: widget.session.isCashOpen,
        ),
      ),
    );
    if (!mounted || result == null) return;

    final client = result['client'] as Map<String, dynamic>?;
    final createLoan = result['createLoan'] == true;

    if (client != null) {
      widget.controller.load();
      if (createLoan) {
        await showModalBottomSheet<String?>(
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
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cliente ${client['name']} registrado')),
        );
      }
    }
  }

  /// Chips de categoría con su cantidad (como los de la lista web).
  Widget _buildRatingFilter() {
    final ctrl = widget.controller;
    final counts = ctrl.ratingCounts;
    final options = <(String, String, Color?)>[
      ('', 'Todos', null),
      ('puntuales', 'Puntuales', const Color(0xFF15803D)),
      for (final entry in clientRatingCategories.entries) (entry.key, entry.value.label, entry.value.color),
    ];

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        children: [
          for (final (key, label, color) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$label ${counts[key.isEmpty ? 'total' : key] ?? ''}'.trim()),
                selected: ctrl.rating == key,
                onSelected: ctrl.loading ? null : (_) => ctrl.load(rating: key),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ctrl.rating == key ? Colors.white : (color ?? AppPalette.ink),
                ),
                selectedColor: color ?? AppPalette.deepBlue,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = widget.session.permissions.contains('clients.create');
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Stack(
          children: [
            ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            const AppHeader(title: 'Clientes', subtitle: 'Gestiona clientes y sus transacciones'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchCtrl,
                onSubmitted: (query) => widget.controller.load(query: query.trim()),
                decoration: InputDecoration(
                  hintText: 'Buscar cliente...',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () => widget.controller.load(query: _searchCtrl.text.trim()),
                  ),
                ),
              ),
            ),
            _buildRatingFilter(),
            if (widget.controller.loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (widget.controller.error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(widget.controller.error!),
              )
            else if (widget.controller.clients.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hay clientes para mostrar.'),
              )
            else
              ...widget.controller.clients.map((client) {
                final map = (client as Map).cast<String, dynamic>();
                final rawId = map['id'];
                final clientId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
                final initial = (map['name']?.toString().isNotEmpty ?? false)
                    ? map['name'].toString().substring(0, 1).toUpperCase()
                    : 'C';
                final photoUrl = map['photo_url']?.toString();
                final rating = map['rating'] is Map ? (map['rating'] as Map).cast<String, dynamic>() : null;
                final contact = map['phone']?.toString() ?? map['email']?.toString() ?? 'Sin contacto';
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Card(
                    child: ListTile(
                      leading: photoUrl != null && photoUrl.isNotEmpty
                          ? CircleAvatar(
                              backgroundColor: AppPalette.deepBlue.withValues(alpha: 0.15),
                              backgroundImage: NetworkImage(photoUrl),
                              onBackgroundImageError: (_, _) {},
                            )
                          : CircleAvatar(
                              backgroundColor: AppPalette.deepBlue,
                              child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                      title: Text(map['name']?.toString() ?? 'Sin nombre'),
                      subtitle: rating == null
                          ? Text(contact)
                          : Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ClientRatingChip(rating: rating, showPunctuality: true),
                                  if ((map['tag']?.toString() ?? '').isNotEmpty)
                                    ClientTagChip(name: map['tag'].toString(), color: map['tag_color']?.toString()),
                                  Text(contact, style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      onTap: clientId == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ClientDetailScreen(
                                    api: widget.api,
                                    logger: widget.logger,
                                    clientId: clientId,
                                    session: widget.session,
                                  ),
                                ),
                              );
                            },
                    ),
                  ),
                );
              }),
          ],
        ),
            if (canCreate)
              Positioned(
                right: 16,
                bottom: 24,
                child: FloatingActionButton.extended(
                  onPressed: _openNewClientSheet,
                  backgroundColor: AppPalette.deepBlue,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('Nuevo cliente'),
                ),
              ),
          ],
        );
      },
    );
  }
}
