import 'package:flutter/material.dart';

import 'app_config.dart';
import '../screens/company_picker_screen.dart';
import '../screens/home_shell_screen.dart';
import '../screens/license_expired_screen.dart';
import '../screens/login_screen.dart';
import '../screens/widgets/brand_logo.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';
import 'session_controller.dart';

class PrestamosApp extends StatefulWidget {
  const PrestamosApp({super.key});

  @override
  State<PrestamosApp> createState() => _PrestamosAppState();
}

class _PrestamosAppState extends State<PrestamosApp> {
  late final SessionController _session;

  @override
  void initState() {
    super.initState();
    _session = SessionController(
      apiService: ApiService(baseUrl: AppConfig.baseUrl),
      storageService: SecureStorageService(),
    );
    _session.bootstrap();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SantaAna2',
          theme: AppTheme.light(),
          home: _session.initializing
              ? const _SplashScreen()
              : _session.appExpired
                  ? LicenseExpiredScreen(session: _session)
                  : !_session.isAuthenticated
                  ? LoginScreen(session: _session)
                  : _session.needsCompany
                      ? CompanyPickerScreen(session: _session)
                      // La clave por empresa rehace la pantalla (y recarga sus datos) al cambiar de empresa.
                      : HomeShellScreen(key: ValueKey('company-${_session.company?['id']}'), session: _session),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E5E9D), Color(0xFF19C5B6)],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BrandLogo(),
              SizedBox(height: 18),
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Preparando tu espacio financiero...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return const BrandLogo(size: 74);
  }
}
