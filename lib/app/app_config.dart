import 'package:flutter/foundation.dart';

/// URL de la API según cómo se ejecuta la app:
///
/// - **Debug** (`flutter run`, F5 en VS Code) → servidor local [localBaseUrl].
/// - **Release** (`flutter build apk`, `flutter build appbundle`, `flutter build ios`) → [productionBaseUrl].
///
/// Para el local, el servidor Laravel debe escuchar en la red, no solo en localhost:
///   `php artisan serve --host=0.0.0.0 --port=8010`
/// y el celular debe estar en la misma Wi-Fi que la PC. Si cambia la IP de la PC:
///   `flutter run --dart-define=LOCAL_API_HOST=192.168.0.X`
/// (en el emulador de Android la PC es `10.0.2.2`).
///
/// `--dart-define=API_BASE_URL=https://...` fuerza una URL completa en cualquier modo.
class AppConfig {
  static const String productionBaseUrl = 'https://santaana2.sczsoft.net/api/v1';

  /// IP de la PC en la red local (Wi-Fi) y puerto de `php artisan serve`.
  static const String localApiHost = String.fromEnvironment('LOCAL_API_HOST', defaultValue: '192.168.0.13');
  static const String localApiPort = String.fromEnvironment('LOCAL_API_PORT', defaultValue: '8010');
  static const String localBaseUrl = 'http://$localApiHost:$localApiPort/api/v1';

  /// true si la app apunta al servidor local (para mostrarlo en pantalla durante el desarrollo).
  static bool get isLocal => baseUrl == localBaseUrl;

  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    return kReleaseMode ? productionBaseUrl : localBaseUrl;
  }
}
