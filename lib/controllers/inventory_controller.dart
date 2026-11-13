import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

class InventoryController extends ChangeNotifier {
  InventoryController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool loading = false;
  String? error;
  List<dynamic> inventory = <dynamic>[];

  bool optionsLoading = false;
  String? optionsError;
  List<dynamic> branches = <dynamic>[];
  List<dynamic> warehouses = <dynamic>[];
  List<dynamic> categories = <dynamic>[];
  List<dynamic> products = <dynamic>[];

  /// Personal que no es gerente: solo puede ingresar stock en esta sucursal.
  int? lockedBranchId;

  /// Código sugerido para un producto nuevo (siguiente PD- de la empresa; se puede cambiar).
  String? nextProductCode;

  bool submittingEntry = false;
  String? submitError;
  String? submitSuccess;
  Map<String, String> validationErrors = <String, String>{};

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return <dynamic>[];
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  void clearSubmitState() {
    submitError = null;
    submitSuccess = null;
    validationErrors = <String, String>{};
    notifyListeners();
  }

  /// Filtros de la lista: branch_id, warehouse_id, category_id e in_stock (por defecto solo con stock).
  Map<String, dynamic> filters = <String, dynamic>{'in_stock': 1};
  String _query = '';
  int page = 1;
  int lastPage = 1;
  int total = 0;
  bool loadingMore = false;

  /// Valor de lo filtrado: units, cost, sale, profit, for_sale{...}, pledged{...}, missing_price.
  Map<String, dynamic> totals = <String, dynamic>{};

  /// Carga la primera página (o la siguiente con [more]) con la búsqueda y los filtros actuales.
  Future<void> load({String? query, bool more = false}) async {
    if (query != null) _query = query;
    if (more) {
      loadingMore = true;
    } else {
      loading = true;
      error = null;
    }
    notifyListeners();

    try {
      final next = more ? page + 1 : 1;
      final data = await _api.inventory(query: _query, filters: filters, page: next);
      final rows = _asList(data['data']);
      inventory = more ? [...inventory, ...rows] : rows;
      totals = _asMap(data['totals']);
      page = int.tryParse('${data['current_page']}') ?? next;
      lastPage = int.tryParse('${data['last_page']}') ?? 1;
      total = int.tryParse('${data['total']}') ?? inventory.length;
    } catch (e, st) {
      error = 'No se pudo cargar inventario';
      await _logger.logError(module: 'inventory', error: e, stackTrace: st, endpoint: '/inventory/stock');
    } finally {
      loading = false;
      loadingMore = false;
      notifyListeners();
    }
  }

  void applyFilters(Map<String, dynamic> value) {
    filters = value;
    load();
  }

  /// Filtros elegidos por el usuario (sin contar "solo con stock", que está activo por defecto).
  int get activeFilterCount =>
      filters.entries.where((e) => e.key != 'in_stock' && e.value != null && '${e.value}'.isNotEmpty).length +
      (filters['in_stock'] == 1 ? 0 : 1);

  Future<void> loadOptions({String? query}) async {
    optionsLoading = true;
    optionsError = null;
    notifyListeners();

    try {
      final data = await _api.inventoryOptions(query: query);
      branches = _asList(data['branches']);
      warehouses = _asList(data['warehouses']);
      categories = _asList(data['categories']);
      products = _asList(data['products']);
      lockedBranchId = int.tryParse('${data['locked_branch_id'] ?? ''}');
      nextProductCode = data['next_product_code']?.toString();
    } catch (e, st) {
      optionsError = 'No se pudieron cargar opciones de inventario';
      await _logger.logError(module: 'inventory_options', error: e, stackTrace: st, endpoint: '/inventory/options');
    } finally {
      optionsLoading = false;
      notifyListeners();
    }
  }

