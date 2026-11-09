
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_hub.dart';
import 'market_provider.dart';

// =====================================================
// AI TRADE PRO
// Trading Controller - Version 0.9.0
// Improved market data and paper trading safety
// =====================================================

class TradingController extends ChangeNotifier {
  final MarketHub marketHub;

  final PaperPortfolio portfolio = PaperPortfolio(
    initialUsdt: 50,
  );

  final RiskManager riskManager = RiskManager();
  final SignalEngine signalEngine = SignalEngine();

  TradingStyle style = TradingStyle.mediumTerm;

  String symbol = 'BTCUSDT';
  String interval = '1h';

  Timer? _quoteTimer;
  Timer? _candleTimer;
  Timer? _scannerTimer;
  bool _scanningMarkets = false;
  bool _refreshingAllQuotes = false;

  static const List<String> supportedSymbols = [
    'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT',
    'XRPUSDT', 'ADAUSDT', 'DOGEUSDT',
  ];
  final Map<String, DateTime> _lastProcessedCandles = {};

  bool _running = false;
  bool _refreshingQuote = false;
  bool _refreshingCandles = false;
  bool _disposed = false;

  bool _quoteHealthy = false;
  bool _candlesHealthy = false;

  MarketQuote? latestQuote;
  TradeSignal? latestSignal;

  List<Candle> candles = [];

  DateTime? _lastProcessedCandle;

  final Map<String, double> _lastPrices = {};

  String status = 'آماده دریافت اطلاعات بازار';
  String? lastError;

  TradingController({
    required this.marketHub,
  });

  bool get isRunning => _running;

  bool get isRefreshing =>
      _refreshingQuote || _refreshingCandles;

  bool get hasValidPrice {
    return latestQuote != null &&
        latestQuote!.isValid &&
        latestQuote!.isFresh(
          maximumAge: const Duration(seconds: 15),
        );
  }

  bool get hasValidCandles => candles.length >= 30;

  double get currentPrice {
    if (!hasValidPrice) return 0;
    return latestQuote!.midPrice;
  }

  double get equity {
    return portfolio.equity(_currentPrices);
  }

  double get totalPnl => equity - portfolio.initialUsdt;

  double get unrealizedPnl {
    return portfolio.unrealizedPnl(_currentPrices);
  }

  double get realizedPnl => portfolio.realizedPnl;

  int get tradeCount => portfolio.fills.length;

  Map<String, double> get _currentPrices {
    return Map<String, double>.from(_lastPrices);
  }

  String get quoteStatus => marketHub.lastQuoteStatus;

  String get candleStatus => marketHub.lastCandleStatus;

  void _updateErrorStatus() {
    final errors = <String>[];

    if (!_quoteHealthy) {
      errors.add(marketHub.lastQuoteStatus);
    }

    if (!_candlesHealthy) {
      errors.add(marketHub.lastCandleStatus);
    }

    lastError = errors.isEmpty ? null : errors.join(' | ');

    if (lastError != null) {
      status = 'دریافت اطلاعات بازار با مشکل مواجه است';
    }
  }

  // -------------------- START --------------------

  Future<void> start() async {
    if (_disposed || _running) return;

    _running = true;
    status = 'ربات آزمایشی در حال دریافت اطلاعات است';
    lastError = null;

    notifyListeners();

    await refreshMarket();
    if (!_running || _disposed) return;
    await scanAllMarkets();
    if (!_running || _disposed) return;

    _quoteTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => refreshAllQuotes(),
    );

