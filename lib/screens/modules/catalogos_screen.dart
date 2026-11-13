import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/session_controller.dart';
import '../../controllers/catalogs_controller.dart';
import '../../services/api_service.dart';
import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/color_utils.dart';
import '../catalogs/catalog_detail_screen.dart';
import '../catalogs/catalog_form_screen.dart';

class CatalogosScreen extends StatefulWidget {
  const CatalogosScreen({super.key, required this.api, required this.logger, required this.session});

  final ApiService api;
  final ErrorLogService logger;
  final SessionController session;

  @override
  State<CatalogosScreen> createState() => _CatalogosScreenState();
}

class _CatalogosScreenState extends State<CatalogosScreen> {
  late final CatalogsController _controller;
  final _searchCtrl = TextEditingController();

  bool get _canCreate => widget.session.permissions.contains('catalogs.create');

  @override
  void initState() {
    super.initState();
    _controller = CatalogsController(api: widget.api, logger: widget.logger);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() => _controller.load(query: _searchCtrl.text.trim());

  Future<void> _openDetail(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CatalogDetailScreen(api: widget.api, logger: widget.logger, catalogId: id),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _newCatalog() async {
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => CatalogFormScreen(api: widget.api, logger: widget.logger)),
    );
    if (id == null || !mounted) return;
    _reload();
    _openDetail(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogos'), backgroundColor: AppPalette.deepBlue, foregroundColor: Colors.white),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: _newCatalog,
              backgroundColor: AppPalette.deepBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo catálogo'),
            )
          : null,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _reload(),
                  decoration: InputDecoration(
                    hintText: 'Buscar catálogo...',
                    suffixIcon: IconButton(icon: const Icon(Icons.search_rounded), onPressed: _reload),
                  ),
                ),
                const SizedBox(height: 12),
                if (_controller.loading)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                else if (_controller.error != null)
                  Padding(padding: const EdgeInsets.all(24), child: Text(_controller.error!))
                else if (_controller.catalogs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _canCreate
                          ? 'Todavía no hay catálogos. Crea uno con "Nuevo catálogo" para compartir tus productos.'
                          : 'No hay catálogos para mostrar.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._controller.catalogs.whereType<Map>().map((c) => _catalogCard(Map<String, dynamic>.from(c))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _catalogCard(Map<String, dynamic> c) {
    final id = int.tryParse('${c['id']}');
    final color = parseHexColor('${c['cover_color'] ?? ''}') ?? AppPalette.deepBlue;
    final expires = DateTime.tryParse('${c['expires_at'] ?? ''}');
    final branch = c['branch'] is Map ? '${(c['branch'] as Map)['name']}' : 'Todas las sucursales';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: id == null ? null : () => _openDetail(id),
        child: Row(
          children: [
            Container(width: 6, height: 76, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c['title'] ?? 'Catálogo'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${c['items_count'] ?? 0} productos',
                        branch,
                        if (expires != null) 'vence ${DateFormat('dd/MM/yyyy').format(expires.toLocal())}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.only(right: 12), child: CatalogStatusChip(status: '${c['status'] ?? ''}')),
          ],
        ),
      ),
    );
  }
}

/// Estado del enlace: activo, pausado o vencido.
class CatalogStatusChip extends StatelessWidget {
  const CatalogStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' => ('Activo', const Color(0xFF198754)),
      'paused' => ('Pausado', const Color(0xFF6C757D)),
      'expired' => ('Vencido', const Color(0xFFDC3545)),
      _ => ('—', const Color(0xFF6C757D)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
