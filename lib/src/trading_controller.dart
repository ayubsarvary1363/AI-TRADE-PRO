
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
  DateTime? _cooldownUntil;
  double? _activeStopPrice;
  double? _initialRiskDistance;
  double? _highestPriceSinceEntry;

  static const Duration _stopCooldown = Duration(minutes: 10);
  static const double _atrStopMultiplier = 2.0;
  static const double _trailAtrMultiplier = 1.8;

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

  double? get activeStopPrice => _activeStopPrice;

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
      _manageOpenPosition();
      _updateErrorStatus();

      if (lastError == null && _running) {
        status = 'قیمت بازار به‌روزرسانی شد';
      }
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

      if (_quoteHealthy && _candlesHealthy) {
        _processNewSignal();

        if (lastError == null && !_running) {
          status = 'اطلاعات بازار دریافت شد';
        }
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

    _lastProcessedCandle = candleTime;

    if (signal.direction == SignalDirection.hold ||
        signal.confidence < 0.60 ||
        currentPrice <= 0) {
      status = 'سیگنال معتبر برای معامله وجود ندارد';
      return;
    }

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
      if (_cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!)) {
        status = 'پس از خروج زیان‌ده، دوره مکث فعال است';
        return;
      }
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

    final atr = _calculateAtr(candles, 14);
    if (atr <= 0 || !atr.isFinite) {
      status = 'ATR معتبر نیست؛ برای حفظ سرمایه ورود انجام نشد';
      return;
    }

    final riskDistance = (atr * _atrStopMultiplier)
        .clamp(price * 0.008, price * 0.04)
        .toDouble();
    final stopPrice = price - riskDistance;

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

    if (success) {
      _activeStopPrice = stopPrice;
      _initialRiskDistance = riskDistance;
      _highestPriceSinceEntry = price;
    }

    status = success
        ? 'خرید آزمایشی ثبت شد؛ حد ضرر پویا فعال شد'
        : 'موجودی برای خرید کافی نیست';
  }

  void _executePaperSell() {
    if (!hasValidPrice) {
      status = 'قیمت معتبر برای فروش وجود ندارد';
      return;
    }

    final position = portfolio.positions[symbol];

    if (position == null) {
      status = 'موقعیت بازی برای فروش وجود ندارد';
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

    if (success) _clearProtectiveState();

    status = success
        ? 'فروش آزمایشی ثبت شد'
        : 'ثبت فروش ناموفق بود';
  }

  // -------------------- DYNAMIC RISK ENGINE --------------------

  double _calculateAtr(List<Candle> data, int period) {
    if (data.length < period + 1) return 0;
    final sorted = [...data]..sort((a, b) => a.time.compareTo(b.time));
    final start = sorted.length - period;
    double total = 0;
    for (int i = start; i < sorted.length; i++) {
      final current = sorted[i];
      final previousClose = sorted[i - 1].close;
      final trueRange = [
        current.high - current.low,
        (current.high - previousClose).abs(),
        (current.low - previousClose).abs(),
      ].reduce((a, b) => a > b ? a : b);
      total += trueRange;
    }
    return total / period;
  }

  void _manageOpenPosition() {
    if (!_running || !hasValidPrice) return;
    final position = portfolio.positions[symbol];
    if (position == null || _activeStopPrice == null) return;

    final bid = latestQuote!.bid;
    if (bid <= 0 || !bid.isFinite) return;

    final previousHigh = _highestPriceSinceEntry ?? position.averageEntryPrice;
    if (bid > previousHigh) _highestPriceSinceEntry = bid;
    final high = _highestPriceSinceEntry ?? bid;
    final atr = _calculateAtr(candles, 14);
    final initialRisk = _initialRiskDistance ??
        (position.averageEntryPrice - _activeStopPrice!);

    if (initialRisk > 0 &&
        high >= position.averageEntryPrice + initialRisk * 1.25) {
      final breakEven = position.averageEntryPrice * 1.002;
      if (breakEven > _activeStopPrice!) _activeStopPrice = breakEven;
    }

    if (atr > 0 && initialRisk > 0 &&
        high >= position.averageEntryPrice + initialRisk * 1.5) {
      final trailDistance = (atr * _trailAtrMultiplier)
          .clamp(position.averageEntryPrice * 0.006,
              position.averageEntryPrice * 0.035)
          .toDouble();
      final trailingStop = high - trailDistance;
      if (trailingStop > _activeStopPrice!) _activeStopPrice = trailingStop;
    }

    if (bid <= _activeStopPrice!) {
      final success = portfolio.sell(
        symbol: symbol,
        price: bid,
        quantity: position.quantity,
      );
      if (success) {
        _cooldownUntil = DateTime.now().add(_stopCooldown);
        _clearProtectiveState();
        status = 'خروج حفاظتی انجام شد؛ ورود مجدد موقتاً متوقف است';
        notifyListeners();
      }
    }
  }

  void _clearProtectiveState() {
    _activeStopPrice = null;
    _initialRiskDistance = null;
    _highestPriceSinceEntry = null;
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
    _cooldownUntil = null;
    _clearProtectiveState();

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