  Future<bool> submitStockEntry({
    required int branchId,
    int? warehouseId,
    required String productMode,
    int? productId,
    int? creditCategoryId,
    String? productCode,
    String? productName,
    String? productBrand,
    String? productSerialNumber,
    String? productDescription,
    double? productCost,
    double? productPrice,
    String? productItemModel,
    String? productModelYear,
    String? productPlate,
    String? productChassis,
    String? productItemType,
    String? productKarat,
    String? productMaterialType,
    required double quantity,
    double? unitCost,
    String? reference,
    String? notes,
    required String movementDate,
    List<String> imagePaths = const <String>[],
  }) async {
    submittingEntry = true;
    submitError = null;
    submitSuccess = null;
    validationErrors = <String, String>{};
    notifyListeners();

    try {
      final response = await _api.createStockEntry(
        branchId: branchId,
        warehouseId: warehouseId,
        productMode: productMode,
        productId: productId,
        creditCategoryId: creditCategoryId,
        productCode: productCode,
        productName: productName,
        productBrand: productBrand,
        productSerialNumber: productSerialNumber,
        productDescription: productDescription,
        productCost: productCost,
        productPrice: productPrice,
        productItemModel: productItemModel,
        productModelYear: productModelYear,
        productPlate: productPlate,
        productChassis: productChassis,
        productItemType: productItemType,
        productKarat: productKarat,
        productMaterialType: productMaterialType,
        quantity: quantity,
        unitCost: unitCost,
        reference: reference,
        notes: notes,
        movementDate: movementDate,
        imagePaths: imagePaths,
      );

      submitSuccess = response['message']?.toString() ?? 'Ingreso de stock registrado correctamente';
      // Recarga la lista y las opciones (el código sugerido pasa al siguiente PD-).
      await Future.wait([load(), loadOptions()]);
      return true;
    } on DioException catch (e, st) {
      final data = _asMap(e.response?.data);
      final message = data['message']?.toString();

      if (e.response?.statusCode == 422) {
        final errors = _asMap(data['errors']);
        final parsed = <String, String>{};
        for (final entry in errors.entries) {
          final raw = entry.value is List && (entry.value as List).isNotEmpty
              ? (entry.value as List).first.toString()
              : entry.value.toString();
          parsed[entry.key] = _translateValidationMessage(entry.key, raw);
        }
        validationErrors = parsed;
        submitError = _buildValidationSummary(parsed);
      } else if (e.response?.statusCode == 403) {
        submitError = message ?? 'No tienes permisos para registrar ingresos de stock';
      } else if (e.response?.statusCode == 401) {
        submitError = 'Tu sesión expiró. Inicia sesión nuevamente';
      } else {
        submitError = message ?? 'No fue posible registrar el ingreso de stock';
      }

      await _logger.logError(
        module: 'inventory_stock_entry',
        error: e,
        stackTrace: st,
        endpoint: '/inventory/stock-entry',
      );
      return false;
    } catch (e, st) {
      submitError = 'No fue posible registrar el ingreso de stock';
      await _logger.logError(
        module: 'inventory_stock_entry',
        error: e,
        stackTrace: st,
        endpoint: '/inventory/stock-entry',
      );
      return false;
    } finally {
      submittingEntry = false;
      notifyListeners();
    }
  }

  // ── Nombre en español de cada campo del formulario ──────────────────────
  static const _fieldNames = <String, String>{
    'branch_id': 'Sucursal',
    'warehouse_id': 'Almacén',
    'product_mode': 'Modo de producto',
    'product_id': 'Producto',
    'credit_category_id': 'Categoría',
    'product_name': 'Nombre del producto',
    'product_code': 'Código del producto',
    'product_brand': 'Marca',
    'product_serial_number': 'Número de serie',
    'product_description': 'Descripción',
    'product_cost': 'Costo del producto',
    'product_price': 'Precio del producto',
    'product_item_model': 'Modelo del artículo',
    'product_model_year': 'Año del modelo',
    'product_plate': 'Placa',
    'product_chassis': 'Chasis',
    'product_item_type': 'Tipo de joya',
    'product_karat': 'Kilates',
    'product_material_type': 'Material',
    'quantity': 'Cantidad',
    'unit_cost': 'Costo unitario',
    'reference': 'Referencia',
    'notes': 'Notas',
    'movement_date': 'Fecha de movimiento',
    'images': 'Imágenes',
    'images[]': 'Imágenes',
  };

  // ── Traducción de claves de validación de Laravel ────────────────────────
  static String _translateValidationMessage(String field, String raw) {
    // Si el mensaje ya es legible (no empieza con "validation."), lo devuelve tal cual
    if (!raw.startsWith('validation.')) return raw;

    final key = raw.split(' ').first; // "validation.array (and 1 more error)" → "validation.array"
    final fieldLabel = _fieldNames[field] ?? field;

    const translations = <String, String>{
      'validation.required': 'es obligatorio',
      'validation.array': 'debe ser un arreglo válido',
      'validation.min': 'es demasiado pequeño',
      'validation.max': 'supera el máximo permitido',
      'validation.numeric': 'debe ser un número',
      'validation.integer': 'debe ser un número entero',
      'validation.string': 'debe ser texto',
      'validation.date': 'no es una fecha válida',
      'validation.date_format': 'no tiene el formato de fecha correcto',
      'validation.exists': 'no existe en el sistema',
      'validation.unique': 'ya está en uso',
      'validation.email': 'no es un correo electrónico válido',
      'validation.mimes': 'el tipo de archivo no está permitido',
      'validation.mimetypes': 'el tipo de archivo no está permitido',
      'validation.max.file': 'el archivo supera el tamaño máximo',
      'validation.image': 'debe ser una imagen válida',
      'validation.between': 'está fuera del rango permitido',
      'validation.in': 'el valor seleccionado no es válido',
      'validation.gt': 'debe ser mayor que cero',
      'validation.gte': 'debe ser mayor o igual a cero',
    };

    final msg = translations[key] ?? raw;
    return '$fieldLabel $msg';
  }

  // ── Resumen legible para el banner de error ──────────────────────────────
  static String _buildValidationSummary(Map<String, String> errors) {
    if (errors.isEmpty) return 'Hay datos inválidos en el formulario';

    // Agrupa campos únicos (images[] y images son el mismo)
    final fields = errors.keys
        .map((k) => _fieldNames[k] ?? k)
        .toSet()
        .toList();

    if (fields.length == 1) {
      // Un solo error: el mensaje del servidor ya dice qué falta (ej. "El serial es obligatorio para artículos.").
      final message = errors.values.first;
      return message.startsWith('validation.') ? 'Corrige el campo: ${fields.first}' : message;
    }
    if (fields.length <= 3) {
      return 'Corrige los campos: ${fields.join(', ')}';
    }
    return 'Corrige ${fields.length} campos con errores: ${fields.take(2).join(', ')} y ${fields.length - 2} más';
  }
}
