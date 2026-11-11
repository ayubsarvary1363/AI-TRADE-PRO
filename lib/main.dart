import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/background_trading_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackgroundTradingService();
  runApp(const AiTradeProApp());
}
