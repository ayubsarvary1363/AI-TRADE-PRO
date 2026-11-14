import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String _channelId = 'rise_s_trade_trading';
const int _notificationId = 7411;

final FlutterBackgroundService _backgroundService = FlutterBackgroundService();
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

bool _serviceConfigured = false;

/// Creates the Android notification channel before configuring the service.
/// Android 8+ requires a channel for foreground-service notifications.
Future<void> initializeBackgroundTradingService() async {
  if (_serviceConfigured) return;

  const channel = AndroidNotificationChannel(
    _channelId,
    'RISE S TRADE',
    description: 'وضعیت اجرای موتور معاملات',
    importance: Importance.low,
  );

  await _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await _backgroundService.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: backgroundTradingEntrypoint,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: _channelId,
      foregroundServiceTypes: const [AndroidForegroundType.dataSync],
      initialNotificationTitle: 'RISE S TRADE',
      initialNotificationContent: 'آماده‌سازی سرویس معاملات',
      foregroundServiceNotificationId: _notificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: backgroundTradingEntrypoint,
      onBackground: iosBackgroundEntrypoint,
    ),
  );

  _serviceConfigured = true;
}

Future<void> startBackgroundTradingService() async {
  await initializeBackgroundTradingService();

  final started = await _backgroundService.startService();
  if (!started) {
    throw StateError('سرویس پس‌زمینه توسط اندروید راه‌اندازی نشد');
  }
}

Future<void> stopBackgroundTradingService() async {
  _backgroundService.invoke('stopService');
}

@pragma('vm:entry-point')
void backgroundTradingEntrypoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // isForegroundMode=true and foregroundServiceTypes configure promotion
  // in the plugin. Do not call setAsForegroundService a second time here.
  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: 'RISE S TRADE',
      content: 'سرویس نگهدارنده اجرای برنامه فعال است',
    );
  }

  // One TradingController remains in the UI isolate. This isolate only
  // hosts the Android foreground service; it must not create another engine.
  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> iosBackgroundEntrypoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}
