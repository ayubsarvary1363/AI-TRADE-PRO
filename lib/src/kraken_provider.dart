
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

class KrakenProvider implements MarketProvider, CandleMarketProvider {
  final http.Client _client;
  final String restUrl;
  final String wsUrl;

  WebSocketChannel? _socket;
  StreamSubscription? _subscription;

  bool _closed = false;
  bool _connecting = false;

  final Set<String> _subscribed = {};
  final Map<String, String> _symbolsByPair = {};
  final Map<String, MarketQuote> _quotes = {};

  String? lastError;

  KrakenProvider({
    http.Client? client,
    this.restUrl = 'https://api.kraken.com',
    this.wsUrl = 'wss://ws.kraken.com/v2',
  }) : _client = client ?? http.Client();

  @override
  String get id => 'kraken';

  @override
  String get name => 'Kraken';

  @override
  MarketType get market => MarketType.crypto;

  // نماد مورد استفاده در WebSocket نسخه 2
  String _pair(String symbol) {
    const pairs = {
      'BTCUSDT': 'XBT/USDT',
      'ETHUSDT': 'ETH/USDT',
      'BNBUSDT': 'BNB/USDT',
      'SOLUSDT': 'SOL/USDT',
      'XRPUSDT': 'XRP/USDT',
      'ADAUSDT': 'ADA/USDT',
      'DOGEUSDT': 'DOGE/USDT',
    };

    final value = symbol.trim().toUpperCase();
    return pairs[value] ?? value;
  }

