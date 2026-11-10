import 'dart:convert';

import 'package:http/http.dart' as http;

import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

/// Public Yahoo Finance chart endpoint for indicative FX market data.
/// This provider is data-only; it cannot execute broker orders.
class YahooForexProvider implements MarketProvider, CandleMarketProvider {
  final http.Client _client;
  final String baseUrl;
  bool _closed = false;

  YahooForexProvider({
    http.Client? client,
    this.baseUrl = 'https://query1.finance.yahoo.com',
  }) : _client = client ?? http.Client();

  @override
  String get id => 'yahoo_forex';

  @override
  String get name => 'Yahoo Finance FX';

  @override
  MarketType get market => MarketType.forex;

  String _ticker(String symbol) {
    final value = symbol.trim().toUpperCase().replaceAll('/', '');
    if (value.endsWith('=X')) return value;
    if (value.length == 6) return '${value}=X';
    throw ArgumentError('نماد فارکس نامعتبر است: $symbol');
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<Map<String, dynamic>> _chart(
    String symbol, {
    required String interval,
    required String range,
  }) async {
    if (_closed) throw StateError('منبع Yahoo Forex بسته شده است');

    final ticker = _ticker(symbol);
    final uri = Uri.parse('$baseUrl/v8/finance/chart/${Uri.encodeComponent(ticker)}')
        .replace(queryParameters: {
      'interval': interval,
      'range': range,
      'includePrePost': 'true',
    });

    final response = await _client.get(uri, headers: const {
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 AI-Trade-Pro/1.0',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw StateError('Yahoo Finance HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw StateError('پاسخ Yahoo معتبر نیست');

    final chart = decoded['chart'];
    if (chart is! Map) throw StateError('ساختار پاسخ Yahoo نامعتبر است');

    final error = chart['error'];
    if (error != null) {
      throw StateError('Yahoo Finance: $error');
    }

    final results = chart['result'];
    if (results is! List || results.isEmpty || results.first is! Map) {
      throw StateError('داده نماد ${_ticker(symbol)} در Yahoo موجود نیست');
    }

    return Map<String, dynamic>.from(results.first as Map);
  }

  @override
  Future<bool> checkConnection() async {
    try {
      await fetchQuote('EURUSD=X');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<MarketQuote?> fetchQuote(String symbol) async {
    final data = await _chart(symbol, interval: '1m', range: '1d');
    final meta = data['meta'];
    if (meta is! Map) return null;

    final price = _number(meta['regularMarketPrice'] ?? meta['previousClose']);
    if (price <= 0 || !price.isFinite) return null;

    return MarketQuote(
      providerId: id,
      symbol: _ticker(symbol),
      market: MarketType.forex,
      // Yahoo chart endpoint provides indicative last price, not a live order book.
      bid: price,
      ask: price,
      volume: 0,
      timestamp: DateTime.now(),
    );
  }

  String _interval(String value) {
    const supported = {
      '1m': '1m',
      '5m': '5m',
      '15m': '15m',
      '30m': '30m',
      '1h': '60m',
      '1d': '1d',
    };
    final result = supported[value];
    if (result == null) {
      throw ArgumentError('Yahoo Forex از تایم‌فریم $value پشتیبانی نمی‌کند');
    }
    return result;
  }

  String _range(String interval) =>
      interval == '1d' ? '1y' : '5d';

  @override
  Future<List<Candle>> fetchCandles(
    String symbol,
    String interval, {
    int limit = 200,
  }) async {
    final yahooInterval = _interval(interval);
    final data = await _chart(
      symbol,
      interval: yahooInterval,
      range: _range(interval),
    );

    final timestamps = data['timestamp'];
    final indicators = data['indicators'];
    if (timestamps is! List || indicators is! Map) return const [];

    final quoteList = indicators['quote'];
    if (quoteList is! List || quoteList.isEmpty || quoteList.first is! Map) {
      return const [];
    }

    final quote = quoteList.first as Map;
    final opens = quote['open'];
    final highs = quote['high'];
    final lows = quote['low'];
    final closes = quote['close'];
    final volumes = quote['volume'];

    if (opens is! List || highs is! List || lows is! List || closes is! List) {
      return const [];
    }

    final candles = <Candle>[];
    final count = [
      timestamps.length,
      opens.length,
      highs.length,
      lows.length,
      closes.length,
    ].reduce((a, b) => a < b ? a : b);

    for (var i = 0; i < count; i++) {
      final timestamp = _number(timestamps[i]);
      final open = _number(opens[i]);
      final high = _number(highs[i]);
      final low = _number(lows[i]);
      final close = _number(closes[i]);
      final volume = volumes is List && i < volumes.length
          ? _number(volumes[i])
          : 0.0;

      if (timestamp <= 0 ||
          open <= 0 ||
          high <= 0 ||
          low <= 0 ||
          close <= 0) {
        continue;
      }

      final candle = Candle(
        time: DateTime.fromMillisecondsSinceEpoch(
          (timestamp * 1000).round(),
          isUtc: true,
        ),
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume < 0 ? 0 : volume,
      );

      if (candle.isValid) candles.add(candle);
    }

    candles.sort((a, b) => a.time.compareTo(b.time));
    final safeLimit = limit.clamp(30, 720).toInt();
    if (candles.length > safeLimit) {
      return candles.sublist(candles.length - safeLimit);
    }
    return candles;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
