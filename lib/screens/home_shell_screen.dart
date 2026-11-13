import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_config.dart';
import '../app/session_controller.dart';
import '../controllers/clients_controller.dart';
import '../controllers/dashboard_controller.dart';
import '../controllers/inventory_controller.dart';
import '../services/api_service.dart';
import '../services/error_log_service.dart';
import '../theme/app_theme.dart';
import 'cash/cash_session_sheet.dart';
import 'modules/catalogos_screen.dart';
import 'modules/compras_screen.dart';
import 'modules/pagos_screen.dart';
import 'modules/prestamos_screen.dart';
import 'modules/ventas_screen.dart';
import 'profile/profile_dialog.dart';
import 'tabs/clientes_tab.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/inventario_tab.dart';
import 'tabs/movimientos_tab.dart';
import 'widgets/common_widgets.dart';
import '../utils/currency.dart';
import 'company_picker_screen.dart';
import 'reports/reports_screen.dart';
import 'widgets/brand_logo.dart';

class HomeShellScreen extends StatefulWidget {
  const HomeShellScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends State<HomeShellScreen> with WidgetsBindingObserver {
  int _bottomIndex = 0;

  /// Claves de las pestañas visibles (en orden), para que el menú lateral pueda saltar a una.
  List<String> _tabKeys = const [];

  /// Cambia a la pestaña [key]. Devuelve false si el usuario no la tiene (no tiene permiso).
  bool _selectTab(String key) {
    final i = _tabKeys.indexOf(key);
    if (i < 0) return false;
    setState(() => _bottomIndex = i);
    return true;
  }
  late final ApiService _api;
  late final ErrorLogService _logger;

  late final DashboardController _dashboardController;
  late final ClientsController _clientsController;
  late final InventoryController _inventoryController;

  final _money = Currency.formatter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = ApiService(baseUrl: AppConfig.baseUrl);
    _api.setToken(widget.session.token);
    _logger = ErrorLogService();

    _dashboardController = DashboardController(api: _api, logger: _logger);
    _clientsController = ClientsController(api: _api, logger: _logger);
    _inventoryController = InventoryController(api: _api, logger: _logger);
    _loadAll();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowLicenseDialog());
  }

  /// Diálogo de "la versión de prueba vence pronto", como máximo una vez por día.
  Future<void> _maybeShowLicenseDialog() async {
    final session = widget.session;
    if (!session.licenseWarning || !mounted) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('license_warning_shown') == today) return;
      await prefs.setString('license_warning_shown', today);
    } catch (_) {
      // Sin preferencias se muestra igual.
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.schedule_rounded, color: Color(0xFFE76F51), size: 40),
        title: const Text('Versión de prueba'),
        content: Text(session.licenseMessage ?? 'La versión de prueba de la aplicación vence pronto.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.session.refreshProfile();
    }
  }

  Future<void> _loadAll() async {
    // Solo los módulos que el usuario puede ver (los demás responderían 403).
    final can = widget.session.permissions.contains;
    await Future.wait([
      _dashboardController.load(),
      if (can('clients.view')) _clientsController.load(),
      if (can('warehouses.view')) _inventoryController.load(),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dashboardController.dispose();
    _clientsController.dispose();
    _inventoryController.dispose();
    super.dispose();
  }

  void _openProfileDialog() {
    showDialog(
      context: context,
      builder: (_) => ProfileDialog(session: widget.session, logger: _logger),
    );
  }

  void _showCashSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CashSessionSheet(api: _api, logger: _logger, session: widget.session),
    );
  }

  @override
  Widget build(BuildContext context) {
    final can = widget.session.permissions.contains;
    // Cada pestaña solo si el usuario puede ver ese módulo (como el menú de la web).
    // Accesos rápidos: Inicio, Préstamos, Clientes e Inventario. Movimientos, Pagos y el resto están en el menú lateral.
    final tabs = <({String key, Widget page, NavigationDestination destination})>[
      (
        key: 'home',
        page: DashboardTab(controller: _dashboardController, money: _money, api: _api, logger: _logger),
        destination: const NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'Inicio'),
      ),
      if (can('loans.view'))
        (
          key: 'loans',
          page: PrestamosScreen(api: _api, logger: _logger, session: widget.session, embedded: true),
          destination: const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Préstamos',
          ),
        ),
      if (can('clients.view'))
        (
          key: 'clients',
          page: ClientesTab(
            controller: _clientsController,
            money: _money,
            api: _api,
            logger: _logger,
            session: widget.session,
          ),
          destination: const NavigationDestination(icon: Icon(Icons.people_rounded), label: 'Clientes'),
        ),
      if (can('warehouses.view'))
        (
          key: 'inventory',
          page: InventarioTab(
            controller: _inventoryController,
            api: _api,
            logger: _logger,
            canCreate: can('warehouses.create'),
          ),
          destination: const NavigationDestination(icon: Icon(Icons.inventory_2_rounded), label: 'Inventario'),
        ),
    ];
    _tabKeys = [for (final t in tabs) t.key];
    final index = _bottomIndex < tabs.length ? _bottomIndex : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SantaAna2'),
        backgroundColor: AppPalette.deepBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          // ── Botón caja ────────────────────────────────────────────────────
          AnimatedBuilder(
            animation: widget.session,
            builder: (context, _) {
              final isOpen = widget.session.isCashOpen;
              final loading = widget.session.loading;
              final tooltip = loading
                  ? 'Verificando caja...'
                  : isOpen
                  ? 'Caja abierta'
                  : 'Sin caja abierta';
              return Tooltip(
                message: tooltip,
                child: InkWell(
                  onTap: _showCashSheet,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(Icons.point_of_sale_rounded, color: loading ? Colors.white38 : Colors.white, size: 24),
                        if (!loading)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: isOpen ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppPalette.deepBlue, width: 1.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // ── Botón perfil ──────────────────────────────────────────────────
          IconButton(icon: const Icon(Icons.person_rounded), onPressed: _openProfileDialog, tooltip: 'Perfil'),
        ],
      ),
      drawer: _AppDrawer(
        api: _api,
        session: widget.session,
        logger: _logger,
        money: _money,
        onSelectTab: _selectTab,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEAF6FF), Color(0xFFFFF8EE)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Aviso de vencimiento de la versión de prueba (lo manda el servidor).
              AnimatedBuilder(
                animation: widget.session,
                builder: (context, _) => widget.session.licenseWarning
                    ? _LicenseBanner(message: widget.session.licenseMessage ?? '')
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: tabs[index].page),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => _bottomIndex = value),
              destinations: [for (final t in tabs) t.destination],
            ),
    );
  }
}

