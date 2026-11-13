import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

class CreateLoanController extends ChangeNotifier {
  CreateLoanController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool categoriesLoading = false;
  String? categoriesError;
  List<dynamic> categories = [];

  bool clientSearchLoading = false;
  List<dynamic> clientResults = [];

  bool submitting = false;
  String? submitError;
  String? cashError;
  String? submitCode;
  Map<String, String> validationErrors = {};

  // Id del intento de registro: se reutiliza en los reintentos (si el primero llegó al
  // servidor, no se crea un préstamo duplicado) y se renueva al registrar con éxito.
  String _requestId = _newRequestId();

  static String _newRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

  Future<void> loadCategories() async {
    categoriesLoading = true;
    categoriesError = null;
    notifyListeners();
    try {
      final data = await _api.loanCategories();
      final raw = data['data'] ?? data['categories'] ?? data;
      categories = raw is List ? raw : [];
    } catch (e, st) {
      categoriesError = 'No se pudieron cargar las categorías';
      await _logger.logError(module: 'loan_categories', error: e, stackTrace: st, endpoint: '/loans/categories');
    } finally {
      categoriesLoading = false;
      notifyListeners();
    }
  }

  Map<String, dynamic>? categoryById(int categoryId) {
    for (final cat in categories) {
      final map = _asMap(cat);
      if ((map['id'] as num?)?.toInt() == categoryId) return map;
    }
    return null;
  }

  Map<String, dynamic>? ruleForCategory(int categoryId) {
    final cat = categoryById(categoryId);
    if (cat == null) return null;
    final rules = cat['rules'];
    if (rules is List && rules.isNotEmpty) return _asMap(rules.first);
    return null;
  }

  Future<void> searchClients(String query) async {
    if (query.trim().isEmpty) {
      clientResults = [];
      notifyListeners();
      return;
    }
    clientSearchLoading = true;
    notifyListeners();
    try {
      // Igual que la web: solo se puede prestar a clientes activos.
      final data = await _api.clients(query: query.trim(), perPage: 10, active: true);
      final raw = data['data'];
      clientResults = raw is List ? raw : [];
    } catch (_) {
      clientResults = [];
    } finally {
      clientSearchLoading = false;
      notifyListeners();
    }
  }

