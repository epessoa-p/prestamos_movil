import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

class ClientDetailController extends ChangeNotifier {
  ClientDetailController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool loading = false;
  String? error;
  Map<String, dynamic>? client;
  List<dynamic> loans = <dynamic>[];
  List<dynamic> purchases = <dynamic>[];
  List<dynamic> sales = <dynamic>[];

  /// Etiquetas de la empresa para el selector ({id, name, color}) y si el usuario puede asignarlas.
  List<Map<String, dynamic>> tagOptions = [];
  bool canTag = false;
  bool savingTag = false;

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<dynamic> _pickList(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final candidate = source[key];
      if (candidate is List) return candidate;
    }
    return <dynamic>[];
  }

  Future<void> load(int clientId) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final data = await _api.clientDetail(clientId);
      final payload = _asMap(data['data']).isNotEmpty ? _asMap(data['data']) : data;

      client = _asMap(payload['client']).isNotEmpty ? _asMap(payload['client']) : payload;
      tagOptions = ((payload['tag_options'] as List?) ?? const []).map(_asMap).toList();
      canTag = payload['can_tag'] == true;

      loans = _pickList(payload, ['loans', 'latest_loans', 'recent_loans', 'last_loans']);
      purchases = _pickList(payload, ['purchases', 'latest_purchases', 'recent_purchases', 'last_purchases']);
      sales = _pickList(payload, ['sales', 'latest_sales', 'recent_sales', 'last_sales']);

      // Fallback: try inside the client object if top-level arrays are empty
      if (loans.isEmpty && client != null) {
        loans = _pickList(client!, ['loans', 'latest_loans', 'recent_loans', 'last_loans']);
      }
      if (purchases.isEmpty && client != null) {
        purchases = _pickList(client!, ['purchases', 'latest_purchases', 'recent_purchases', 'last_purchases']);
      }
      if (sales.isEmpty && client != null) {
        sales = _pickList(client!, ['sales', 'latest_sales', 'recent_sales', 'last_sales']);
      }
    } catch (e, st) {
      error = 'No se pudo cargar detalle de cliente';
      await _logger.logError(module: 'client_detail', error: e, stackTrace: st, endpoint: '/clients/$clientId');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Asigna o quita (tag null) la etiqueta. Devuelve el mensaje para mostrar.
  Future<({bool ok, String message})> updateTag(int clientId, String? tag) async {
    savingTag = true;
    notifyListeners();
    try {
      final data = await _api.updateClientTag(clientId: clientId, tag: tag);
      client = {...?client, 'tag': data['tag'], 'tag_color': data['tag_color']};
      return (ok: true, message: data['message']?.toString() ?? 'Etiqueta actualizada.');
    } on DioException catch (e, st) {
      final body = _asMap(e.response?.data);
      final errors = _asMap(body['errors']);
      final first = errors.values.isNotEmpty ? errors.values.first : null;
      final message = first is List && first.isNotEmpty
          ? first.first.toString()
          : body['message']?.toString() ?? 'No se pudo cambiar la etiqueta.';
      if (e.response == null || (e.response!.statusCode ?? 0) >= 500) {
        await _logger.logError(module: 'client_tag', error: e, stackTrace: st, endpoint: '/clients/$clientId/tag');
      }
      return (ok: false, message: message);
    } catch (e, st) {
      await _logger.logError(module: 'client_tag', error: e, stackTrace: st, endpoint: '/clients/$clientId/tag');
      return (ok: false, message: 'No se pudo cambiar la etiqueta.');
    } finally {
      savingTag = false;
      notifyListeners();
    }
  }
}
