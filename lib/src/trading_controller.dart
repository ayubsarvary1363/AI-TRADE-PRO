
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_hub.dart';

// =====================================================
// AI TRADE PRO
// Trading Controller - Version 0.8.0
// Paper trading orchestration
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

  bool _running = false;
  bool _refreshingQuote = false;
  bool _refreshingCandles = false;
  bool _disposed = false;

  MarketQuote? latestQuote;
  TradeSignal? latestSignal;

  List<Candle> candles = [];

  DateTime? _lastProcessedCandle;

  String status = 'آماده دریافت اطلاعات بازار';
  String? lastError;

  TradingController({
    required this.marketHub,
  });

  bool get isRunning => _running;

  bool get isRefreshing =>
      _refreshingQuote || _refreshingCandles;

  double get currentPrice => latestQuote?.midPrice ?? 0;

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
    if (currentPrice <= 0) return {};
    return {symbol: currentPrice};
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

    _quoteTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => refreshQuote(),
    );

    _candleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshCandles(),
    );
  }

  // -------------------- STOP --------------------

  void stop() {
    _running = false;

    _quoteTimer?.cancel();
    _candleTimer?.cancel();

    _quoteTimer = null;
    _candleTimer = null;

    status = 'ربات آزمایشی متوقف شد';

    if (!_disposed) notifyListeners();
  }

  // -------------------- REFRESH MARKET --------------------

  Future<void> refreshMarket() async {
    await refreshQuote();
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

      if (quote == null) {
        status = 'قیمت معتبر دریافت نشد';
        lastError = 'اتصال یا دریافت قیمت ناموفق بود';
      } else {
        latestQuote = quote;
        lastError = null;

        portfolio.updateEquity(_currentPrices);

        if (_running) {
          status = 'قیمت بازار به‌روزرسانی شد';
        }
      }
    } catch (error) {
      if (!_disposed) {
        lastError = error.toString();
        status = 'خطا در دریافت قیمت';
      }
    } finally {
      _refreshingQuote = false;

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
        status = 'برای تحلیل، کندل کافی دریافت نشد';
        return;
      }

      candles = result;

      latestSignal = signalEngine.analyze(
        candles,
        style: style,
      );

      _processNewSignal();

      lastError = null;
    } catch (error) {
      if (!_disposed) {
        lastError = error.toString();
        status = 'خطا در دریافت کندل‌ها';
      }
    } finally {
      _refreshingCandles = false;

      if (!_disposed) notifyListeners();
    }
  }

  // -------------------- PAPER EXECUTION --------------------

  void _processNewSignal() {
    if (!_running || latestSignal == null || candles.isEmpty) {
      return;
    }

    final signal = latestSignal!;
    final candleTime = candles.last.time;

    // از اجرای چندباره یک سیگنال روی یک کندل جلوگیری می‌شود.
    if (_lastProcessedCandle == candleTime) return;

    _lastProcessedCandle = candleTime;

    if (signal.direction == SignalDirection.hold ||
        signal.confidence < 0.60 ||
        currentPrice <= 0) {
      status = 'سیگنال معتبر برای معامله وجود ندارد';
      return;
    }

    final currentEquity = portfolio.updateEquity(_currentPrices);

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
    if (portfolio.positions.containsKey(symbol)) {
      status = 'برای این نماد موقعیت خرید باز وجود دارد';
      return;
    }

    final price = currentPrice;
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
    final position = portfolio.positions[symbol];

    if (position == null) {
      status = 'موقعیت بازی برای فروش وجود ندارد';
      return;
    }

    final success = portfolio.sell(
      symbol: symbol,
      price: currentPrice,
      quantity: position.quantity,
    );

    status = success
        ? 'فروش آزمایشی ثبت شد'
        : 'ثبت فروش ناموفق بود';
  }

  // -------------------- SETTINGS --------------------

  void changeSymbol(String value) {
    if (_disposed || value.trim().isEmpty) return;

    symbol = value.trim().toUpperCase();
    latestQuote = null;
    latestSignal = null;
    candles = [];
    _lastProcessedCandle = null;

    notifyListeners();

    if (_running) {
      refreshMarket();
    }
  }

  void changeInterval(String value) {
    if (_disposed || interval == value) return;

    interval = value;
    latestSignal = null;
    _lastProcessedCandle = null;

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

    _lastProcessedCandle = null;
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

    unawaited(marketHub.dispose());

    super.dispose();
  }
}
