import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_config.dart';
import '../app/session_controller.dart';
import '../theme/app_theme.dart';
import 'widgets/brand_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await widget.session.login(
      login: _loginCtrl.text.trim(),
      password: _passwordCtrl.text,
      companyId: 1,
    );

    if (!mounted) return;

    if (!ok && widget.session.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.session.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E2940), Color(0xFF1E5E9D), Color(0xFF19C5B6)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Card(
                  color: Colors.white.withValues(alpha: 0.94),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BrandLogo(size: 72),
                          const SizedBox(height: 14),
                          const Text(
                            'SantaAna2',
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppPalette.ink),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Gestiona tus prestamos, pagos y estados en tiempo real.',
                            style: TextStyle(fontSize: 15, color: Color(0xFF4E6070)),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _loginCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Correo o usuario',
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty) ? 'Ingresa tu usuario o correo' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Clave',
                              prefixIcon: Icon(Icons.lock_rounded),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty) ? 'Ingresa tu clave' : null,
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppPalette.deepBlue,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: widget.session.loading ? null : _submit,
                              child: widget.session.loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                    )
                                  : const Text('Iniciar sesion', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                          // Solo en desarrollo: a qué servidor apunta la app (en release no se muestra).
                          if (!kReleaseMode) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Servidor: ${AppConfig.baseUrl}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppConfig.isLocal ? const Color(0xFFD97706) : const Color(0xFF6A8299),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
