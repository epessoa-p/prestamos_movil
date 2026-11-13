import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

/// Caja del usuario: estado, apertura y cierre (GET /cash-session, POST /cash-session/open|close).
class CashSessionController extends ChangeNotifier {
  CashSessionController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool loading = false;
  bool saving = false;
  String? error;
  Map<String, dynamic> data = {};

  Map<String, dynamic>? get session => _map(data['session']);
  bool get isOpen => session != null;
  bool get canOperate => data['can_operate'] == true;
  bool get isManager => data['is_manager'] == true;
  String? get openError => data['open_error']?.toString();
  List<Map<String, dynamic>> get registers =>
      ((data['registers'] as List?) ?? const []).map((r) => _map(r) ?? {}).toList();
  List<Map<String, dynamic>> get denominations =>
      ((data['denominations'] as List?) ?? const []).map((r) => _map(r) ?? {}).toList();

  /// Gastos: permiso cash-registers.expense y caja abierta.
  bool get canRegisterExpense => data['can_register_expense'] == true;
  List<Map<String, dynamic>> get expenseCategories =>
      ((data['expense_categories'] as List?) ?? const []).map((r) => _map(r) ?? {}).toList();
  List<Map<String, dynamic>> get expensePersonals =>
      ((data['expense_personals'] as List?) ?? const []).map((r) => _map(r) ?? {}).toList();

  Future<({bool ok, String message})> registerExpense({
    required String category,
    int? personalId,
    required double amount,
    String? notes,
  }) =>
      _run('/cash-session/expense', () => _api.registerCashExpense(
            category: category,
            personalId: personalId,
            amount: amount,
            notes: notes,
            requestId: _requestId,
          ));

  // Un id por intento: si el envío se repite, el servidor no abre/cierra dos veces.
  String _requestId = _newRequestId();
  static String _newRequestId() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      data = await _api.cashSession();
    } catch (e, st) {
      error = 'No se pudo consultar la caja.';
      await _logger.logError(module: 'cash_session', error: e, stackTrace: st, endpoint: '/cash-session');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<({bool ok, String message})> open({required double amount, int? cashRegisterId, String? notes}) =>
      _run('/cash-session/open', () => _api.openCashSession(
            openingAmount: amount,
            cashRegisterId: cashRegisterId,
            notes: notes,
            requestId: _requestId,
          ));

  Future<({bool ok, String message})> close({double? amount, Map<String, int>? breakdown, String? notes}) =>
      _run('/cash-session/close', () => _api.closeCashSession(
            closingAmount: amount,
            breakdown: breakdown,
            notes: notes,
            requestId: _requestId,
          ));

  Future<({bool ok, String message})> _run(String endpoint, Future<Map<String, dynamic>> Function() call) async {
    if (saving) return (ok: false, message: 'Espera a que termine la operación en curso.');
    saving = true;
    notifyListeners();
    try {
      final result = await call();
      _requestId = _newRequestId();
      await load();
      return (ok: true, message: result['message']?.toString() ?? 'Listo.');
    } on DioException catch (e, st) {
      final body = _map(e.response?.data) ?? {};
      final errors = _map(body['errors']) ?? {};
      final first = errors.values.isNotEmpty ? errors.values.first : null;
      final message = first is List && first.isNotEmpty
          ? first.first.toString()
          : body['message']?.toString() ?? 'No se pudo completar la operación.';
      if (e.response == null || (e.response!.statusCode ?? 0) >= 500) {
        await _logger.logError(module: 'cash_session', error: e, stackTrace: st, endpoint: endpoint);
      }
      return (ok: false, message: message);
    } catch (e, st) {
      await _logger.logError(module: 'cash_session', error: e, stackTrace: st, endpoint: endpoint);
      return (ok: false, message: 'No se pudo completar la operación.');
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  static Map<String, dynamic>? _map(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }
}
