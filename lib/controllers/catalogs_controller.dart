import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

class CatalogsController extends ChangeNotifier {
  CatalogsController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool loading = false;
  String? error;
  List<dynamic> catalogs = <dynamic>[];

  Future<void> load({String? query}) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final data = await _api.catalogs(query: query);
      catalogs = (data['data'] as List?) ?? <dynamic>[];
    } catch (e, st) {
      error = 'No se pudo cargar catalogos';
      await _logger.logError(module: 'catalogs', error: e, stackTrace: st, endpoint: '/catalogs');
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
