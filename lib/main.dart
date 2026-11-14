import 'package:flutter/material.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Do not initialize Android foreground-service plugins before the first frame.
  // The service is configured lazily only when the user explicitly starts Demo.
  runApp(const AiTradeProApp());
}
