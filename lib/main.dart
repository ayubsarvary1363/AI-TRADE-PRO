import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/background_trading_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackgroundTradingService();
  runApp(const AiTradeProApp());
}
