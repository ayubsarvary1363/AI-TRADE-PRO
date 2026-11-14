import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'market_hub.dart';
import 'provider_setup.dart';
import 'trading_controller.dart';

final FlutterBackgroundService _backgroundService = FlutterBackgroundService();

Future<void> initializeBackgroundTradingService() async {
  await _backgroundService.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: backgroundTradingEntrypoint,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: 'rise_s_trade_trading',
      initialNotificationTitle: 'RISE S TRADE',
      initialNotificationContent: 'سرویس معاملات آزمایشی فعال است',
      foregroundServiceNotificationId: 7411,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: backgroundTradingEntrypoint,
      onBackground: iosBackgroundEntrypoint,
    ),
  );
}

Future<void> startBackgroundTradingService() async {
  await _backgroundService.startService();
}

Future<void> stopBackgroundTradingService() async {
  _backgroundService.invoke('stopTrading');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _backgroundService.invoke('stopService');
}

@pragma('vm:entry-point')
void backgroundTradingEntrypoint(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'RISE S TRADE',
      content: 'موتور معاملات آزمایشی در پس‌زمینه فعال است',
    );
  }

  final marketHub = MarketHub(registry: ProviderSetup.createRegistry());
  final controller = TradingController(marketHub: marketHub);
  await controller.start();

  service.on('stopTrading').listen((_) {
    controller.stop();
  });

  service.on('stopService').listen((_) async {
    controller.stop();
    await marketHub.dispose();
    service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> iosBackgroundEntrypoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}
