import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';

/// Alta y edición de clientes (el mismo formulario sirve para ambos).
class CreateClientController extends ChangeNotifier {
  CreateClientController({required ApiService api, required ErrorLogService logger})
      : _api = api,
        _logger = logger;

  final ApiService _api;
  final ErrorLogService _logger;

  bool submitting = false;
  String? submitError;
  Map<String, String> validationErrors = {};
  Map<String, dynamic>? createdClient;

  /// Con [clientId] edita ese cliente; sin él, lo crea.
  /// En la edición, [removePhoto] quita la foto actual y [locationLat]/[locationLng] se envían
  /// siempre (null = sin ubicación).
  Future<bool> submitClient({
    int? clientId,
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
    submitting = true;
    submitError = null;
    validationErrors = {};
    createdClient = null;
    notifyListeners();

    final isEdit = clientId != null;
    final endpoint = isEdit ? '/clients/$clientId' : '/clients';

    try {
      final response = isEdit
          ? await _api.updateClient(
              clientId: clientId,
              name: name,
              idNumber: idNumber,
              phone: phone,
              email: email,
              address: address,
              notes: notes,
              locationUrl: locationUrl,
              locationLat: locationLat,
              locationLng: locationLng,
              photoPath: photoPath,
              removePhoto: removePhoto,
              docPaths: docPaths,
              docLabels: docLabels,
              tag: tag,
            )
          : await _api.createClient(
              name: name,
              idNumber: idNumber,
              phone: phone,
              email: email,
              address: address,
              notes: notes,
              locationUrl: locationUrl,
              photoPath: photoPath,
              docPaths: docPaths,
              docLabels: docLabels,
              tag: tag,
            );
      createdClient = _asMap(response['client']);
      return true;
    } on DioException catch (e, st) {
      final data = _asMap(e.response?.data);
      final message = data['message']?.toString();
      final errors = _asMap(data['errors']);

      if (e.response?.statusCode == 422 && errors.isNotEmpty) {
        final parsed = <String, String>{};
        for (final entry in errors.entries) {
          final raw = entry.value is List && (entry.value as List).isNotEmpty
              ? (entry.value as List).first.toString()
              : entry.value.toString();
          parsed[entry.key] = _translate(entry.key, raw);
        }
        validationErrors = parsed;
        submitError = parsed.length == 1 ? parsed.values.first : _summary(parsed);
      } else if (e.response?.statusCode == 403) {
        submitError = message ?? 'No tienes permisos para ${isEdit ? 'editar' : 'registrar'} clientes';
      } else {
        submitError = message ?? 'No fue posible ${isEdit ? 'guardar' : 'registrar'} el cliente';
      }

      await _logger.logError(module: isEdit ? 'edit_client' : 'create_client', error: e, stackTrace: st, endpoint: endpoint);
      return false;
    } catch (e, st) {
      submitError = 'No fue posible ${isEdit ? 'guardar' : 'registrar'} el cliente';
      await _logger.logError(module: isEdit ? 'edit_client' : 'create_client', error: e, stackTrace: st, endpoint: endpoint);
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  void clearState() {
    submitError = null;
    validationErrors = {};
    createdClient = null;
    notifyListeners();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  static const _fieldNames = <String, String>{
    'name': 'Nombre',
    'id_number': 'Número de documento',
    'phone': 'Teléfono',
    'email': 'Email',
    'address': 'Dirección',
    'notes': 'Observaciones',
    'location_url': 'Link de ubicación',
    'photo': 'Foto',
    'doc_files': 'Documentos',
    'tag': 'Etiqueta',
  };

  static String _translate(String field, String raw) {
    if (!raw.startsWith('validation.')) return raw;
    final key = raw.split(' ').first;
    final label = _fieldNames[field] ?? field;
    const map = <String, String>{
      'validation.required': 'es obligatorio',
      'validation.string': 'debe ser texto',
      'validation.max': 'supera el largo permitido',
      'validation.unique': 'ya está registrado',
      'validation.email': 'no es un email válido',
      'validation.image': 'debe ser una imagen válida',
      'validation.mimes': 'el tipo de archivo no está permitido',
      'validation.max.file': 'el archivo supera el tamaño máximo',
    };
    return '$label ${map[key] ?? raw}';
  }

  static String _summary(Map<String, String> errors) {
    if (errors.isEmpty) return 'Hay datos inválidos en el formulario';
    final fields = errors.keys.map((f) => _fieldNames[f] ?? f).toSet().toList();
    if (fields.length == 1) return 'Corrige el campo: ${fields.first}';
    if (fields.length <= 3) return 'Corrige los campos: ${fields.join(', ')}';
    return 'Corrige ${fields.length} campos con errores';
  }
}
