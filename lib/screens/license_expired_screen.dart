import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/session_controller.dart';
import 'widgets/brand_logo.dart';

/// Pantalla que bloquea la app cuando el servidor indica que venció el periodo de prueba.
/// "Reintentar" vuelve a consultar al servidor (por si se extendió el plazo).
class LicenseExpiredScreen extends StatelessWidget {
  const LicenseExpiredScreen({super.key, required this.session});

  final SessionController session;

  Future<void> _retry(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await session.retryLicense();
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('La aplicación sigue sin habilitar. Comuníquese con el proveedor.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expires = DateTime.tryParse(session.licenseExpiresAt ?? '');
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E5E9D), Color(0xFF19C5B6)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandLogo(size: 64),
                    const SizedBox(height: 18),
                    const Icon(Icons.lock_clock_rounded, size: 48, color: Color(0xFFE76F51)),
                    const SizedBox(height: 12),
                    const Text(
                      'Periodo de prueba terminado',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      session.licenseMessage ??
                          'El periodo de prueba de la aplicación terminó. Comuníquese con el proveedor del sistema.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF4E6070)),
                    ),
                    if (expires != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Venció el ${DateFormat('dd/MM/yyyy').format(expires)}.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'El sistema web sigue funcionando con normalidad.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF6A8299)),
                    ),
                    const SizedBox(height: 20),
                    AnimatedBuilder(
                      animation: session,
                      builder: (context, _) => SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: session.loading ? null : () => _retry(context),
                          icon: session.loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