  // نماد مورد استفاده در REST کراکن
  String _restPair(String symbol) {
    const pairs = {
      'BTCUSDT': 'XBTUSDT',
      'ETHUSDT': 'ETHUSDT',
      'BNBUSDT': 'BNBUSDT',
      'SOLUSDT': 'SOLUSDT',
      'XRPUSDT': 'XRPUSDT',
      'ADAUSDT': 'ADAUSDT',
      'DOGEUSDT': 'XDGUSDT',
    };

    final value = symbol.trim().toUpperCase();
    return pairs[value] ?? _pair(value).replaceAll('/', '');
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  @override
  Future<bool> checkConnection() async {
    if (_closed) return false;

    try {
      final response = await _client
          .get(Uri.parse('$restUrl/0/public/SystemStatus'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        lastError = 'خطای اتصال Kraken: HTTP ${response.statusCode}';
        return false;
      }

      final data = jsonDecode(response.body);

      if (data is Map &&
          data['error'] is List &&
          (data['error'] as List).isEmpty) {
        lastError = null;
        return true;
      }

      lastError = 'پاسخ وضعیت Kraken معتبر نیست';
      return false;
    } catch (e) {
      lastError = 'اتصال به Kraken ناموفق بود: $e';
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
          lastError = 'خطای WebSocket کراکن: $error';
          _resetSocket();
        },
        onDone: _resetSocket,
        cancelOnError: true,
      );
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
    final pair = _pair(normalized);

    // نگاشت پیش از دریافت اولین پیام ثبت می‌شود.
    _symbolsByPair[pair] = normalized;

    _connectWebSocket();

    if (_socket == null || _subscribed.contains(pair)) return;

    try {
      _socket!.sink.add(jsonEncode({
        'method': 'subscribe',
        'params': {
          'channel': 'ticker',
          'symbol': [pair],
        },
      }));

      _subscribed.add(pair);
    } catch (e) {
      lastError = 'ارسال درخواست قیمت زنده ناموفق بود: $e';
      _resetSocket();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message.toString());

      if (decoded is! Map) return;
      if (decoded['channel'] != 'ticker') return;

      final data = decoded['data'];
      if (data is! List) return;

      for (final item in data) {
        if (item is! Map) continue;

        final pair = item['symbol']?.toString();
        if (pair == null) continue;

        final appSymbol = _symbolsByPair[pair];
        if (appSymbol == null) continue;

        final bid = _number(item['bid']);
        final ask = _number(item['ask']);
        final volume = _number(item['volume']);

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
    } catch (e) {
      lastError = 'خواندن پیام قیمت Kraken ناموفق بود: $e';
    }
  }

  // -------------------- REST QUOTE --------------------

  Future<MarketQuote?> _fetchRestQuote(String symbol) async {
    final uri = Uri.parse('$restUrl/0/public/Ticker').replace(
      queryParameters: {'pair': _restPair(symbol)},
    );

    final response = await _client.get(uri).timeout(
      const Duration(seconds: 8),
    );

    if (response.statusCode != 200) {
      throw StateError('خطای دریافت قیمت Kraken: HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map ||
        decoded['error'] is! List ||
        (decoded['error'] as List).isNotEmpty) {
      final errors = decoded is Map ? decoded['error'] : null;
      throw StateError('خطای API کراکن: $errors');
    }

    final result = decoded['result'];

    if (result is! Map || result.isEmpty) {
      throw StateError('جفت‌ارز ${_restPair(symbol)} در Kraken پیدا نشد');
    }

    final ticker = result.values.first;
    if (ticker is! Map) return null;

    final asks = ticker['a'];
    final bids = ticker['b'];
    final volumes = ticker['v'];

    if (asks is! List ||
        bids is! List ||
        asks.isEmpty ||
        bids.isEmpty) {
      return null;
    }

    final bid = _number(bids[0]);
    final ask = _number(asks[0]);

    final volume = volumes is List && volumes.length > 1
        ? _number(volumes[1])
        : 0.0;

    final quote = MarketQuote(
      providerId: id,
      symbol: symbol.toUpperCase(),
      market: MarketType.crypto,
      bid: bid,
      ask: ask,
      volume: volume,
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

    // فرصت کوتاه برای دریافت قیمت از WebSocket
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

  int _interval(String value) {
    const intervals = {
      '1m': 1,
      '5m': 5,
      '15m': 15,
      '30m': 30,
      '1h': 60,
      '4h': 240,
      '1d': 1440,
    };

    final result = intervals[value];

    if (result == null) {
      throw ArgumentError('تایم‌فریم پشتیبانی نمی‌شود: $value');
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

    final uri = Uri.parse('$restUrl/0/public/OHLC').replace(
      queryParameters: {
        'pair': _restPair(symbol),
        'interval': _interval(interval).toString(),
      },
    );

    final response = await _client.get(uri).timeout(
      const Duration(seconds: 12),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'خطای دریافت کندل Kraken: HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map ||
        decoded['error'] is! List ||
        (decoded['error'] as List).isNotEmpty) {
      final errors = decoded is Map ? decoded['error'] : null;
      throw StateError('خطای دریافت کندل از Kraken: $errors');
    }

    final result = decoded['result'];
    if (result is! Map) return const [];

    dynamic rows;

    for (final entry in result.entries) {
      if (entry.key.toString() != 'last') {
        rows = entry.value;
        break;
      }
    }

    if (rows is! List) return const [];

    final candles = <Candle>[];

    for (final item in rows) {
      if (item is! List || item.length < 7) continue;

      final timestamp = _number(item[0]);
      if (timestamp <= 0) continue;

      final candle = Candle(
        time: DateTime.fromMillisecondsSinceEpoch(
          (timestamp * 1000).round(),
          isUtc: true,
        ),
        open: _number(item[1]),
        high: _number(item[2]),
        low: _number(item[3]),
        close: _number(item[4]),
        volume: _number(item[6]),
      );

      if (candle.isValid) {
        candles.add(candle);
      }
    }

    candles.sort((a, b) => a.time.compareTo(b.time));

    final safeLimit = limit.clamp(30, 720).toInt();

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
    _symbolsByPair.clear();
    _subscribed.clear();

    _client.close();
  }
}
