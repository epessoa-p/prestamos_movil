import 'package:flutter/material.dart';

import '../app/session_controller.dart';
import '../theme/app_theme.dart';
import 'widgets/brand_logo.dart';

/// Pantalla para elegir la empresa al ingresar cuando el usuario no tiene una (el super admin).
class CompanyPickerScreen extends StatelessWidget {
  const CompanyPickerScreen({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final name = session.user?['name']?.toString() ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          children: [
            const Center(child: BrandLogo(size: 72)),
            const SizedBox(height: 18),
            Text(
              name.isEmpty ? 'Elige una empresa' : 'Hola, $name',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppPalette.ink),
            ),
            const SizedBox(height: 6),
            const Text(
              'Elige la empresa con la que vas a trabajar. Puedes cambiarla después desde el menú.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6A8299)),
            ),
            const SizedBox(height: 20),
            CompanyList(session: session),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: session.loading ? null : () => session.logout(),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja para cambiar de empresa desde el menú lateral.
Future<void> showCompanySwitcher(BuildContext context, SessionController session) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Cambiar empresa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'Todo lo que veas y registres será de la empresa elegida.',
                style: TextStyle(color: Color(0xFF6A8299), fontSize: 13),
              ),
              const SizedBox(height: 14),
              CompanyList(session: session, onSelected: () => Navigator.of(ctx).pop()),
            ],
          ),
        ),
      ),
    ),
  );
}

class CompanyList extends StatefulWidget {
  const CompanyList({super.key, required this.session, this.onSelected});

  final SessionController session;
  final VoidCallback? onSelected;

  @override
  State<CompanyList> createState() => _CompanyListState();
}

class _CompanyListState extends State<CompanyList> {
  int? _selecting;
  String? _error;

  Future<void> _select(int id) async {
    if (_selecting != null) return; // evita doble toque
    if (id == _currentId) {
      widget.onSelected?.call();
      return;
    }
    setState(() {
      _selecting = id;
      _error = null;
    });
    final error = await widget.session.selectCompany(id);
    if (!mounted) return;
    setState(() {
      _selecting = null;
      _error = error;
    });
    if (error == null) widget.onSelected?.call();
  }

  int? get _currentId => int.tryParse('${widget.session.company?['id'] ?? ''}');

  @override
  Widget build(BuildContext context) {
    final companies = widget.session.companies;
    if (companies.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No hay empresas activas disponibles. Consulta con el administrador.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: const TextStyle(color: AppPalette.rose, fontWeight: FontWeight.w600)),
          ),
        ...companies.map((c) {
          final id = int.tryParse('${c['id']}');
          final current = id != null && id == _currentId;
          final ruc = '${c['ruc'] ?? ''}'.trim();
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: current ? AppPalette.deepBlue : const Color(0xFFE6EEF5), width: current ? 2 : 1),
            ),
            child: ListTile(
              onTap: id == null || _selecting != null ? null : () => _select(id),
              leading: CircleAvatar(
                backgroundColor: AppPalette.deepBlue.withValues(alpha: 0.1),
                child: const Icon(Icons.business_rounded, color: AppPalette.deepBlue),
              ),
              title: Text('${c['name'] ?? 'Empresa'}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                if (ruc.isNotEmpty) 'RUC/NIT: $ruc',
                'Moneda: ${c['currency_symbol'] ?? 'Bs'}',
              ].join(' · ')),
              trailing: _selecting == id
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : current
                      ? const Icon(Icons.check_circle_rounded, color: AppPalette.deepBlue)
                      : const Icon(Icons.chevron_right_rounded),
            ),
          );
        }),
      ],
    );
  }
}
