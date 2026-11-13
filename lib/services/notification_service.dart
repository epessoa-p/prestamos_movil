import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Canal Android usado para mostrar notificaciones en primer plano.
/// Debe coincidir con `default_notification_channel_id` en AndroidManifest.xml.
const AndroidNotificationChannel _defaultChannel = AndroidNotificationChannel(
  'prestamos_default_channel',
  'Notificaciones',
  description: 'Avisos de la aplicación',
  importance: Importance.high,
);

/// Handler de mensajes en segundo plano. DEBE ser una función top-level y estar
/// anotada con `@pragma('vm:entry-point')` para que sobreviva al tree-shaking.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Cuando el mensaje trae bloque `notification`, Android lo muestra
  // automáticamente en la bandeja. Aquí no hace falta lógica adicional.
}

/// Servicio centralizado de notificaciones push (Firebase Cloud Messaging).
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Se invoca con el `data` del mensaje cuando el usuario abre una notificación.
  void Function(Map<String, dynamic> data)? onMessageOpened;

  /// Se invoca cuando Firebase entrega/renueva el token del dispositivo.
  void Function(String token)? onTokenRefresh;

  /// Inicializa permisos, canal local y listeners. Idempotente.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onMessageOpened?.call(_decodePayload(payload));
        }
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_defaultChannel);

    // App en primer plano: mostramos una notificación local.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // App en segundo plano y el usuario toca la notificación.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onMessageOpened?.call(_dataFrom(message));
    });

    // App abierta desde estado terminado por una notificación.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      onMessageOpened?.call(_dataFrom(initialMessage));
    }

    _messaging.onTokenRefresh.listen((token) => onTokenRefresh?.call(token));
  }

  /// Devuelve el token FCM del dispositivo (o `null` si no se pudo obtener).
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('No se pudo obtener el token FCM: $e');
      return null;
    }
  }

  /// Elimina el token del dispositivo (al cerrar sesión).
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
    } catch (_) {}
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _defaultChannel.id,
          _defaultChannel.name,
          channelDescription: _defaultChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: _encodePayload(_dataFrom(message)),
    );
  }

  Map<String, dynamic> _dataFrom(RemoteMessage message) =>
      Map<String, dynamic>.from(message.data);

  String _encodePayload(Map<String, dynamic> data) =>
      data.entries.map((e) => '${e.key}=${e.value}').join('&');

  Map<String, dynamic> _decodePayload(String payload) {
    final result = <String, dynamic>{};
    for (final pair in payload.split('&')) {
      final idx = pair.indexOf('=');
      if (idx > 0) {
        result[pair.substring(0, idx)] = pair.substring(idx + 1);
      }
    }
    return result;
  }
}
