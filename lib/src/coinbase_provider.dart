
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

class CoinbaseProvider implements MarketProvider, CandleMarketProvider {
  final http.Client _client;
  final String restUrl;
  final String wsUrl;

  WebSocketChannel? _socket;
  StreamSubscription? _subscription;

  bool _closed = false;
  bool _connecting = false;

  final Set<String> _subscribed = {};
  final Map<String, String> _symbolsByProduct = {};
  final Map<String, MarketQuote> _quotes = {};

  String? lastError;

  CoinbaseProvider({
    http.Client? client,
    this.restUrl = 'https://api.coinbase.com',
    this.wsUrl = 'wss://advanced-trade-ws.coinbase.com',
  }) : _client = client ?? http.Client();

  @override
  String get id => 'coinbase';

  @override
  String get name => 'Coinbase';

  @override
  MarketType get market => MarketType.crypto;

  String _productId(String symbol) {
    final value = symbol.trim().toUpperCase();

    if (value.endsWith('USDT')) {
      return '${value.substring(0, value.length - 4)}-USDT';
    }

    if (value.endsWith('USD')) {
      return '${value.substring(0, value.length - 3)}-USD';
    }

    return value.replaceAll('/', '-');
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  Uri _uri(String path, [Map<String, String>? parameters]) {
    return Uri.parse('$restUrl$path').replace(
      queryParameters: parameters,
    );
  }

  @override
  Future<bool> checkConnection() async {
    if (_closed) return false;

    try {
      final response = await _client
          .get(_uri('/api/v3/brokerage/market/products', {
            'limit': '1',
          }))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        lastError = 'خطای اتصال Coinbase: HTTP ${response.statusCode}';
        return false;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is Map && decoded['products'] is List) {
        lastError = null;
        return true;
      }

      lastError = 'پاسخ Coinbase معتبر نیست';
      return false;
    } catch (e) {
      lastError = 'اتصال به Coinbase ناموفق بود: $e';
      return false;
    }
  }

  // -------------------- WEBSOCKET --------------------

  void _connectWebSocket() {
    if (_closed || _connecting || _socket != null) return;

    _connecting = true;

    try {
      final socket = WebSocketChannel.connect(Uri.parse(wsUrl));
      _socket = socket;

      _subscription = socket.stream.listen(
        _handleMessage,
        onError: (error) {
          lastError = 'خطای WebSocket Coinbase: $error';
          _resetSocket();
        },
        onDone: _resetSocket,
        cancelOnError: true,
      );

      // کانال heartbeat برای پایش اتصال
      socket.sink.add(jsonEncode({
        'type': 'subscribe',
        'channel': 'heartbeats',
      }));
    } catch (e) {
      lastError = 'اتصال WebSocket برقرار نشد: $e';
      _resetSocket();
    } finally {
      _connecting = false;
    }
  }

  void _resetSocket() {
    _socket = null;
    _subscribed.clear();
  }

