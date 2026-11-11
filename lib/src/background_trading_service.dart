import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'engine.dart';
import 'exchange_router.dart';
import 'market_hub.dart';
import 'market_provider.dart';
import 'provider_setup.dart';
import 'trading_controller.dart';

class BackgroundTradingService {
  BackgroundTradingService._();

  static void initialize() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ai_trade_pro_background',
        channelName: 'AI Trade Pro',
        channelDescription: 'وضعیت اجرای ربات آزمایشی',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(2000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  @pragma('vm:entry-point')
  static void startCallback() {
    FlutterForegroundTask.setTaskHandler(_TradingTaskHandler());
  }

  static bool _starting = false;

  static Future<void> start() async {
    if (_starting) return;
    _starting = true;
    try {
      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'start'}));
        return;
      }

      // Starting a new foreground service triggers onStart, which starts
      // the engine after restoring its saved account. Do not send an IPC
      // command immediately after startService: it can arrive before the
      // task isolate has registered its handler and be silently lost.
      await FlutterForegroundTask.startService(
        serviceId: 731,
        notificationTitle: 'AI Trade Pro',
        notificationText: 'ربات آزمایشی در حال اجراست',
        notificationButtons: const [
          NotificationButton(id: 'stop', text: 'توقف ربات'),
        ],
        notificationInitialRoute: '/',
        callback: startCallback,
      );
    } finally {
      _starting = false;
    }
  }

  static void send(Map<String, dynamic> command) {
    FlutterForegroundTask.sendDataToTask(jsonEncode(command));
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'stop'}));
    }
  }
}

/// The sole trading engine is owned by the foreground task isolate.
class _TradingTaskHandler extends TaskHandler {
  TradingController? _engine;
  bool _stopping = false;

  Future<void> _persist() async {
    final engine = _engine;
    if (engine == null) return;
    await FlutterForegroundTask.saveData(
      key: 'engine_state',
      value: jsonEncode(engine.exportPersistentState()),
    );
  }

