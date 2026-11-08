
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exchange_router.dart';
import 'market_provider.dart';

// =====================================================
// AI TRADE PRO
// Binance Market Data Provider - Version 0.5.0
// Public market data only
// No API key required
// No real orders
// =====================================================

class BinanceProvider implements MarketProvider {
  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  bool _closed = false;
  DateTime? _lastRequestTime;
  DateTime? _blockedUntil;

  BinanceProvider({
    http.Client? client,
    this.baseUrl = 'https://api.binance.com',
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  @override
  String get id => 'binance';

  @override
  String get name => 'Binance';

  @override
  MarketType get market => MarketType.crypto;

  bool get isClosed => _closed;

  Future<http.Response> _get(Uri uri) async {
    if (_closed) {
      throw StateError('Binance provider is closed');
    }

    final blocked = _blockedUntil;

    if (blocked != null && DateTime.now().isBefore(blocked)) {
      throw StateError('Binance temporarily blocked after rate limit');
    }

    // فاصله کوتاه بین درخواست‌ها برای کاهش فشار روی API
    final previous = _lastRequestTime;

    if (previous != null) {
      final elapsed = DateTime.now().difference(previous);
      const minimumInterval = Duration(milliseconds: 250);

      if (elapsed < minimumInterval) {
        await Future.delayed(minimumInterval - elapsed);
      }
    }

    _lastRequestTime = DateTime.now();

    final response = await _client.get(uri).timeout(timeout);

    if (response.statusCode == 429 || response.statusCode == 418) {
      _blockedUntil = DateTime.now().add(
        const Duration(minutes: 1),
      );

      throw StateError(
        'Binance API rate limit: ${response.statusCode}',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Binance HTTP error: ${response.statusCode}',
      );
    }

    return response;
  }

  @override
  Future<bool> checkConnection() async {
    try {
      final response = await _get(
        Uri.parse('$baseUrl/api/v3/ping'),
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<MarketQuote?> fetchQuote(String symbol) async {
    if (_closed || symbol.trim().isEmpty) return null;

    final normalized = symbol.trim().toUpperCase();

    try {
      final uri = Uri.parse(
        '$baseUrl/api/v3/ticker/bookTicker',
      ).replace(
        queryParameters: {'symbol': normalized},
      );

      final response = await _get(uri);
      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) return null;

      final bid = double.tryParse(data['bidPrice']?.toString() ?? '');
      final ask = double.tryParse(data['askPrice']?.toString() ?? '');

      if (bid == null || ask == null) return null;

      final quote = MarketQuote(
        providerId: id,
        symbol: normalized,
        market: MarketType.crypto,
        bid: bid,
        ask: ask,
        volume: 0,
        timestamp: DateTime.now(),
      );

      return quote.isValid ? quote : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;

    _closed = true;
    _client.close();
  }
}