    _candleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshCandles(),
    );
    _scannerTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => scanAllMarkets(),
    );
  }

  // -------------------- STOP --------------------

  void stop() {
    _running = false;

    _quoteTimer?.cancel();
    _candleTimer?.cancel();
    _scannerTimer?.cancel();

    _quoteTimer = null;
    _candleTimer = null;
    _scannerTimer = null;

    status = 'ربات آزمایشی متوقف شد';

    if (!_disposed) notifyListeners();
  }

  // -------------------- REFRESH MARKET --------------------

  Future<void> refreshMarket() async {
    if (_disposed) return;

    await refreshQuote();

    if (_disposed) return;

    await refreshCandles();
  }

  // -------------------- REFRESH QUOTE --------------------

  Future<void> refreshQuote() async {
    if (_disposed || _refreshingQuote) return;

    _refreshingQuote = true;

    try {
      final quote = await marketHub.getBestQuote(
        symbol,
        market: MarketType.crypto,
      );

      if (_disposed) return;

      if (quote == null ||
          !quote.isValid ||
          !quote.isFresh(
            maximumAge: const Duration(seconds: 15),
          )) {
        _quoteHealthy = false;
        _updateErrorStatus();
        return;
      }

      if (quote.symbol.toUpperCase() != symbol.toUpperCase()) {
        _quoteHealthy = false;
        marketHub.lastQuoteStatus = 'نماد دریافتی با نماد انتخابی متفاوت است';
        _updateErrorStatus();
        return;
      }

      latestQuote = quote;

      _lastPrices[symbol] = quote.midPrice;

      _quoteHealthy = true;

      portfolio.updateEquity(_currentPrices);

      _updateErrorStatus();

      // Keep the trading decision/status visible; quote refreshes must not
      // overwrite it every two seconds.
    } catch (error) {
      if (!_disposed) {
        _quoteHealthy = false;
        marketHub.lastQuoteStatus = 'خطای قیمت: $error';
        _updateErrorStatus();
      }
    } finally {
      _refreshingQuote = false;

      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refreshAllQuotes() async {
    if (_disposed || !_running || _refreshingAllQuotes) return;
    _refreshingAllQuotes = true;

    try {
      final quotes = await Future.wait(
        supportedSymbols.map((item) async {
          try {
            return await marketHub.getBestQuote(
              item,
              market: MarketType.crypto,
            );
          } catch (_) {
            return null;
          }
        }),
      );

      if (_disposed) return;

      for (int i = 0; i < supportedSymbols.length; i++) {
        final item = supportedSymbols[i];
        final quote = quotes[i];
        if (quote == null ||
            !quote.isValid ||
            quote.symbol.toUpperCase() != item ||
            !quote.isFresh(maximumAge: const Duration(seconds: 15))) {
          continue;
        }

        _lastPrices[item] = quote.midPrice;
        if (item == symbol) {
          latestQuote = quote;
          _quoteHealthy = true;
        }
      }

      portfolio.updateEquity(_currentPrices);
      if (symbol == 'BTCUSDT' && latestQuote == null) {
        _quoteHealthy = false;
      }
    } finally {
      _refreshingAllQuotes = false;
      if (!_disposed) notifyListeners();
    }
  }

  // -------------------- REFRESH CANDLES --------------------

  Future<void> refreshCandles() async {
    if (_disposed || _refreshingCandles) return;

    _refreshingCandles = true;

    try {
      final result = await marketHub.fetchCandles(
        symbol,
        interval,
        market: MarketType.crypto,
        limit: 200,
      );

      if (_disposed) return;

      if (result.length < 30) {
        _candlesHealthy = false;
        _updateErrorStatus();
        return;
      }

      candles = result;

      _candlesHealthy = true;

      latestSignal = signalEngine.analyze(
        candles,
        style: style,
      );

      _updateErrorStatus();

      if (lastError == null && !_running) {
        status = 'اطلاعات بازار دریافت شد';
      }
    } catch (error) {
      if (!_disposed) {
        _candlesHealthy = false;
        marketHub.lastCandleStatus = 'خطای دریافت کندل: $error';
        _updateErrorStatus();
      }
    } finally {
      _refreshingCandles = false;

      if (!_disposed) notifyListeners();
    }
  }

  // -------------------- MULTI-MARKET PAPER SCANNER --------------------

  Future<void> scanAllMarkets() async {
    if (_disposed || !_running || _scanningMarkets) return;
    _scanningMarkets = true;

    int checked = 0;
    int traded = 0;
    final errors = <String>[];

    try {
      final results = await Future.wait(
        supportedSymbols.map((item) => _scanSymbol(item)),
      );

      for (final result in results) {
        if (result == 'TRADED') {
          traded++;
          checked++;
        } else if (result == 'OK' || result == 'HOLD') {
          checked++;
        } else if (result != null) {
          errors.add(result);
        }
      }

      if (!_disposed && _running) {
        status = traded > 0
            ? '$traded معامله آزمایشی جدید در بررسی چندارزی ثبت شد'
            : 'بررسی چندارزی انجام شد؛ $checked از ' + supportedSymbols.length.toString() + ' ارز بررسی شدند، فعلاً سیگنال قابل اجرا وجود ندارد';
        if (errors.isNotEmpty && checked == 0) {
          status = 'دریافت اطلاعات چندارزی ناموفق بود';
          lastError = errors.take(3).join(' | ');
        }
        notifyListeners();
      }
    } catch (error) {
      if (!_disposed) {
        status = 'خطا در بررسی هم‌زمان بازارها';
        lastError = error.toString();
        notifyListeners();
      }
    } finally {
      _scanningMarkets = false;
    }
  }

  Future<String?> _scanSymbol(String item) async {
    try {
      final quote = await marketHub.getBestQuote(
        item,
        market: MarketType.crypto,
      );
      if (_disposed || !_running) return null;

      if (quote == null ||
          !quote.isValid ||
          quote.symbol.toUpperCase() != item ||
          !quote.isFresh(maximumAge: const Duration(seconds: 15))) {
        return '$item: قیمت معتبر دریافت نشد';
      }

      final price = quote.midPrice;
      _lastPrices[item] = price;

      final data = await marketHub.fetchCandles(
        item,
        interval,
        market: MarketType.crypto,
        limit: 200,
      );
      if (_disposed || !_running) return null;
      if (data.length < 30) return '$item: کندل کافی دریافت نشد';

      final signal = signalEngine.analyze(data, style: style);
      final candleTime = data.last.time;
      if (_lastProcessedCandles[item] == candleTime) return 'HOLD';

      if (signal.direction == SignalDirection.hold ||
          signal.confidence < 0.60) {
        return 'HOLD';
      }

      // One actionable decision per symbol per candle.
      _lastProcessedCandles[item] = candleTime;

      final currentEquity = portfolio.updateEquity(_currentPrices);
      final canTrade = riskManager.canTrade(
        currentEquity: currentEquity,
        dayStartingEquity: portfolio.dayStartingEquity,
        peakEquity: portfolio.peakEquity,
      );
      if (!canTrade) {
        stop();
        status = 'توقف خودکار به دلیل محدودیت ریسک';
        return null;
      }

      if (signal.direction == SignalDirection.buy) {
        if (portfolio.positions.containsKey(item)) return 'HOLD';

        final entry = quote.ask;
        if (entry <= 0) return '$item: قیمت خرید نامعتبر است';
        final quantity = riskManager.calculatePositionSize(
          equity: currentEquity,
          entryPrice: entry,
          stopPrice: entry * 0.98,
          confidence: signal.confidence,
        );
        if (quantity <= 0) return '$item: حجم خرید صفر است';

        return portfolio.buy(
          symbol: item,
          price: entry,
          quantity: quantity,
        ) ? 'TRADED' : '$item: موجودی نقدی کافی نیست';
      }

      if (signal.direction == SignalDirection.sell) {
        final position = portfolio.positions[item];
        if (position == null) return 'HOLD';

        return portfolio.sell(
          symbol: item,
          price: quote.bid,
          quantity: position.quantity,
        ) ? 'TRADED' : '$item: فروش ناموفق بود';
      }

      return 'HOLD';
    } catch (error) {
      return '$item: $error';
    }
  }

  // -------------------- PAPER EXECUTION --------------------

  void _processNewSignal() {
    if (!_running ||
        latestSignal == null ||
        candles.isEmpty ||
        !hasValidPrice ||
        !hasValidCandles) {
      return;
    }

    final signal = latestSignal!;
    final candleTime = candles.last.time;

    if (_lastProcessedCandle == candleTime) return;

    // A HOLD or low-confidence signal is not consumed. If it becomes
    // actionable while this candle is still current, it can be evaluated.
    if (signal.direction == SignalDirection.hold ||
        signal.confidence < 0.60 ||
        currentPrice <= 0) {
      status = signal.direction == SignalDirection.hold
          ? 'سیگنال فعلی انتظار است؛ ربات منتظر فرصت خرید یا فروش می‌ماند'
          : 'اطمینان سیگنال برای معامله کافی نیست';
      return;
    }

    // Process at most one actionable signal per candle.
    _lastProcessedCandle = candleTime;

    final currentEquity = portfolio.updateEquity(
      _currentPrices,
    );

    final canTrade = riskManager.canTrade(
      currentEquity: currentEquity,
      dayStartingEquity: portfolio.dayStartingEquity,
      peakEquity: portfolio.peakEquity,
    );

    if (!canTrade) {
      stop();
      status = 'توقف خودکار به دلیل محدودیت ریسک';
      return;
    }

    if (signal.direction == SignalDirection.buy) {
      _executePaperBuy(signal);
    } else if (signal.direction == SignalDirection.sell) {
      _executePaperSell();
    }
  }

  void _executePaperBuy(TradeSignal signal) {
    if (!hasValidPrice) {
      status = 'قیمت معتبر برای خرید وجود ندارد';
      return;
    }

    if (portfolio.positions.containsKey(symbol)) {
      status = 'برای این نماد موقعیت خرید باز وجود دارد';
      return;
    }

    final price = latestQuote!.ask;

    if (price <= 0) {
      status = 'قیمت خرید معتبر نیست';
      return;
    }

    final stopPrice = price * 0.98;

    final quantity = riskManager.calculatePositionSize(
      equity: portfolio.equity(_currentPrices),
      entryPrice: price,
      stopPrice: stopPrice,
      confidence: signal.confidence,
    );

    if (quantity <= 0) {
      status = 'حجم معامله با محدودیت ریسک سازگار نیست';
      return;
    }

    final success = portfolio.buy(
      symbol: symbol,
      price: price,
      quantity: quantity,
    );

    status = success
        ? 'خرید آزمایشی ثبت شد'
        : 'موجودی برای خرید کافی نیست';
  }

  void _executePaperSell() {
    if (!hasValidPrice) {
      status = 'قیمت معتبر برای فروش وجود ندارد';
      return;
    }

    final position = portfolio.positions[symbol];

    if (position == null) {
      status = 'سیگنال فروش معتبر است، اما دارایی بازی نداریم؛ منتظر سیگنال خرید می‌مانیم';
      return;
    }

    final price = latestQuote!.bid;

    if (price <= 0) {
      status = 'قیمت فروش معتبر نیست';
      return;
    }

    final success = portfolio.sell(
      symbol: symbol,
      price: price,
      quantity: position.quantity,
    );

    status = success
        ? 'فروش آزمایشی ثبت شد'
        : 'ثبت فروش ناموفق بود';
  }

  // -------------------- SETTINGS --------------------

  void changeSymbol(String value) {
    if (_disposed || value.trim().isEmpty) return;

    final nextSymbol = value.trim().toUpperCase();

    if (symbol == nextSymbol) return;

    symbol = nextSymbol;

    latestQuote = null;
    latestSignal = null;
    candles = [];

    _quoteHealthy = false;
    _candlesHealthy = false;

    _lastProcessedCandle = null;
    _lastProcessedCandles.remove(nextSymbol);

    status = 'در حال دریافت اطلاعات $symbol';

    _updateErrorStatus();

    notifyListeners();

    if (_running) {
      refreshMarket();
    }
  }

  void changeInterval(String value) {
    if (_disposed || interval == value) return;

    interval = value;

    latestSignal = null;
    candles = [];

    _candlesHealthy = false;
    _lastProcessedCandle = null;
    _lastProcessedCandles.clear();

    status = 'در حال دریافت کندل‌های $interval';

    _updateErrorStatus();

    notifyListeners();

    if (_running) {
      refreshCandles();
    }
  }

  void changeStyle(TradingStyle value) {
    if (_disposed || style == value) return;

    style = value;
    latestSignal = null;

    notifyListeners();

    if (_running) {
      refreshCandles();
    }
  }

  // -------------------- RESET DEMO --------------------

  void resetDemo() {
    if (_disposed) return;

    stop();

    portfolio.reset();

    latestQuote = null;
    latestSignal = null;
    candles = [];

    _lastPrices.clear();

    _quoteHealthy = false;
    _candlesHealthy = false;

    _lastProcessedCandle = null;
    _lastProcessedCandles.clear();

    lastError = null;
    status = 'حساب آزمایشی بازنشانی شد';

    notifyListeners();
  }

  // -------------------- DISPOSE --------------------

  @override
  void dispose() {
    if (_disposed) return;

    _disposed = true;

    _quoteTimer?.cancel();
    _candleTimer?.cancel();
    _scannerTimer?.cancel();

    unawaited(marketHub.dispose());

    super.dispose();
  }
}
