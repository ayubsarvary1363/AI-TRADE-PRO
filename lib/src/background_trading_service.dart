import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

final FlutterBackgroundService _backgroundService = FlutterBackgroundService();
bool _serviceConfigured = false;

/// Configures a foreground keep-alive service. The trading controller lives
/// only in the main Flutter isolate; creating another controller here would
/// start a second independent trading engine and corrupt the demo state.
Future<void> initializeBackgroundTradingService() async {
  if (_serviceConfigured) return;

  await _backgroundService.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: backgroundTradingEntrypoint,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: 'rise_s_trade_trading',
      initialNotificationTitle: 'RISE S TRADE',
      initialNotificationContent: 'موتور معاملات آزمایشی فعال است',
      foregroundServiceNotificationId: 7411,
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
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

@pragma('vm:entry-point')
void backgroundTradingEntrypoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    await service.setForegroundNotificationInfo(
      title: 'RISE S TRADE',
      content: 'سرویس نگهدارنده اجرای برنامه فعال است',
    );
  }

  // IMPORTANT: Do not create TradingController/MarketHub in this isolate.
  // The main isolate owns the single controller and the single paper portfolio.
  service.on('stopService').listen((_) async {
    service.stopSelf();
  });

  service.on('stopTrading').listen((_) async {
    if (service is AndroidServiceInstance) {
      await service.setAsBackgroundService();
    }
  });
}

@pragma('vm:entry-point')
Future<bool> iosBackgroundEntrypoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}