  void _subscribe(String symbol) {
    final normalized = symbol.trim().toUpperCase();
    final product = _productId(normalized);

    _symbolsByProduct[product] = normalized;

    _connectWebSocket();

    if (_socket == null || _subscribed.contains(product)) return;

    try {
      _socket!.sink.add(jsonEncode({
        'type': 'subscribe',
        'channel': 'ticker',
        'product_ids': [product],
      }));

      _subscribed.add(product);
    } catch (e) {
      lastError = 'ارسال درخواست قیمت Coinbase ناموفق بود: $e';
      _resetSocket();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message.toString());

      if (decoded is! Map) return;

      final events = decoded['events'];
      if (events is! List) return;

      for (final event in events) {
        if (event is! Map) continue;

        final tickers = event['tickers'];
        if (tickers is! List) continue;

        for (final item in tickers) {
          if (item is! Map) continue;

          final product = item['product_id']?.toString();
          if (product == null) continue;

          final appSymbol = _symbolsByProduct[product];
          if (appSymbol == null) continue;

          final bid = _number(item['best_bid']);
          final ask = _number(item['best_ask']);
          final volume = _number(item['volume_24_h']);

          if (bid <= 0 || ask <= 0 || ask < bid) continue;

          final quote = MarketQuote(
            providerId: id,
            symbol: appSymbol,
            market: MarketType.crypto,
            bid: bid,
            ask: ask,
            volume: volume,
            timestamp: DateTime.now(),
          );

          if (quote.isValid) {
            _quotes[appSymbol] = quote;
            lastError = null;
          }
        }
      }
    } catch (e) {
      lastError = 'خواندن پیام Coinbase ناموفق بود: $e';
    }
  }

  // -------------------- REST QUOTE --------------------

  Future<MarketQuote?> _fetchRestQuote(String symbol) async {
    final product = _productId(symbol);

    final response = await _client
        .get(_uri('/api/v3/brokerage/market/product_book', {
          'product_id': product,
          'limit': '1',
        }))
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw StateError(
        'خطای دریافت قیمت Coinbase: HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {
      throw StateError('پاسخ قیمت Coinbase معتبر نیست');
    }

    final book = decoded['pricebook'];

    if (book is! Map) {
      throw StateError('دفتر سفارش $product در Coinbase پیدا نشد');
    }

    final bids = book['bids'];
    final asks = book['asks'];

    if (bids is! List ||
        asks is! List ||
        bids.isEmpty ||
        asks.isEmpty) {
      return null;
    }

    final bestBid = bids.first;
    final bestAsk = asks.first;

    if (bestBid is! Map || bestAsk is! Map) return null;

    final bid = _number(bestBid['price']);
    final ask = _number(bestAsk['price']);

    final quote = MarketQuote(
      providerId: id,
      symbol: symbol.toUpperCase(),
      market: MarketType.crypto,
      bid: bid,
      ask: ask,
      volume: 0,
      timestamp: DateTime.now(),
    );

    return quote.isValid ? quote : null;
  }

  @override
  Future<MarketQuote?> fetchQuote(String symbol) async {
    if (_closed || symbol.trim().isEmpty) return null;

    final normalized = symbol.trim().toUpperCase();

    _subscribe(normalized);

    final cached = _quotes[normalized];

    if (cached != null &&
        cached.isFresh(maximumAge: const Duration(seconds: 5))) {
      return cached;
    }

    // فرصت کوتاه برای دریافت قیمت WebSocket
    for (var i = 0; i < 4; i++) {
      await Future.delayed(const Duration(milliseconds: 250));

      if (_closed) return null;

      final quote = _quotes[normalized];

      if (quote != null &&
          quote.isFresh(maximumAge: const Duration(seconds: 5))) {
        return quote;
      }
    }

    // مسیر جایگزین REST
    try {
      final quote = await _fetchRestQuote(normalized);

      if (quote != null) {
        _quotes[normalized] = quote;
        lastError = null;
      }

      return quote;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  // -------------------- CANDLES --------------------

  String _granularity(String interval) {
    const values = {
      '1m': 'ONE_MINUTE',
      '5m': 'FIVE_MINUTE',
      '15m': 'FIFTEEN_MINUTE',
      '30m': 'THIRTY_MINUTE',
      '1h': 'ONE_HOUR',
      '4h': 'FOUR_HOUR',
      '1d': 'ONE_DAY',
    };

    final result = values[interval];

    if (result == null) {
      throw ArgumentError('تایم‌فریم پشتیبانی نمی‌شود: $interval');
    }

    return result;
  }

  Duration _intervalDuration(String interval) {
    const values = {
      '1m': Duration(minutes: 1),
      '5m': Duration(minutes: 5),
      '15m': Duration(minutes: 15),
      '30m': Duration(minutes: 30),
      '1h': Duration(hours: 1),
      '4h': Duration(hours: 4),
      '1d': Duration(days: 1),
    };

    final result = values[interval];

    if (result == null) {
      throw ArgumentError('تایم‌فریم پشتیبانی نمی‌شود: $interval');
    }

    return result;
  }

  @override
  Future<List<Candle>> fetchCandles(
    String symbol,
    String interval, {
    int limit = 200,
  }) async {
    if (_closed || symbol.trim().isEmpty) return const [];

    final safeLimit = limit.clamp(30, 350).toInt();
    final duration = _intervalDuration(interval);

    final end = DateTime.now().toUtc();
    final start = end.subtract(duration * safeLimit);

    final product = _productId(symbol);

    final uri = _uri(
      '/api/v3/brokerage/market/products/$product/candles',
      {
        'start': (start.millisecondsSinceEpoch ~/ 1000).toString(),
        'end': (end.millisecondsSinceEpoch ~/ 1000).toString(),
        'granularity': _granularity(interval),
        'limit': safeLimit.toString(),
      },
    );

    final response = await _client.get(uri).timeout(
      const Duration(seconds: 12),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'خطای دریافت کندل Coinbase: HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map || decoded['candles'] is! List) {
      throw StateError('پاسخ کندل Coinbase معتبر نیست');
    }

    final rows = decoded['candles'] as List;
    final candles = <Candle>[];

    for (final item in rows) {
      if (item is! Map) continue;

      final timestamp = _number(item['start']);

      if (timestamp <= 0) continue;

      final candle = Candle(
        time: DateTime.fromMillisecondsSinceEpoch(
          (timestamp * 1000).round(),
          isUtc: true,
        ),
        open: _number(item['open']),
        high: _number(item['high']),
        low: _number(item['low']),
        close: _number(item['close']),
        volume: _number(item['volume']),
      );

      if (candle.isValid) {
        candles.add(candle);
      }
    }

    candles.sort((a, b) => a.time.compareTo(b.time));

    if (candles.length > safeLimit) {
      return candles.sublist(candles.length - safeLimit);
    }

    return candles;
  }

  // -------------------- CLOSE --------------------

  @override
  Future<void> close() async {
    if (_closed) return;

    _closed = true;

    await _subscription?.cancel();

    try {
      await _socket?.sink.close();
    } catch (_) {}

    _socket = null;
    _quotes.clear();
    _symbolsByProduct.clear();
    _subscribed.clear();

    _client.close();
  }
}
