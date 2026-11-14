import 'package:flutter/material.dart';
import 'screens.dart';

class AiTradeProApp extends StatelessWidget {
  const AiTradeProApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF16A36A);
    return MaterialApp(
      title: 'RISE S TRADE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        cardTheme: CardTheme(
          color: const Color(0xFF121D2E),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1220),
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
