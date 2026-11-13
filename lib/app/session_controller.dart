import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/secure_storage_service.dart';
import '../utils/currency.dart';

class SessionController extends ChangeNotifier {
  SessionController({required ApiService apiService, required SecureStorageService storageService})
      : _apiService = apiService,
        _storageService = storageService {
    ApiService.onAppExpired = _markExpired;
  }

  final ApiService _apiService;
  final SecureStorageService _storageService;

  bool _initializing = true;
  bool _loading = false;
  String? _error;
  String? _token;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _company;
  List<Map<String, dynamic>> _companies = [];
  List<String> _permissions = [];

  Map<String, dynamic>? _cashRegister;

  // Caducidad de la app (la decide el servidor: config api.mobile_expires_at).
  Map<String, dynamic> _license = {};
  bool _appExpired = false;

  /// El servidor rechazó la app porque venció el periodo de prueba.
  bool get appExpired => _appExpired;

  /// Faltan pocos días para el vencimiento (el servidor manda el aviso).
  bool get licenseWarning => !_appExpired && _license['warning'] == true;
  String? get licenseMessage => _license['message']?.toString();
  String? get licenseExpiresAt => _license['expires_at']?.toString();

  bool get initializing => _initializing;
  bool get loading => _loading;
  String? get error => _error;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get company => _company;

  /// Empresas que el usuario puede elegir (todas las activas si es super admin).
  List<Map<String, dynamic>> get companies => _companies;
  bool get isSuperAdmin => _user?['is_super_admin'] == true;

  /// Sin empresa elegida (el super admin no tiene una): la app pide elegirla antes de seguir.
  bool get needsCompany => isAuthenticated && _user != null && _company == null;
  List<String> get permissions => _permissions;
  Map<String, dynamic>? get cashRegister => _cashRegister;
  bool get isCashOpen => _cashRegister != null;

  Future<void> bootstrap() async {
    _setLoading(true);
    try {
      final token = await _storageService.readToken();
      if (token != null && token.isNotEmpty) {
        _token = token;
        _apiService.setToken(token);
        await refreshProfile();
        if (isAuthenticated) {
          await _setupPush();
        }
      }
    } catch (_) {
      await _storageService.clearToken();
      _token = null;
      _apiService.setToken(null);
    } finally {
      _initializing = false;
      _setLoading(false);
    }
  }

  Future<bool> login({
    required String login,
    required String password,
    int? companyId,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final data = await _apiService.login(
        login: login,
        password: password,
        companyId: companyId,
      );
      final token = (data['token'] ?? '').toString();
      if (token.isEmpty) {
        _error = 'No se recibió token de autenticación.';
        return false;
      }
      _token = token;
      _apiService.setToken(token);
      await _storageService.saveToken(token);

      _applyProfile(data);

      notifyListeners();
      await _setupPush();
      return true;
    } catch (e) {
      _error = _messageFromError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Vuelve a pedir usuario, empresa, permisos y caja. Devuelve false si no se pudo.
  ///
  /// Solo cierra la sesión si el servidor rechaza el token (401: token inválido o vencido,
  /// usuario o empresa inactivos). Ante un corte de red, timeout o error del servidor se
  /// conservan la sesión y los datos que ya había, y queda el mensaje en [error].
  Future<bool> refreshProfile() async {
    try {
      final data = await _apiService.me();
      _applyProfile(data);
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        _error = 'Tu sesión expiró. Inicia sesión nuevamente.';
        await logout(silent: true);
      } else {
        _error = _messageFromError(e);
        notifyListeners();
      }
      return false;
    }
  }

  /// Elige o cambia la empresa con la que se trabaja. Devuelve null si salió bien o el mensaje de error.
  Future<String?> selectCompany(int companyId) async {
    _setLoading(true);
    try {
      final data = await _apiService.selectCompany(companyId);
      _applyProfile(data);
      _error = null;
      notifyListeners();
      return null;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await logout(silent: true);
      }
      return _messageFromError(e);
    } finally {
      _setLoading(false);
    }
  }

