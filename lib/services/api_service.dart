import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

class ApiService {
  ApiService({required this.baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'Accept': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        final data = error.response?.data;
        if (error.response?.statusCode == 403 && data is Map && data['code'] == 'app_expired') {
          onAppExpired?.call(Map<String, dynamic>.from(data));
        }
        handler.next(error);
      },
    ));
  }

  /// Se llama cuando el servidor responde que venció el periodo de prueba de la app
  /// (403 con code = app_expired). Es global porque cada pantalla crea su propio ApiService.
  static void Function(Map<String, dynamic> data)? onAppExpired;

  final String baseUrl;
  final Dio _dio;

  /// Estado de la API sin sesión (incluye `license`: vencimiento de la app).
  Future<Map<String, dynamic>> health() async {
    final response = await _dio.get('/health');
    return _asMap(response.data);
  }

  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Options _authOptions() {
    final headers = <String, dynamic>{'Accept': 'application/json'};
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return Options(headers: headers);
  }

  Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    int? companyId,
    String deviceName = 'flutter-app',
  }) async {
    final body = <String, dynamic>{
      'login': login,
      'password': password,
      'device_name': deviceName,
      ...companyId == null ? const <String, dynamic>{} : {'company_id': companyId},
    };

    final response = await _dio.post('/auth/login', data: body, options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get('/auth/me', options: _authOptions());
    return _asMap(response.data);
  }

  /// Elige o cambia la empresa del token. Devuelve el mismo perfil que [me].
  Future<Map<String, dynamic>> selectCompany(int companyId) async {
    final response = await _dio.post('/auth/company', data: {'company_id': companyId}, options: _authOptions());
    return _asMap(response.data);
  }

  Future<void> logout() async {
    await _dio.post('/auth/logout', options: _authOptions());
  }

  Future<void> registerDeviceToken(String fcmToken, {String platform = 'android'}) async {
    await _dio.post(
      '/auth/device-token',
      data: {'fcm_token': fcmToken, 'platform': platform},
      options: _authOptions(),
    );
  }

  Future<Map<String, dynamic>> dashboard() async {
    final response = await _dio.get('/dashboard', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> loans({
    String? status,
    String? query,
    int perPage = 20,
  }) async {
    final response = await _dio.get(
      '/loans',
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (query != null && query.isNotEmpty) 'q': query,
        'per_page': perPage,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Pagos de préstamos. [filters]: date_from, date_to, branch_id, payment_method, payment_type.
  /// La respuesta trae además `totals` {count, amount} de lo filtrado.
  Future<Map<String, dynamic>> payments({
    int? loanId,
    String? query,
    Map<String, dynamic> filters = const {},
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _dio.get(
      '/payments',
      queryParameters: {
        ...loanId == null ? const <String, dynamic>{} : {'loan_id': loanId},
        if (query != null && query.isNotEmpty) 'q': query,
        ..._cleanFilters(filters),
        'page': page,
        'per_page': perPage,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Sucursales (con color), métodos y tipos para los filtros de pagos.
  Future<Map<String, dynamic>> paymentOptions() async {
    final response = await _dio.get('/payments/options', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> paymentDetail(int paymentId) async {
    final response = await _dio.get('/payments/$paymentId', options: _authOptions());
    return _asMap(response.data);
  }

  /// Descarga el recibo del pago en PDF ([size]: ticket | carta) en [dir] y devuelve la ruta.
  Future<String> downloadPaymentReceipt(int paymentId, {required String size, required String dir}) =>
      _downloadFile(
        '/payments/$paymentId/receipt',
        query: {'size': size},
        dir: dir,
        fallbackName: 'recibo-$paymentId.pdf',
      );

  /// Elimina (auditado, restaurable) un periodo de interés no pagado.
  Future<Map<String, dynamic>> deleteInterest({required int loanId, required int interestId}) async {
    final response = await _dio.delete('/loans/$loanId/interest-payments/$interestId', options: _authOptions());
    return _asMap(response.data);
  }

  /// Restaura un periodo de interés eliminado.
  Future<Map<String, dynamic>> restoreInterest({required int loanId, required int interestId}) async {
    final response = await _dio.post('/loans/$loanId/interest-payments/$interestId/restore', options: _authOptions());
    return _asMap(response.data);
  }

  /// Cobros de un préstamo con la misma lógica que la web.
  /// [action]: 'interest-payments' | 'penalty-payment' | 'amortization' | 'liquidation'.
  /// [requestId] evita cobros duplicados si el envío se repite (el servidor responde 409).
  Future<Map<String, dynamic>> loanAction({
    required int loanId,
    required String action,
    required String requestId,
    double? amount,
    int? interestPaymentId,
    String? notes,
  }) async {
    final response = await _dio.post(
      '/loans/$loanId/$action',
      data: {
        'request_id': requestId,
        'payment_method': 'efectivo',
        'amount': ?amount,
        'interest_payment_id': ?interestPaymentId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// [rating]: fiel | puntual | regular | riesgo | nuevo | puntuales (fiel + puntual).
  /// [withRatingCounts] agrega `rating_counts` (cantidad por categoría) a la respuesta.
  Future<Map<String, dynamic>> clients({
    String? query,
    int perPage = 20,
    String? rating,
    bool withRatingCounts = false,
    bool? active,
  }) async {
    final response = await _dio.get(
      '/clients',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        'per_page': perPage,
        if (active != null) 'active': active ? 1 : 0,
        if (rating != null && rating.isNotEmpty) 'rating': rating,
        if (withRatingCounts) 'with_rating_counts': 1,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Catálogo de etiquetas de la empresa (`tags`) y si el usuario puede asignarlas (`can_tag`).
  Future<Map<String, dynamic>> clientTags() async {
    final response = await _dio.get('/clients/tags', options: _authOptions());
    return _asMap(response.data);
  }

  /// Asigna la etiqueta [tag] al cliente; null o vacío la quita.
  Future<Map<String, dynamic>> updateClientTag({required int clientId, String? tag}) async {
    final response = await _dio.patch(
      '/clients/$clientId/tag',
      data: {'tag': tag ?? ''},
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> loanDetail(int loanId) async {
    final response = await _dio.get('/loans/$loanId', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> clientDetail(int clientId) async {
    final response = await _dio.get('/clients/$clientId', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> purchases({String? query, int perPage = 20}) async {
    final response = await _dio.get(
      '/purchases',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        'per_page': perPage,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> purchaseDetail(int purchaseId) async {
    final response = await _dio.get('/purchases/$purchaseId', options: _authOptions());
    return _asMap(response.data);
  }

  /// Caja abierta (sucursal y saldo), categorías activas, kilatajes y materiales para "Nueva compra".
  Future<Map<String, dynamic>> purchaseOptions() async {
    final response = await _dio.get('/purchases/options', options: _authOptions());
    return _asMap(response.data);
  }

  /// Registra una compra. [fields] usa los nombres de la API (credit_category_id, product_*,
  /// client_id o client_name/client_id_number/client_phone, amount, notes). Las fotos van como images[].
  Future<Map<String, dynamic>> createPurchase({
    required Map<String, dynamic> fields,
    List<String> imagePaths = const [],
    required String requestId,
  }) async {
    final data = <String, dynamic>{
      for (final entry in fields.entries)
        if (entry.value != null && entry.value.toString().trim().isNotEmpty) entry.key: entry.value,
      'request_id': requestId,
    };

    if (imagePaths.isEmpty) {
      final response = await _dio.post('/purchases', data: data, options: _authOptions());
      return _asMap(response.data);
    }

    final form = FormData();
    data.forEach((k, v) => form.fields.add(MapEntry(k, v.toString().trim())));
    for (final p in imagePaths) {
      form.files.add(MapEntry('images[]', await MultipartFile.fromFile(p, filename: p.split(RegExp(r'[\\/]+')).last)));
    }
    final response = await _dio.post('/purchases', data: form, options: _authOptions());
    return _asMap(response.data);
  }

  /// Elimina una compra: lo pagado vuelve a la caja abierta y el producto sale del almacén.
  Future<Map<String, dynamic>> deletePurchase({required int purchaseId, required String requestId}) async {
    final response = await _dio.delete('/purchases/$purchaseId', data: {'request_id': requestId}, options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> saleDetail(int saleId) async {
    final response = await _dio.get('/sales/$saleId', options: _authOptions());
    return _asMap(response.data);
  }

  /// Caja abierta, sucursal y productos disponibles en su almacén para vender.
  Future<Map<String, dynamic>> saleOptions() async {
    final response = await _dio.get('/sales/options', options: _authOptions());
    return _asMap(response.data);
  }

  /// Registra una venta. [paymentType] CONTADO | CREDITO; en crédito [installments] = [{due_date, percentage, amount}].
  Future<Map<String, dynamic>> createSale({
    required int productId,
    required String paymentType,
    required double amount,
    int? clientId,
    String? clientName,
    String? clientIdNumber,
    String? clientPhone,
    double? creditAdditionalPercentage,
    double? downPayment,
    List<Map<String, dynamic>> installments = const [],
    String? notes,
    required String requestId,
  }) async {
    final response = await _dio.post(
      '/sales',
      data: {
        'product_id': productId,
        'payment_type': paymentType,
        'amount': amount,
        'client_id': ?clientId,
        if (clientId == null && clientName != null && clientName.isNotEmpty) 'client_name': clientName,
        if (clientId == null && clientIdNumber != null && clientIdNumber.isNotEmpty) 'client_id_number': clientIdNumber,
        if (clientId == null && clientPhone != null && clientPhone.isNotEmpty) 'client_phone': clientPhone,
        'credit_additional_percentage': ?creditAdditionalPercentage,
        'down_payment': ?downPayment,
        if (installments.isNotEmpty) 'installments': installments,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'request_id': requestId,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Acciones sobre una venta: pagar cuota, liquidar o devolver.
  Future<Map<String, dynamic>> paySaleInstallment({required int installmentId, String? notes, required String requestId}) async {
    final response = await _dio.post(
      '/sales/installments/$installmentId/pay',
      data: {if (notes != null && notes.isNotEmpty) 'payment_notes': notes, 'request_id': requestId},
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> liquidateSale({required int saleId, required String requestId}) async {
    final response = await _dio.post('/sales/$saleId/liquidate', data: {'request_id': requestId}, options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> returnSale({
    required int saleId,
    required String reason,
    String? notes,
    required String requestId,
  }) async {
    final response = await _dio.post(
      '/sales/$saleId/return',
      data: {
        'return_reason': reason,
        if (notes != null && notes.isNotEmpty) 'return_notes': notes,
        'request_id': requestId,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> sales({String? query, int perPage = 20}) async {
    final response = await _dio.get(
      '/sales',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        'per_page': perPage,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> movements({String? query, int perPage = 20}) async {
    final response = await _dio.get(
      '/movements',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        'per_page': perPage,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Stock por producto/almacén. [filters]: branch_id, warehouse_id, category_id, in_stock (1 = solo con stock).
  Future<Map<String, dynamic>> inventory({
    String? query,
    Map<String, dynamic> filters = const {},
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _dio.get(
      '/inventory/stock',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        ..._cleanFilters(filters),
        'page': page,
        'per_page': perPage,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> inventoryStockDetail(int productId) async {
    final response = await _dio.get('/inventory/stock/$productId', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> updateProductPrice(int productId, double price) async {
    final response = await _dio.patch(
      '/inventory/products/$productId/price',
      data: {'price': price},
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Fotos del producto (las de su préstamo, compra o ingreso). data: photos, can_edit, max_photos.
  Future<Map<String, dynamic>> productPhotos(int productId) async {
    final response = await _dio.get('/inventory/products/$productId/photos', options: _authOptions());
    return _asMap(response.data);
  }

  /// Agrega fotos al producto (se guardan en su préstamo, compra o ingreso). data: photos.
  Future<Map<String, dynamic>> addProductPhotos(int productId, List<String> imagePaths) async {
    final form = FormData();
    for (final p in imagePaths) {
      form.files.add(MapEntry('images[]', await MultipartFile.fromFile(p, filename: p.split(RegExp(r'[\\/]+')).last)));
    }
    final response = await _dio.post('/inventory/products/$productId/photos', data: form, options: _authOptions());
    return _asMap(response.data);
  }

  /// Elimina una foto del producto (también del préstamo, la compra o el ingreso). data: photos.
  Future<Map<String, dynamic>> deleteProductPhoto(int productId, String type, int photoId) async {
    final response = await _dio.delete('/inventory/products/$productId/photos/$type/$photoId', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> inventoryOptions({String? query, int productLimit = 100}) async {
    final response = await _dio.get(
      '/inventory/options',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        'product_limit': productLimit,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Ingreso de stock. Sin [warehouseId] el servidor usa el almacén de la sucursal.
  Future<Map<String, dynamic>> createStockEntry({
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
    // Artículos
    String? productItemModel,
    // Vehículos
    String? productModelYear,
    String? productPlate,
    String? productChassis,
    // Joyas
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
    final data = <String, dynamic>{
      'branch_id': branchId,
      'warehouse_id': ?warehouseId,
      'product_mode': productMode,
      'quantity': quantity,
      'movement_date': movementDate,
      if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };

    if (productMode == 'existing') {
      data['product_id'] = productId;
      if (unitCost != null) {
        data['unit_cost'] = unitCost;
      }
    } else {
      data['credit_category_id'] = creditCategoryId;
      // Vacío = el servidor usa el siguiente PD- sugerido.
      if (productCode != null && productCode.trim().isNotEmpty) {
        data['product_code'] = productCode.trim();
      }
      if (productName != null && productName.trim().isNotEmpty) {
        data['product_name'] = productName.trim();
      }
      if (productBrand != null && productBrand.trim().isNotEmpty) {
        data['product_brand'] = productBrand.trim();
      }
      if (productSerialNumber != null && productSerialNumber.trim().isNotEmpty) {
        data['product_serial_number'] = productSerialNumber.trim();
      }
      if (productDescription != null && productDescription.trim().isNotEmpty) {
        data['product_description'] = productDescription.trim();
      }
      if (productCost != null) {
        data['product_cost'] = productCost;
      }
      if (productPrice != null) {
        data['product_price'] = productPrice;
      }
      if (productItemModel != null && productItemModel.trim().isNotEmpty) {
        data['product_item_model'] = productItemModel.trim();
      }
      if (productModelYear != null && productModelYear.trim().isNotEmpty) {
        data['product_model_year'] = productModelYear.trim();
      }
      if (productPlate != null && productPlate.trim().isNotEmpty) {
        data['product_plate'] = productPlate.trim();
      }
      if (productChassis != null && productChassis.trim().isNotEmpty) {
        data['product_chassis'] = productChassis.trim();
      }
      if (productItemType != null && productItemType.trim().isNotEmpty) {
        data['product_item_type'] = productItemType.trim();
      }
      if (productKarat != null && productKarat.trim().isNotEmpty) {
        data['product_karat'] = productKarat.trim();
      }
      if (productMaterialType != null && productMaterialType.trim().isNotEmpty) {
        data['product_material_type'] = productMaterialType.trim();
      }
    }

    final hasImages = imagePaths.isNotEmpty;
    FormData? formPayload;
    if (hasImages) {
      final files = await Future.wait(
        imagePaths.map(
          (path) => MultipartFile.fromFile(
            path,
            filename: path.split(RegExp(r'[\\/]+')).last,
          ),
        ),
      );
      formPayload = FormData();
      data.forEach((key, value) => formPayload!.fields.add(MapEntry(key, value.toString())));
      for (final file in files) {
        formPayload.files.add(MapEntry('images[]', file));
      }
    }
    final payload = formPayload ?? data;

    final response = await _dio.post('/inventory/stock-entry', data: payload, options: _authOptions());
    return _asMap(response.data);
  }

  /// Estado de la caja del usuario: `session` (null si no hay abierta, con `summary`),
  /// `registers` que puede abrir, `open_error`, `is_manager`, `can_operate` y `denominations`.
  Future<Map<String, dynamic>> cashSession() async {
    final response = await _dio.get('/cash-session', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> openCashSession({
    required double openingAmount,
    int? cashRegisterId,
    String? notes,
    required String requestId,
  }) async {
    final response = await _dio.post(
      '/cash-session/open',
      data: {
        'opening_amount': openingAmount,
        'cash_register_id': ?cashRegisterId,
        if (notes != null && notes.isNotEmpty) 'opening_notes': notes,
        'request_id': requestId,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Gasto en la caja abierta: [category] service_expense | staff_payment | operating_expense.
  Future<Map<String, dynamic>> registerCashExpense({
    required String category,
    int? personalId,
    required double amount,
    String? notes,
    required String requestId,
  }) async {
    final response = await _dio.post(
      '/cash-session/expense',
      data: {
        'category': category,
        'personal_id': ?personalId,
        'amount': amount,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'request_id': requestId,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Cierra la caja con el monto contado o con el conteo por denominaciones ([breakdown]).
  Future<Map<String, dynamic>> closeCashSession({
    double? closingAmount,
    Map<String, int>? breakdown,
    String? notes,
    required String requestId,
  }) async {
    final response = await _dio.post(
      '/cash-session/close',
      data: {
        'closing_amount': ?closingAmount,
        if (breakdown != null && breakdown.values.any((q) => q > 0)) 'closing_breakdown': breakdown,
        if (notes != null && notes.isNotEmpty) 'closing_notes': notes,
        'request_id': requestId,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> loanCategories() async {
    final response = await _dio.get('/loans/categories', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> createLoan({
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
    String? requestId,
  }) async {
    final data = <String, dynamic>{
      'request_id': ?requestId,
      'client_id': clientId,
      'credit_category_id': creditCategoryId,
      'amount': amount,
      'interest_rate': ?interestRate,
      if (startDate != null && startDate.isNotEmpty) 'start_date': startDate,
      'product_price': ?productPrice,
      if (productDetails != null && productDetails.trim().isNotEmpty) 'product_details': productDetails.trim(),
      if (productName != null && productName.trim().isNotEmpty) 'product_name': productName.trim(),
      if (productBrand != null && productBrand.trim().isNotEmpty) 'product_brand': productBrand.trim(),
      'product_model_year': ?productModelYear,
      if (productPlate != null && productPlate.trim().isNotEmpty) 'product_plate': productPlate.trim(),
      if (productChassis != null && productChassis.trim().isNotEmpty) 'product_chassis': productChassis.trim(),
      if (productItemType != null && productItemType.trim().isNotEmpty) 'product_item_type': productItemType.trim(),
      if (productKarat != null && productKarat.trim().isNotEmpty) 'product_karat': productKarat.trim(),
      if (productMaterialType != null && productMaterialType.trim().isNotEmpty) 'product_material_type': productMaterialType.trim(),
      if (productSerialNumber != null && productSerialNumber.trim().isNotEmpty) 'product_serial_number': productSerialNumber.trim(),
      if (productItemModel != null && productItemModel.trim().isNotEmpty) 'product_item_model': productItemModel.trim(),
    };

    if (imagePaths.isNotEmpty) {
      final files = await Future.wait(
        imagePaths.map(
          (p) => MultipartFile.fromFile(p, filename: p.split(RegExp(r'[\\/]+')).last),
        ),
      );
      final form = FormData();
      data.forEach((k, v) => form.fields.add(MapEntry(k, v.toString())));
      for (final f in files) {
        form.files.add(MapEntry('images[]', f));
      }
      final response = await _dio.post('/loans', data: form, options: _authOptions());
      return _asMap(response.data);
    }

    final response = await _dio.post('/loans', data: data, options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> createClient({
    required String name,
    String? idNumber,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? locationUrl,
    String? photoPath,
    List<String> docPaths = const [],
    List<String> docLabels = const [],
    String? tag,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
      if (idNumber != null && idNumber.trim().isNotEmpty) 'id_number': idNumber.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (locationUrl != null && locationUrl.trim().isNotEmpty) 'location_url': locationUrl.trim(),
    };

    final needsMultipart = photoPath != null || docPaths.isNotEmpty;
    if (needsMultipart) {
      final form = FormData();
      data.forEach((k, v) => form.fields.add(MapEntry(k, v.toString())));
      if (photoPath != null) {
        form.files.add(MapEntry(
          'photo',
          await MultipartFile.fromFile(photoPath, filename: photoPath.split(RegExp(r'[\\/]+')).last),
        ));
      }
      for (int i = 0; i < docPaths.length; i++) {
        final path = docPaths[i];
        form.files.add(MapEntry(
          'doc_files[]',
          await MultipartFile.fromFile(path, filename: path.split(RegExp(r'[\\/]+')).last),
        ));
        final label = i < docLabels.length ? docLabels[i].trim() : '';
        form.fields.add(MapEntry('doc_labels[]', label));
      }
      final response = await _dio.post('/clients', data: form, options: _authOptions());
      return _asMap(response.data);
    }

    final response = await _dio.post('/clients', data: data, options: _authOptions());
    return _asMap(response.data);
  }

  /// Edita un cliente. Se envían todos los campos (vacío = se borra el dato).
  /// Va por POST + `_method=PUT` para poder adjuntar archivos (multipart).
  Future<Map<String, dynamic>> updateClient({
    required int clientId,
    required String name,
    String? idNumber,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? locationUrl,
    double? locationLat,
    double? locationLng,
    String? photoPath,
    bool removePhoto = false,
    List<String> docPaths = const [],
    List<String> docLabels = const [],
    String? tag,
  }) async {
    final form = FormData();
    final fields = <String, String>{
      '_method': 'PUT',
      'name': name,
      'id_number': idNumber?.trim() ?? '',
      'phone': phone?.trim() ?? '',
      'email': email?.trim() ?? '',
      'address': address?.trim() ?? '',
      'notes': notes?.trim() ?? '',
      'location_url': locationUrl?.trim() ?? '',
      'location_lat': locationLat?.toString() ?? '',
      'location_lng': locationLng?.toString() ?? '',
      // El servidor solo la aplica si el usuario tiene permiso clients.tag.
      'tag': tag ?? '',
      if (removePhoto) 'remove_photo': '1',
    };
    fields.forEach((k, v) => form.fields.add(MapEntry(k, v)));
    if (photoPath != null) {
      form.files.add(MapEntry(
        'photo',
        await MultipartFile.fromFile(photoPath, filename: photoPath.split(RegExp(r'[\\/]+')).last),
      ));
    }
    for (int i = 0; i < docPaths.length; i++) {
      final path = docPaths[i];
      form.files.add(MapEntry(
        'doc_files[]',
        await MultipartFile.fromFile(path, filename: path.split(RegExp(r'[\\/]+')).last),
      ));
      form.fields.add(MapEntry('doc_labels[]', i < docLabels.length ? docLabels[i].trim() : ''));
    }
    final response = await _dio.post('/clients/$clientId', data: form, options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> deleteClientDocument(int documentId) async {
    final response = await _dio.delete('/clients/documents/$documentId', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> catalogs({String? query, int perPage = 20}) async {
    final response = await _dio.get(
      '/catalogs',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        'per_page': perPage,
      },
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> catalogDetail(int catalogId) async {
    final response = await _dio.get('/catalogs/$catalogId', options: _authOptions());
    return _asMap(response.data);
  }

  /// Sucursales permitidas y productos disponibles para un catálogo (con [catalogId] incluye los que ya tiene).
  Future<Map<String, dynamic>> catalogOptions({int? catalogId}) async {
    final response = await _dio.get(
      '/catalogs/options',
      queryParameters: {'catalog_id': ?catalogId},
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Crea (sin [catalogId]) o edita un catálogo. Con [logoPath] se envía multipart (products va como JSON).
  Future<Map<String, dynamic>> saveCatalog(Map<String, dynamic> data, {int? catalogId, String? logoPath}) async {
    final path = catalogId == null ? '/catalogs' : '/catalogs/$catalogId';
    if (logoPath == null) {
      final response = catalogId == null
          ? await _dio.post(path, data: data, options: _authOptions())
          : await _dio.put(path, data: data, options: _authOptions());
      return _asMap(response.data);
    }
    final form = FormData.fromMap({
      for (final e in data.entries)
        if (e.key != 'products' && e.value != null) e.key: e.value is bool ? (e.value ? '1' : '0') : '${e.value}',
      'products': jsonEncode(data['products']),
      if (catalogId != null) '_method': 'PUT',
      'logo': await MultipartFile.fromFile(logoPath),
    });
    final response = await _dio.post(path, data: form, options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> toggleCatalog(int catalogId) async {
    final response = await _dio.post('/catalogs/$catalogId/toggle-active', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> regenerateCatalogLink(int catalogId) async {
    final response = await _dio.post('/catalogs/$catalogId/regenerate-slug', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> deleteCatalog(int catalogId) async {
    final response = await _dio.delete('/catalogs/$catalogId', options: _authOptions());
    return _asMap(response.data);
  }

  /// Descarga el PDF del catálogo (con fotos) en [dir] y devuelve la ruta.
  Future<String> downloadCatalogPdf(int catalogId, {required String dir}) =>
      _downloadFile('/catalogs/$catalogId/pdf', dir: dir, fallbackName: 'catalogo-$catalogId.pdf');

  // ── Reportes ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> reportsSummary() async {
    final response = await _dio.get('/reports/summary', options: _authOptions());
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> reportOptions() async {
    final response = await _dio.get('/reports/options', options: _authOptions());
    return _asMap(response.data);
  }

  /// Totales y una página de filas del reporte ([report]: loans, payments, movements, closures, clients, warehouses).
  Future<Map<String, dynamic>> report(String report, {Map<String, dynamic> filters = const {}, int page = 1, int perPage = 20}) async {
    final response = await _dio.get(
      '/reports/$report',
      queryParameters: {..._cleanFilters(filters), 'page': page, 'per_page': perPage},
      options: _authOptions(),
    );
    return _asMap(response.data);
  }

  /// Detalle de una sesión de caja: resumen del cierre y sus movimientos.
  Future<Map<String, dynamic>> closureDetail(int sessionId) async {
    final response = await _dio.get('/reports/closures/$sessionId', options: _authOptions());
    return _asMap(response.data);
  }

  /// Descarga el reporte en PDF o Excel ([format]: pdf | excel; [detail]: summary | detailed) y lo guarda en [dir].
  /// Devuelve la ruta del archivo. Los errores (422/500) llegan como DioException con el JSON del servidor.
  Future<String> downloadReport(
    String report, {
    required String format,
    required String detail,
    required String dir,
    Map<String, dynamic> filters = const {},
  }) =>
      _downloadFile(
        '/reports/$report/export',
        query: {..._cleanFilters(filters), 'format': format, 'detail': detail},
        dir: dir,
        fallbackName: '$report.${format == 'excel' ? 'xlsx' : 'pdf'}',
      );

  /// Descarga un archivo de la API en [dir] con el nombre que manda el servidor. Los errores (422/500) llegan
  /// como DioException con el JSON del servidor, para mostrarlos con apiErrorMessage().
  Future<String> _downloadFile(
    String path, {
    Map<String, dynamic> query = const {},
    required String dir,
    required String fallbackName,
  }) async {
    final options = _authOptions().copyWith(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(minutes: 2), // un PDF grande tarda (~12 s con 700 filas)
      validateStatus: (status) => status != null && status < 600,
    );
    final response = await _dio.get<List<int>>(path, queryParameters: query, options: options);
    final bytes = response.data ?? const <int>[];
    if (response.statusCode != 200) {
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        data = null;
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: Response(requestOptions: response.requestOptions, statusCode: response.statusCode, data: data),
        type: DioExceptionType.badResponse,
      );
    }
    final disposition = response.headers.value('content-disposition') ?? '';
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition);
    final name = match?.group(1) ?? fallbackName;
    final file = File('$dir/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Map<String, dynamic> _cleanFilters(Map<String, dynamic> filters) => {
        for (final e in filters.entries)
          if (e.value != null && '${e.value}'.trim().isNotEmpty) e.key: e.value,
      };

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }
}
