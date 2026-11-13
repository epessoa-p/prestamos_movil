import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

class ClientsController extends ChangeNotifier {
  ClientsController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool loading = false;
  String? error;
  List<dynamic> clients = <dynamic>[];

  /// Última búsqueda y filtro de categoría ('' = todas).
  String query = '';
  String rating = '';

  /// Cantidad de clientes por categoría para la búsqueda actual (incluye 'puntuales' y 'total').
  Map<String, int> ratingCounts = {};

  Future<void> load({String? query, String? rating}) async {
    if (query != null) this.query = query;
    if (rating != null) this.rating = rating;
    loading = true;
    error = null;
    notifyListeners();

    try {
      final data = await _api.clients(query: this.query, rating: this.rating, withRatingCounts: true);
      clients = (data['data'] as List?) ?? <dynamic>[];
      final counts = data['rating_counts'];
      ratingCounts = counts is Map
          ? counts.map((k, v) => MapEntry(k.toString(), v is int ? v : int.tryParse('$v') ?? 0))
          : {};
    } catch (e, st) {
      error = 'No se pudo cargar clientes';
      await _logger.logError(module: 'clients', error: e, stackTrace: st, endpoint: '/clients');
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
