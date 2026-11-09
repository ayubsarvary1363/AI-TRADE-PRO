
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exchange_router.dart';
import 'market_provider.dart';
import 'engine.dart';

// =====================================================
// AI TRADE PRO
// Binance Market Data Provider - Version 0.6.0
// Public quotes and historical candles
// No API key | No real orders
// =====================================================

class BinanceProvider implements MarketProvider, CandleMarketProvider, MarketProviderDiagnostics {
  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  bool _closed = false;

  @override
  String? lastError;
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

  Future<http.Response> _get(Uri uri) async {
    if (_closed) {
      throw StateError('Binance provider is closed');
    }

    final blocked = _blockedUntil;

    if (blocked != null && DateTime.now().isBefore(blocked)) {
      throw StateError('Binance temporarily blocked after rate limit');
    }

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

      final ok = response.statusCode == 200;
      lastError = ok ? null : 'HTTP ${response.statusCode}';
      return ok;
    } catch (error) {
      lastError = error.toString();
      return false;
    }
  }

  @override
  Future<MarketQuote?> fetchQuote(String symbol) async {
    if (_closed || symbol.trim().isEmpty) return null;

    final normalized = symbol.trim().toUpperCase();
    final hosts = <String>[
      baseUrl,
      'https://data-api.binance.vision',
    ];
    final failures = <String>[];

    for (final host in hosts.toSet()) {
      try {
        // Build the URI from a clean HTTPS authority and exactly one
        // query parameter. This avoids carrying query fragments from a
        // configured base URL into the public market-data request.
        final authority = Uri.parse(host);
        final uri = Uri.https(
          authority.host,
          '/api/v3/ticker/bookTicker',
          {'symbol': normalized},
        );

        final response = await _get(uri);
        final decoded = jsonDecode(response.body);

        // Binance can return API errors in a JSON body even with HTTP 200.
        if (decoded is Map && decoded['code'] != null) {
          throw StateError(
            'Binance API ${decoded['code']}: ${decoded['msg'] ?? 'unknown error'}',
          );
        }

        if (decoded is! Map<String, dynamic>) {
          throw StateError('Binance returned an unexpected quote response');
        }

        final bid = double.tryParse(decoded['bidPrice']?.toString() ?? '');
        final ask = double.tryParse(decoded['askPrice']?.toString() ?? '');

        if (bid == null || ask == null) {
          throw StateError('Binance quote response has no valid bid/ask');
        }

        final quote = MarketQuote(
          providerId: id,
          symbol: normalized,
          market: MarketType.crypto,
          bid: bid,
          ask: ask,
          volume: 0,
          timestamp: DateTime.now(),
        );

        if (!quote.isValid) {
          throw StateError('Binance quote is invalid');
        }

        lastError = null;
        return quote;
      } catch (error) {
        failures.add('${Uri.parse(host).host}: $error');
      }
    }

    lastError = failures.join(' | ');
    return null;
  }

  // -------------------- HISTORICAL CANDLES --------------------

  @override
  Future<List<Candle>> fetchCandles(
    String symbol,
    String interval, {
    int limit = 200,
  }) async {
    if (_closed || symbol.trim().isEmpty) {
      return const [];
    }

    const supportedIntervals = {
      '1m', '3m', '5m', '15m', '30m',
      '1h', '2h', '4h', '6h', '8h',
      '12h', '1d', '3d', '1w', '1M',
    };

    if (!supportedIntervals.contains(interval)) {
      throw ArgumentError('Unsupported Binance interval: $interval');
    }

    final safeLimit = limit.clamp(30, 1000);
    final normalized = symbol.trim().toUpperCase();

    final uri = Uri.parse(
      '$baseUrl/api/v3/klines',
    ).replace(
      queryParameters: {
        'symbol': normalized,
        'interval': interval,
        'limit': safeLimit.toString(),
      },
    );

    final response = await _get(uri);
    final decoded = jsonDecode(response.body);

    if (decoded is! List) return const [];

    final candles = <Candle>[];

    for (final item in decoded) {
      if (item is! List || item.length < 6) continue;

      try {
        final timestamp = int.parse(item[0].toString());

        final candle = Candle(
          time: DateTime.fromMillisecondsSinceEpoch(
            timestamp,
            isUtc: true,
          ),
          open: double.parse(item[1].toString()),
          high: double.parse(item[2].toString()),
          low: double.parse(item[3].toString()),
          close: double.parse(item[4].toString()),
          volume: double.parse(item[5].toString()),
        );

        if (candle.isValid) {
          candles.add(candle);
        }
      } catch (_) {
        continue;
      }
    }

    candles.sort((a, b) => a.time.compareTo(b.time));

    return candles;
  }

  @override
  Future<void> close() async {
    if (_closed) return;

    _closed = true;
    _client.close();
  }
}