class _LicenseBanner extends StatelessWidget {
  const _LicenseBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFFFFE8D6),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 18, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7C2D12)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── App Drawer ────────────────────────────────────────────────────────────────

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.api,
    required this.session,
    required this.logger,
    required this.money,
    required this.onSelectTab,
  });

  final ApiService api;
  final SessionController session;
  final ErrorLogService logger;
  final NumberFormat money;

  /// Salta a una pestaña de la barra inferior ('home', 'loans', 'clients', 'inventory').
  final bool Function(String key) onSelectTab;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppPalette.deepBlue, AppPalette.aqua],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'SantaAna2',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  BrandLogo(size: 56),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (session.companies.length > 1)
              DrawerItem(
                icon: Icons.swap_horiz_rounded,
                label: 'Cambiar empresa',
                onTap: () {
                  Navigator.pop(context);
                  showCompanySwitcher(context, session);
                },
              ),
            DrawerItem(
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
              onTap: () {
                Navigator.pop(context);
                onSelectTab('home');
              },
            ),
            if (session.permissions.contains('loans.view'))
              DrawerItem(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Préstamos',
                onTap: () {
                  Navigator.pop(context);
                  onSelectTab('loans');
                },
              ),
            if (session.permissions.contains('payments.view'))
              DrawerItem(
                icon: Icons.payments_rounded,
                label: 'Pagos',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PagosScreen(api: api, logger: logger),
                    ),
                  );
                },
              ),
            if (session.permissions.contains('reports.view'))
              DrawerItem(
                icon: Icons.swap_horiz_rounded,
                label: 'Movimientos de caja',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Movimientos de caja'),
                          backgroundColor: AppPalette.deepBlue,
                          foregroundColor: Colors.white,
                        ),
                        backgroundColor: const Color(0xFFF3F7FB),
                        body: SafeArea(child: MovimientosTab(api: api, logger: logger, money: money)),
                      ),
                    ),
                  );
                },
              ),
            if (session.permissions.contains('warehouses.view'))
              DrawerItem(
                icon: Icons.inventory_2_rounded,
                label: 'Inventario',
                onTap: () {
                  Navigator.pop(context);
                  onSelectTab('inventory');
                },
              ),
            if (session.permissions.contains('purchases.view'))
              DrawerItem(
                icon: Icons.shopping_cart_rounded,
                label: 'Compras',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComprasScreen(api: api, logger: logger, session: session),
                    ),
                  );
                },
              ),
            if (session.permissions.contains('sales.view'))
              DrawerItem(
                icon: Icons.sell_rounded,
                label: 'Ventas',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VentasScreen(api: api, logger: logger, session: session),
                    ),
                  );
                },
              ),
            if (session.permissions.contains('reports.view'))
              DrawerItem(
                icon: Icons.bar_chart_rounded,
                label: 'Reportes',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReportesScreen(api: api, logger: logger, session: session)),
                  );
                },
              ),
            if (session.permissions.contains('catalogs.view'))
              DrawerItem(
                icon: Icons.category_rounded,
                label: 'Catálogos',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CatalogosScreen(api: api, logger: logger, session: session),
                    ),
                  );
                },
              ),
            DrawerItem(
              icon: Icons.menu_book_rounded,
              label: 'Manual de usuario',
              onTap: () async {
                Navigator.pop(context);
                // El manual es una página pública del sistema web: /ayuda (con descarga en PDF).
                final apiUri = Uri.parse(api.baseUrl);
                final url = Uri(
                  scheme: apiUri.scheme,
                  host: apiUri.host,
                  port: apiUri.hasPort ? apiUri.port : null,
                  path: '/ayuda',
                );
                final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No se pudo abrir el manual. Revisa que tengas un navegador instalado.'),
                    ),
                  );
                }
              },
            ),
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await session.logout();
                  if (context.mounted) Navigator.of(context).pop();
                },
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
