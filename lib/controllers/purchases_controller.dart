import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

class PurchasesController extends ChangeNotifier {
  PurchasesController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool loading = false;
  String? error;
  List<dynamic> purchases = <dynamic>[];

  Future<void> load({String? query}) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final data = await _api.purchases(query: query);
      purchases = (data['data'] as List?) ?? <dynamic>[];
    } catch (e, st) {
      error = 'No se pudo cargar compras';
      await _logger.logError(module: 'purchases', error: e, stackTrace: st, endpoint: '/purchases');
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
