import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool loading = false;
  String? error;
  Map<String, dynamic>? dashboard;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      dashboard = await _api.dashboard();
    } catch (e, st) {
      error = 'No se pudo cargar dashboard';
      await _logger.logError(module: 'dashboard', error: e, stackTrace: st, endpoint: '/dashboard');
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