  Future<bool> submitLoan({
    required int clientId,
    required int creditCategoryId,
    required double amount,
    int? interestRate,
    String? startDate,
    double? productPrice,
    String? productDetails,
    String? productName,
    String? productBrand,
    int? productModelYear,
    String? productPlate,
    String? productChassis,
    String? productItemType,
    String? productKarat,
    String? productMaterialType,
    String? productSerialNumber,
    String? productItemModel,
    List<String> imagePaths = const [],
  }) async {
    submitting = true;
    submitError = null;
    cashError = null;
    submitCode = null;
    validationErrors = {};
    notifyListeners();

    try {
      final response = await _api.createLoan(
        clientId: clientId,
        creditCategoryId: creditCategoryId,
        amount: amount,
        interestRate: interestRate,
        startDate: startDate,
        productPrice: productPrice,
        productDetails: productDetails,
        productName: productName,
        productBrand: productBrand,
        productModelYear: productModelYear,
        productPlate: productPlate,
        productChassis: productChassis,
        productItemType: productItemType,
        productKarat: productKarat,
        productMaterialType: productMaterialType,
        productSerialNumber: productSerialNumber,
        productItemModel: productItemModel,
        imagePaths: imagePaths,
        requestId: _requestId,
      );

      final loan = response['loan'];
      submitCode = (loan is Map ? loan['code'] : null)?.toString() ?? 'Préstamo registrado';
      _requestId = _newRequestId();
      return true;
    } on DioException catch (e, st) {
      final data = _asMap(e.response?.data);
      final message = data['message']?.toString();

      if (e.response?.statusCode == 409 && data['code'] == 'duplicate_request') {
        submitError = message ?? 'Este préstamo ya fue enviado. Revisa la lista de préstamos.';
      } else if (e.response?.statusCode == 409) {
        cashError = message ?? 'No hay una caja abierta asignada. Apertura una caja antes de registrar préstamos.';
      } else if (e.response?.statusCode == 422 && _asMap(data['errors']).isEmpty) {
        // Regla de negocio sin campo (ej. cliente inactivo): mostrar el mensaje tal cual.
        submitError = message ?? 'Hay datos inválidos en el formulario';
      } else if (e.response?.statusCode == 422) {
        final errors = _asMap(data['errors']);
        final parsed = <String, String>{};
        for (final entry in errors.entries) {
          final raw = entry.value is List && (entry.value as List).isNotEmpty
              ? (entry.value as List).first.toString()
              : entry.value.toString();
          parsed[entry.key] = _translateValidationMessage(entry.key, raw);
        }
        validationErrors = parsed;
        // Un solo error: se muestra completo (ej. "supera el saldo disponible en caja").
        submitError = parsed.length == 1 ? parsed.values.first : _buildValidationSummary(parsed);
      } else if (e.response?.statusCode == 403) {
        submitError = message ?? 'No tienes permisos para registrar préstamos';
      } else if (e.response?.statusCode == 401) {
        submitError = 'Tu sesión expiró. Inicia sesión nuevamente';
      } else {
        submitError = message ?? 'No fue posible registrar el préstamo';
      }

      await _logger.logError(
        module: 'create_loan',
        error: e,
        stackTrace: st,
        endpoint: '/loans',
      );
      return false;
    } catch (e, st) {
      submitError = 'No fue posible registrar el préstamo';
      await _logger.logError(module: 'create_loan', error: e, stackTrace: st, endpoint: '/loans');
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  void clearClientResults() {
    clientResults = [];
    notifyListeners();
  }

  void clearState() {
    _requestId = _newRequestId();
    submitError = null;
    cashError = null;
    submitCode = null;
    validationErrors = {};
    clientResults = [];
    notifyListeners();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  static const _fieldNames = <String, String>{
    'client_id': 'Cliente',
    'credit_category_id': 'Categoría',
    'amount': 'Monto',
    'interest_rate': 'Tasa de interés',
    'start_date': 'Fecha de inicio',
    'product_price': 'Precio del producto',
    'product_details': 'Detalles del producto',
    'product_name': 'Nombre del producto',
    'product_brand': 'Marca',
    'product_model_year': 'Año del modelo',
    'product_plate': 'Placa',
    'product_chassis': 'Chasis',
    'product_item_type': 'Tipo de joya',
    'product_karat': 'Kilates',
    'product_material_type': 'Material',
    'product_serial_number': 'Número de serie',
    'product_item_model': 'Modelo del artículo',
    'images': 'Imágenes',
    'images[]': 'Imágenes',
  };

  static String _labelForField(String field) {
    if (RegExp(r'^images(\[\])?(\.\d+)?$').hasMatch(field)) return 'Imágenes';
    return _fieldNames[field] ?? field;
  }

  static String _translateValidationMessage(String field, String raw) {
    if (!raw.startsWith('validation.')) return raw;
    final key = raw.split(' ').first;
    final fieldLabel = _labelForField(field);
    const translations = <String, String>{
      'validation.required': 'es obligatorio',
      'validation.numeric': 'debe ser un número',
      'validation.integer': 'debe ser un número entero',
      'validation.string': 'debe ser texto',
      'validation.min': 'es demasiado pequeño',
      'validation.max': 'supera el máximo permitido',
      'validation.between': 'está fuera del rango permitido',
      'validation.exists': 'no existe en el sistema',
      'validation.in': 'el valor seleccionado no es válido',
      'validation.date': 'no es una fecha válida',
      'validation.date_format': 'no tiene el formato de fecha correcto',
      'validation.image': 'debe ser una imagen válida',
      'validation.mimes': 'el tipo de archivo no está permitido',
      'validation.max.file': 'el archivo supera el tamaño máximo',
      'validation.gt': 'debe ser mayor que cero',
    };
    final msg = translations[key] ?? raw;
    return '$fieldLabel $msg';
  }

  static String _buildValidationSummary(Map<String, String> errors) {
    if (errors.isEmpty) return 'Hay datos inválidos en el formulario';
    final fields = errors.keys.map(_labelForField).toSet().toList();
    if (fields.length == 1) return 'Corrige el campo: ${fields.first}';
    if (fields.length <= 3) return 'Corrige los campos: ${fields.join(', ')}';
    return 'Corrige ${fields.length} campos con errores: ${fields.take(2).join(', ')} y ${fields.length - 2} más';
  }
}
