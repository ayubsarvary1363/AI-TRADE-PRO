import 'dart:convert';

import 'package:http/http.dart' as http;

import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

// Public Yahoo Finance market-data adapter.
// Indicative quotes only: no broker connection and no real orders.
class YahooForexProvider
    implements MarketProvider, CandleMarketProvider, MarketProviderDiagnostics {
  final http.Client _client;
  bool _closed = false;

  @override
  String? lastError;

  YahooForexProvider({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get id => 'yahoo_forex';

  @override
  String get name => 'Yahoo Finance FX (indicative)';

  @override
  MarketType get market => MarketType.forex;

  static const supportedSymbols = <String>[
    'EURUSD=X',
    'GBPUSD=X',
    'AUDUSD=X',
    'NZDUSD=X',
  ];

  Uri _chartUri(String symbol, String interval, String range) {
    final encoded = Uri.encodeComponent(symbol.toUpperCase());
    return Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/$encoded',
    ).replace(queryParameters: {
      'interval': interval,
      'range': range,
      'includePrePost': 'false',
    });
  }

  Future<Map<String, dynamic>> _fetchChart(
    String symbol, {
    required String interval,
    required String range,
  }) async {
    if (_closed) throw StateError('Forex provider is closed');

    final response = await _client.get(
      _chartUri(symbol, interval, range),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 AI-Trade-Pro',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw StateError('Yahoo Finance HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw StateError('پاسخ فارکس نامعتبر است');

    final chart = decoded['chart'];
    if (chart is! Map) throw StateError('ساختار پاسخ فارکس نامعتبر است');

    final error = chart['error'];
    if (error != null) throw StateError('Yahoo Finance: $error');

    final results = chart['result'];
    if (results is! List || results.isEmpty || results.first is! Map) {
      throw StateError('داده‌ای برای نماد فارکس $symbol پیدا نشد');
    }

    return Map<String, dynamic>.from(results.first as Map);
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Future<bool> checkConnection() async {
    try {
      await fetchQuote('EURUSD=X');
      lastError = null;
      return true;
    } catch (error) {
      lastError = error.toString();
      return false;
    }
  }

  @override
  Future<MarketQuote?> fetchQuote(String symbol) async {
    if (_closed) return null;
    final normalized = symbol.trim().toUpperCase();
    if (!supportedSymbols.contains(normalized)) {
      lastError = 'جفت‌ارز فارکس پشتیبانی نمی‌شود: $normalized';
      return null;
    }

    try {
      final result = await _fetchChart(
        normalized,
        interval: '1m',
        range: '1d',
      );
      final meta = result['meta'];
      if (meta is! Map) throw StateError('قیمت لحظه‌ای در پاسخ موجود نیست');

      final price = _number(meta['regularMarketPrice']);
      if (price <= 0) throw StateError('قیمت فارکس معتبر نیست');

      // Yahoo is a market-data source, not a broker order book.
      // Use a clearly indicative 1-pip-wide spread for paper simulation.
      final halfSpread = price * 0.00005;
      final quote = MarketQuote(
        providerId: id,
        symbol: normalized,
        market: MarketType.forex,
        bid: price - halfSpread,
        ask: price + halfSpread,
        volume: 0,
        timestamp: DateTime.now(),
      );

      if (!quote.isValid) throw StateError('قیمت فارکس نامعتبر است');
      lastError = null;
      return quote;
    } catch (error) {
      lastError = error.toString();
      return null;
    }
  }

  @override
  Future<List<Candle>> fetchCandles(
    String symbol,
    String interval, {
    int limit = 200,
  }) async {
    if (_closed) return const [];
    final normalized = symbol.trim().toUpperCase();
    if (!supportedSymbols.contains(normalized)) {
      throw ArgumentError('جفت‌ارز فارکس پشتیبانی نمی‌شود: $normalized');
    }

    const intervalMap = <String, String>{
      '1m': '1m',
      '3m': '5m',
      '5m': '5m',
      '15m': '15m',
      '30m': '30m',
      '1h': '60m',
      '2h': '60m',
      '4h': '60m',
      '1d': '1d',
      '1w': '1wk',
    };
    final yahooInterval = intervalMap[interval];
    if (yahooInterval == null) {
      throw ArgumentError('تایم‌فریم فارکس پشتیبانی نمی‌شود: $interval');
    }

    final range = switch (yahooInterval) {
      '1m' => '5d',
      '5m' || '15m' || '30m' || '60m' => '1mo',
      '1d' => '1y',
      '1wk' => '5y',
      _ => '1mo',
    };

    final result = await _fetchChart(
      normalized,
      interval: yahooInterval,
      range: range,
    );

    final timestamps = result['timestamp'];
    final indicators = result['indicators'];
    if (timestamps is! List || indicators is! Map) return const [];

    final quoteList = indicators['quote'];
    if (quoteList is! List || quoteList.isEmpty || quoteList.first is! Map) {
      return const [];
    }
    final values = quoteList.first as Map;
    final opens = values['open'];
    final highs = values['high'];
    final lows = values['low'];
    final closes = values['close'];
    final volumes = values['volume'];

    if (opens is! List || highs is! List || lows is! List || closes is! List) {
      return const [];
    }

    final candles = <Candle>[];
    final count = timestamps.length;
    for (var i = 0; i < count; i++) {
      if (i >= opens.length || i >= highs.length ||
          i >= lows.length || i >= closes.length) {
        continue;
      }
      final open = _number(opens[i]);
      final high = _number(highs[i]);
      final low = _number(lows[i]);
      final close = _number(closes[i]);
      if (open <= 0 || high <= 0 || low <= 0 || close <= 0) continue;

      final timestamp = timestamps[i];
      if (timestamp is! num) continue;
      final volume = volumes is List && i < volumes.length
          ? _number(volumes[i])
          : 0.0;
      final candle = Candle(
        time: DateTime.fromMillisecondsSinceEpoch(
          timestamp.toInt() * 1000,
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
    final safeLimit = limit.clamp(30, 1000).toInt();
    return candles.length > safeLimit
        ? candles.sublist(candles.length - safeLimit)
        : candles;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