  void _publish() {
    final engine = _engine;
    if (engine == null) return;
    final symbols = <String>{
      engine.symbol,
      ...engine.portfolio.fills.map((fill) => fill.symbol),
      ...engine.portfolio.positions.keys,
    };
    final prices = <String, double>{};
    for (final symbol in symbols) {
      final price = engine.priceFor(symbol);
      if (price != null) prices[symbol] = price;
    }
    final quote = engine.latestQuote;
    final signal = engine.latestSignal;
    final snapshot = <String, dynamic>{
      'type': 'snapshot',
      'running': engine.isRunning,
      'symbol': engine.symbol,
      'interval': engine.interval,
      'style': engine.style.name,
      'status': engine.status,
      'lastError': engine.lastError,
      'quoteStatus': engine.quoteStatus,
      'candleStatus': engine.candleStatus,
      'portfolio': engine.portfolio.toJson(),
      'prices': prices,
      'quote': quote == null ? null : {
        'providerId': quote.providerId,
        'symbol': quote.symbol,
        'market': quote.market.name,
        'bid': quote.bid,
        'ask': quote.ask,
        'volume': quote.volume,
        'timestamp': quote.timestamp.toIso8601String(),
      },
      'candles': engine.candles.map((c) => {
        'time': c.time.toIso8601String(),
        'open': c.open,
        'high': c.high,
        'low': c.low,
        'close': c.close,
        'volume': c.volume,
      }).toList(),
      'signal': signal == null ? null : {
        'direction': signal.direction.name,
        'confidence': signal.confidence,
        'price': signal.price,
        'reasons': signal.reasons,
        'createdAt': signal.createdAt.toIso8601String(),
      },
    };
    FlutterForegroundTask.sendDataToMain(jsonEncode(snapshot));
    unawaited(_persist());
    FlutterForegroundTask.updateService(
      notificationTitle: 'AI Trade Pro • DEMO',
      notificationText: engine.isRunning
          ? 'در حال معامله آزمایشی • ' + engine.symbol
          : 'ربات آزمایشی متوقف است',
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final hub = MarketHub(registry: ProviderSetup.createRegistry());
    final engine = TradingController(marketHub: hub);
    _engine = engine;
    final saved = await FlutterForegroundTask.getData(key: 'engine_state');
    if (saved is String && saved.isNotEmpty) {
      try {
        final decoded = jsonDecode(saved);
        if (decoded is Map) {
          engine.restorePersistentState(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    engine.addListener(_publish);
    _publish();

    // The service is only created in response to the user's Start action.
    // Start the engine here, after restore and listener registration, so
    // startup cannot depend on a race-prone first IPC message.
    await engine.start();
    _publish();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => _publish();

  @override
  void onReceiveData(Object data) {
    unawaited(_handleCommand(data));
  }

  Future<void> _handleCommand(Object data) async {
    final engine = _engine;
    if (engine == null) return;
    Map<String, dynamic> command;
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      if (decoded is! Map) return;
      command = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    switch (command['type']) {
      case 'start':
        await engine.start();
        break;
      case 'stop':
        _stopping = true;
        engine.stop();
        await _persist();
        await FlutterForegroundTask.stopService();
        return;
      case 'refresh':
        await engine.refreshMarket();
        break;
      case 'symbol':
        if (command['value'] is String) engine.changeSymbol(command['value']);
        break;
      case 'interval':
        if (command['value'] is String) engine.changeInterval(command['value']);
        break;
      case 'style':
        if (command['value'] is String) {
          final style = TradingStyle.values.firstWhere(
            (item) => item.name == command['value'],
            orElse: () => TradingStyle.mediumTerm,
          );
          engine.changeStyle(style);
        }
        break;
      case 'reset':
        engine.resetDemo();
        break;
    }
    _publish();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      unawaited(_handleCommand(jsonEncode({'type': 'stop'})));
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    final engine = _engine;
    if (engine == null) return;
    if (_stopping) engine.stop();
    await _persist();
    engine.removeListener(_publish);
    engine.dispose();
    _engine = null;
  }
}

/// UI-side IPC proxy: it never creates a MarketHub or another trading engine.
class BackgroundTradingController extends ChangeNotifier {
  final PaperPortfolio portfolio = PaperPortfolio(initialUsdt: 50);
  TradingStyle style = TradingStyle.mediumTerm;
  String symbol = 'BTCUSDT';
  String interval = '1h';
  String status = 'آماده دریافت اطلاعات بازار';
  String? lastError;
  String quoteStatus = 'هنوز قیمتی دریافت نشده است';
  String candleStatus = 'هنوز کندلی دریافت نشده است';
  MarketQuote? latestQuote;
  TradeSignal? latestSignal;
  List<Candle> candles = [];
  bool _running = false;
  bool _disposed = false;
  Map<String, double> _prices = {};

  BackgroundTradingController() {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _restoreCachedState();
    FlutterForegroundTask.isRunningService.then((running) {
      if (!_disposed && running) BackgroundTradingService.send({'type': 'refresh'});
    });
  }

  Future<void> _restoreCachedState() async {
    try {
      final serviceRunning = await FlutterForegroundTask.isRunningService;
      if (_disposed || serviceRunning) return;
      final saved = await FlutterForegroundTask.getData(key: 'engine_state');
      if (_disposed || saved is! String || saved.isEmpty) return;
      final decoded = jsonDecode(saved);
      if (decoded is! Map) return;
      final state = Map<String, dynamic>.from(decoded);
      symbol = state['symbol']?.toString() ?? symbol;
      interval = state['interval']?.toString() ?? interval;
      style = TradingStyle.values.firstWhere(
        (value) => value.name == state['style'],
        orElse: () => TradingStyle.mediumTerm,
      );
      final account = state['portfolio'];
      if (account is Map) {
        portfolio.restoreFromJson(Map<String, dynamic>.from(account));
      }
      final rawPrices = state['lastPrices'];
      if (rawPrices is Map) {
        _prices = {};
        rawPrices.forEach((key, value) {
          if (value is num) _prices[key.toString()] = value.toDouble();
        });
      }
      _running = false;
      status = state['wasRunning'] == true
          ? 'سرویس در انتظار بازیابی است'
          : 'ربات آزمایشی متوقف است';
      notifyListeners();
    } catch (error) {
      if (!_disposed) {
        lastError = 'بازیابی حساب آزمایشی ناموفق بود: ' + error.toString();
        notifyListeners();
      }
    }
  }

  bool get isRunning => _running;
  bool get isRefreshing => false;
  bool get hasValidPrice => latestQuote != null &&
      latestQuote!.isFresh(maximumAge: const Duration(seconds: 15));
  bool get hasValidCandles => candles.length >= 30;
  double get currentPrice => hasValidPrice ? latestQuote!.midPrice : 0;
  double get equity => portfolio.equity(_prices);
  double get totalPnl => equity - portfolio.initialUsdt;
  double get unrealizedPnl => portfolio.unrealizedPnl(_prices);
  double get realizedPnl => portfolio.realizedPnl;
  int get tradeCount => portfolio.fills.length;

  double? priceFor(String value) => _prices[value.trim().toUpperCase()];

  void _onTaskData(Object data) {
    if (_disposed) return;
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      if (decoded is! Map || decoded['type'] != 'snapshot') return;
      final snapshot = Map<String, dynamic>.from(decoded);
      _running = snapshot['running'] == true;
      symbol = snapshot['symbol']?.toString() ?? symbol;
      interval = snapshot['interval']?.toString() ?? interval;
      style = TradingStyle.values.firstWhere(
        (value) => value.name == snapshot['style'],
        orElse: () => TradingStyle.mediumTerm,
      );
      status = snapshot['status']?.toString() ?? status;
      lastError = snapshot['lastError']?.toString();
      quoteStatus = snapshot['quoteStatus']?.toString() ?? quoteStatus;
      candleStatus = snapshot['candleStatus']?.toString() ?? candleStatus;
      final account = snapshot['portfolio'];
      if (account is Map) portfolio.restoreFromJson(Map<String, dynamic>.from(account));
      final rawPrices = snapshot['prices'];
      _prices = {};
      if (rawPrices is Map) {
        rawPrices.forEach((key, value) {
          if (value is num) _prices[key.toString()] = value.toDouble();
        });
      }
      final rawQuote = snapshot['quote'];
      latestQuote = rawQuote is Map ? MarketQuote(
        providerId: rawQuote['providerId'].toString(),
        symbol: rawQuote['symbol'].toString(),
        market: MarketType.values.firstWhere(
          (value) => value.name == rawQuote['market'],
          orElse: () => MarketType.crypto,
        ),
        bid: (rawQuote['bid'] as num).toDouble(),
        ask: (rawQuote['ask'] as num).toDouble(),
        volume: (rawQuote['volume'] as num).toDouble(),
        timestamp: DateTime.parse(rawQuote['timestamp'].toString()),
      ) : null;
      final rawCandles = snapshot['candles'];
      candles = rawCandles is List ? rawCandles.whereType<Map>().map((raw) => Candle(
        time: DateTime.parse(raw['time'].toString()),
        open: (raw['open'] as num).toDouble(),
        high: (raw['high'] as num).toDouble(),
        low: (raw['low'] as num).toDouble(),
        close: (raw['close'] as num).toDouble(),
        volume: (raw['volume'] as num).toDouble(),
      )).toList() : [];
      final rawSignal = snapshot['signal'];
      latestSignal = rawSignal is Map ? TradeSignal(
        direction: SignalDirection.values.firstWhere(
          (value) => value.name == rawSignal['direction'],
          orElse: () => SignalDirection.hold,
        ),
        confidence: (rawSignal['confidence'] as num).toDouble(),
        price: (rawSignal['price'] as num).toDouble(),
        reasons: (rawSignal['reasons'] as List? ?? const []).map((v) => v.toString()).toList(),
        createdAt: DateTime.parse(rawSignal['createdAt'].toString()),
      ) : null;
      notifyListeners();
    } catch (error) {
      lastError = 'خطا در دریافت وضعیت سرویس: ' + error.toString();
      notifyListeners();
    }
  }

  Future<void> start() async {
    if (_disposed || _running) return;
    await BackgroundTradingService.start();
  }

  void stop() => BackgroundTradingService.stop();
  void refreshMarket() => BackgroundTradingService.send({'type': 'refresh'});
  void refreshQuote() => refreshMarket();
  void refreshCandles() => refreshMarket();
  void changeSymbol(String value) => BackgroundTradingService.send({'type': 'symbol', 'value': value});
  void changeInterval(String value) => BackgroundTradingService.send({'type': 'interval', 'value': value});
  void changeStyle(TradingStyle value) => BackgroundTradingService.send({'type': 'style', 'value': value.name});
  void resetDemo() => BackgroundTradingService.send({'type': 'reset'});

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }
}