  void _applyProfile(Map<String, dynamic> data) {
    _user = _toMap(data['user']);
    _company = _toMap(data['company']);
    Currency.setFromCompany(_company);
    _permissions = _toPermissions(data['permissions']);
    _cashRegister = _toMap(data['cash_register']);
    final companies = data['companies'];
    _companies = companies is List ? companies.whereType<Map>().map((c) => Map<String, dynamic>.from(c)).toList() : [];
    _license = _toMap(data['license']) ?? {};
    _appExpired = _license['expired'] == true;
  }

  void _markExpired(Map<String, dynamic> data) {
    _license = _toMap(data['license']) ?? {'expired': true, 'message': data['message']};
    if (_appExpired) return;
    _appExpired = true;
    notifyListeners();
  }

  /// Vuelve a consultar al servidor (por si extendieron el plazo). Devuelve true si la app ya funciona.
  Future<bool> retryLicense() async {
    _setLoading(true);
    try {
      final health = await _apiService.health();
      _license = _toMap(health['license']) ?? {};
      _appExpired = _license['expired'] == true;
      if (!_appExpired && isAuthenticated) await refreshProfile();
      return !_appExpired;
    } catch (_) {
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout({bool silent = false}) async {
    if (!silent) {
      try {
        await _apiService.logout();
      } catch (_) {}
    }
    await NotificationService.instance.deleteToken();
    _token = null;
    _apiService.setToken(null);
    _user = null;
    _company = null;
    _companies = [];
    Currency.setFromCompany(null);
    _permissions = [];
    _cashRegister = null;
    await _storageService.clearToken();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Inicializa las notificaciones push y registra el token FCM del dispositivo
  /// en el backend. No debe bloquear el flujo de sesión si algo falla.
  Future<void> _setupPush() async {
    try {
      final notifications = NotificationService.instance;
      notifications.onTokenRefresh = (token) {
        _apiService.registerDeviceToken(token).catchError((_) {});
      };
      await notifications.init();
      final token = await notifications.getToken();
      if (token != null && token.isNotEmpty) {
        await _apiService.registerDeviceToken(token);
      }
    } catch (_) {
      // El registro del token push es best-effort; no afecta la sesión.
    }
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  String _messageFromError(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final data = error.response?.data;
      if (statusCode == 401) {
        return 'Credenciales incorrectas o token inválido.';
      }
      if (statusCode == 403) {
        return data is Map && data['code'] == 'app_expired'
            ? data['message']?.toString() ?? 'El periodo de prueba de la aplicación terminó.'
            : 'No tienes permisos para esta operación.';
      }
      if (statusCode == 422) {
        final validationMessage = _extractValidationMessage(data);
        return validationMessage ?? 'Datos inválidos, revisa los campos.';
      }
      if (statusCode == 404) {
        return 'No se encontró el endpoint de la API. Revisa la URL base.';
      }
      if (statusCode == 500) {
        return 'El servidor presentó un error interno.';
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return 'No se pudo conectar con el servidor. Verifica Internet y la URL de API.';
      }
    }

    final text = error.toString();
    if (text.contains('401')) {
      return 'Sesión expirada. Inicia sesión nuevamente.';
    }
    if (text.contains('403')) {
      return 'No tienes permisos para esta operación.';
    }
    if (text.contains('422')) {
      return 'Datos inválidos, revisa los campos.';
    }
    return 'No se pudo completar la solicitud.';
  }

  String? _extractValidationMessage(dynamic data) {
    if (data is! Map) {
      return null;
    }

    final message = data['message']?.toString();
    if (message != null && message.isNotEmpty) {
      return message;
    }

    final errors = data['errors'];
    if (errors is Map) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) {
          return value.first.toString();
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  List<String> _toPermissions(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList(growable: false);
    }
    return [];
  }
}
