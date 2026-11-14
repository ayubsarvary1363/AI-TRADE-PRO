import 'dart:convert';
import 'package:http/http.dart' as http;
import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

/// Public Yahoo Finance chart feed for indicative FX prices.
/// This feed is not an execution broker and may be delayed or rate-limited.
class YahooForexProvider implements MarketProvider, CandleMarketProvider {
  final http.Client _client;
  final String baseUrl;
  bool _closed = false;

  YahooForexProvider({http.Client? client, this.baseUrl = 'https://query1.finance.yahoo.com'})
      : _client = client ?? http.Client();

  @override
  String get id => 'yahoo_forex';
  @override
  String get name => 'Yahoo Finance FX (indicative)';
  @override
  MarketType get market => MarketType.forex;

  String _ticker(String symbol) {
    final value = symbol.trim().toUpperCase().replaceAll('/', '');
    return value.endsWith('=X') ? value : '${value}=X';
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Uri _chartUri(String symbol, {String range = '5d', String interval = '1m'}) =>
      Uri.parse('$baseUrl/v8/finance/chart/${Uri.encodeComponent(_ticker(symbol))}')
          .replace(queryParameters: {'range': range, 'interval': interval});

  @override
  Future<bool> checkConnection() async {
    if (_closed) return false;
    try {
      final response = await _client.get(_chartUri('EURUSD', range: '1d', interval: '5m'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      final chart = decoded is Map ? decoded['chart'] : null;
      final result = chart is Map ? chart['result'] : null;
      return result is List && result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<MarketQuote?> fetchQuote(String symbol) async {
    if (_closed || symbol.trim().isEmpty) return null;
    final response = await _client.get(_chartUri(symbol, range: '1d', interval: '1m'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Yahoo FX quote HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    final chart = decoded is Map ? decoded['chart'] : null;
    final rows = chart is Map ? chart['result'] : null;
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw StateError('Yahoo FX quote data unavailable for $symbol');
    }
    final meta = rows.first['meta'];
    if (meta is! Map) throw StateError('Yahoo FX metadata missing');
    final price = _number(meta['regularMarketPrice']);
    final timestamp = _number(meta['regularMarketTime']);
    if (price <= 0 || timestamp <= 0) {
      throw StateError('Yahoo FX returned an invalid price for $symbol');
    }
    return MarketQuote(
      providerId: id,
      symbol: symbol.trim().toUpperCase(),
      market: MarketType.forex,
      bid: price,
      ask: price,
      volume: 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round(), isUtc: true),
    );
  }

  String _yahooInterval(String value) {
    const map = {'1m':'1m','5m':'5m','15m':'15m','30m':'30m','1h':'60m','2h':'60m','4h':'60m','1d':'1d','1w':'1wk'};
    final result = map[value];
    if (result == null) throw ArgumentError('Unsupported FX timeframe: $value');
    return result;
  }

  String _range(String interval, int limit) {
    if (interval == '1m') return '5d';
    if (interval == '5m' || interval == '15m' || interval == '30m') return '1mo';
    if (interval == '1h' || interval == '2h' || interval == '4h') return '6mo';
    return limit > 500 ? '5y' : '1y';
  }

  @override
  Future<List<Candle>> fetchCandles(String symbol, String interval, {int limit = 200}) async {
    if (_closed || symbol.trim().isEmpty) return const [];
    final response = await _client.get(_chartUri(symbol, range: _range(interval, limit), interval: _yahooInterval(interval)))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Yahoo FX candles HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    final chart = decoded is Map ? decoded['chart'] : null;
    final rows = chart is Map ? chart['result'] : null;
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw StateError('Yahoo FX candle data unavailable for $symbol');
    }
    final result = rows.first as Map;
    final timestamps = result['timestamp'];
    final indicators = result['indicators'];
    final quotes = indicators is Map ? indicators['quote'] : null;
    if (timestamps is! List || quotes is! List || quotes.isEmpty || quotes.first is! Map) return const [];
    final q = quotes.first as Map;
    final opens = q['open'] as List?;
    final highs = q['high'] as List?;
    final lows = q['low'] as List?;
    final closes = q['close'] as List?;
    final volumes = q['volume'] as List?;
    if (opens == null || highs == null || lows == null || closes == null) return const [];
    final candles = <Candle>[];
    for (var i = 0; i < timestamps.length; i++) {
      if (i >= opens.length || i >= highs.length || i >= lows.length || i >= closes.length) continue;
      final o = _number(opens[i]), h = _number(highs[i]), l = _number(lows[i]), c = _number(closes[i]);
      if (o <= 0 || h <= 0 || l <= 0 || c <= 0) continue;
      final candle = Candle(
        time: DateTime.fromMillisecondsSinceEpoch((_number(timestamps[i]) * 1000).round(), isUtc: true),
        open: o, high: h, low: l, close: c,
        volume: volumes != null && i < volumes.length ? _number(volumes[i]) : 0,
      );
      if (candle.isValid) candles.add(candle);
    }
    candles.sort((a, b) => a.time.compareTo(b.time));
    final safeLimit = limit.clamp(30, 720).toInt();
    return candles.length > safeLimit ? candles.sublist(candles.length - safeLimit) : candles;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
