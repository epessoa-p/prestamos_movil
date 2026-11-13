import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

class SalesController extends ChangeNotifier {
  SalesController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool loading = false;
  String? error;
  List<dynamic> sales = <dynamic>[];

  Future<void> load({String? query}) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final data = await _api.sales(query: query);
      sales = (data['data'] as List?) ?? <dynamic>[];
    } catch (e, st) {
      error = 'No se pudo cargar ventas';
      await _logger.logError(module: 'sales', error: e, stackTrace: st, endpoint: '/sales');
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
