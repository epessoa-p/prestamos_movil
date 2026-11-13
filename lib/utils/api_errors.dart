import 'dart:math';

import 'package:dio/dio.dart';

/// Mensaje para el usuario a partir de un error de la API: primer error de validación,
/// o `message`, o [fallback].
String apiErrorMessage(Object error, {String fallback = 'No se pudo completar la operación. Intenta nuevamente.'}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        return (first is List && first.isNotEmpty) ? first.first.toString() : first.toString();
      }
      if (data['message'] != null) return data['message'].toString();
    }
    if (error.response == null) return 'No se pudo conectar con el servidor. Revisa tu conexión.';
  }
  return fallback;
}

/// true si el error merece quedar en el log local (sin respuesta del servidor o error 5xx).
bool isUnexpectedApiError(Object error) =>
    error is! DioException || error.response == null || (error.response!.statusCode ?? 0) >= 500;

/// Id único por intento: el servidor no repite la operación si el envío se reintenta (responde 409).
String newRequestId() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
