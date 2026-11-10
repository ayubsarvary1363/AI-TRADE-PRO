import 'dart:convert';

import 'package:http/http.dart' as http;

import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

/// BiQuote FX provider.
/// Quotes are accepted only when the API reports an open market and a fresh
/// MT5 tick. OHLC history is provided by BiQuote and may include bootstrap
/// history from other sources, as described in BiQuote's API documentation.
class BiQuoteForexProvider implements MarketProvider, CandleMarketProvider {
  final http.Client _client;
  final String baseUrl;
  final Duration maximumQuoteAge;
  bool _closed = false;

  BiQuoteForexProvider({
    http.Client? client,
    this.baseUrl = 'https://biquote.io',
    this.maximumQuoteAge = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  @override
  String get id => 'biquote_forex';

  @override
  String get name => 'BiQuote Forex (MT5)';

  @override
  MarketType get market => MarketType.forex;

  String _apiSymbol(String symbol) {
    final value = symbol.trim().toUpperCase().replaceAll('/', '');
    final normalized = value.endsWith('=X')
        ? value.substring(0, value.length - 2)
        : value;
    if (!RegExp(r'^[A-Z]{6}$').hasMatch(normalized)) {
      throw ArgumentError('نماد فارکس نامعتبر است: $symbol');
    }
    return normalized;
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<dynamic> _getJson(Uri uri) async {
    if (_closed) throw StateError('منبع BiQuote بسته شده است');
    final response = await _client.get(uri, headers: const {
      'Accept': 'application/json',
      'User-Agent': 'AI-Trade-Pro/1.0',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw StateError('BiQuote HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body);
  }

  @override
  Future<bool> checkConnection() async {
    try {
      final quote = await fetchQuote('EURUSD=X');
      return quote != null && quote.isFresh(maximumAge: maximumQuoteAge);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<MarketQuote?> fetchQuote(String symbol) async {
    final apiSymbol = _apiSymbol(symbol);
    final uri = Uri.parse('$baseUrl/api/$apiSymbol').replace(
      queryParameters: const {'allowStale': 'false'},
    );
    final decoded = await _getJson(uri);
    if (decoded is! Map) return null;

    final data = Map<String, dynamic>.from(decoded);
    final state = (data['marketState'] ?? '').toString().toLowerCase();
    final stale = data['stale'] == true;
    final age = _number(data['quoteAgeSeconds']);
    final bid = _number(data['bid']);
    final ask = _number(data['ask']);
    final rawTimestamp = data['timestamp'] ?? data['lastQuoteAt'];
    final timestamp = DateTime.tryParse(rawTimestamp?.toString() ?? '');

    // Never turn a closed/stale quote into a current price.
    if (state != 'open' ||
        stale ||
        !age.isFinite ||
        age < 0 ||
        age > maximumQuoteAge.inSeconds ||
        timestamp == null ||
        bid <= 0 ||
        ask < bid ||
        !bid.isFinite ||
        !ask.isFinite) {
      return null;
    }

    final utcTimestamp = timestamp.isUtc ? timestamp : timestamp.toUtc();
    final quote = MarketQuote(
      providerId: id,
      // Preserve the app's selected symbol format for MarketHub validation.
      symbol: symbol.trim().toUpperCase(),
      market: MarketType.forex,
      bid: bid,
      ask: ask,
      volume: 0,
      timestamp: utcTimestamp,
    );

    if (!quote.isFresh(maximumAge: maximumQuoteAge)) return null;
    return quote;
  }

  String _interval(String value) {
    const supported = {
      '1m': '1m',
      '5m': '5m',
      '15m': '15m',
      '30m': '30m',
      '1h': '1h',
      '4h': '4h',
      '1d': '1d',
    };
    final result = supported[value];
    if (result == null) {
      throw ArgumentError(
        'BiQuote از تایم‌فریم $value پشتیبانی نمی‌کند؛ '
        'تایم‌فریم‌های 1m، 5m، 15m، 30m، 1h، 4h و 1d در دسترس‌اند',
      );
    }
    return result;
  }

  @override
  Future<List<Candle>> fetchCandles(
    String symbol,
    String interval, {
    int limit = 200,
  }) async {
    final apiSymbol = _apiSymbol(symbol);
    final apiInterval = _interval(interval);
    final uri = Uri.parse('$baseUrl/api/$apiSymbol/ohlc').replace(
      queryParameters: {
        'interval': apiInterval,
        'limit': limit.clamp(30, 1000).toString(),
      },
    );

    final decoded = await _getJson(uri);
    if (decoded is! Map || decoded['bars'] is! List) return const [];

    final bars = decoded['bars'] as List;
    final candles = <Candle>[];

    for (final item in bars) {
      if (item is! Map || item['isOpen'] == true) continue;

      final time = DateTime.tryParse(item['openTime']?.toString() ?? '');
      final open = _number(item['open']);
      final high = _number(item['high']);
      final low = _number(item['low']);
      final close = _number(item['close']);
      final volume = _number(item['tickVolume'] ?? item['volume']);

      if (time == null) continue;
      final candle = Candle(
        time: time.isUtc ? time : time.toUtc(),
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume < 0 ? 0 : volume,
      );
      if (candle.isValid &&
          candle.time.isBefore(DateTime.now().add(const Duration(seconds: 5)))) {
        candles.add(candle);
      }
    }

    candles.sort((a, b) => a.time.compareTo(b.time));
    final safeLimit = limit.clamp(30, 1000).toInt();
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
