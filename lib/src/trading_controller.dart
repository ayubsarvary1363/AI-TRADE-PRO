
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_hub.dart';
import 'market_provider.dart';
import 'market_scanner.dart';

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

  MarketType selectedMarket = MarketType.crypto;
  String symbol = 'BTCUSDT';
  String interval = '1h';

  Timer? _quoteTimer;
  Timer? _candleTimer;
  Timer? _scanTimer;

  bool _running = false;
  bool _refreshingQuote = false;
  bool _refreshingCandles = false;
  bool _disposed = false;
  bool _scanningMarkets = false;
  bool _refreshingPositionQuote = false;
  final Map<String, List<Candle>> _scannerCandles = {};

  late final MarketScanner _scanner;
  String scannerStatus = 'اسکن خودکار بازار هنوز شروع نشده است';

  bool _quoteHealthy = false;
  bool _candlesHealthy = false;

  MarketQuote? latestQuote;
  TradeSignal? latestSignal;

  List<Candle> candles = [];

  // Never trade immediately from historical candles after start or selection.
  bool _awaitNextClosedCandle = true;
  DateTime? _cooldownUntil;
  double? _activeStopPrice;
  double? _activeTakeProfitPrice;
  double? _initialRiskDistance;
  double? _highestPriceSinceEntry;

  static const Duration _stopCooldown = Duration(minutes: 10);
  static const double _atrStopMultiplier = 2.0;
  static const double _trailAtrMultiplier = 1.8;

  final Map<String, double> _lastPrices = {};
  final Map<String, MarketQuote> _tradeQuotes = {};
  bool _refreshingTradeQuotes = false;

  String status = 'آماده دریافت اطلاعات بازار';
  String? lastError;

  TradingController({
    required this.marketHub,
  }) {
    _scanner = MarketScanner(
      marketHub: marketHub,
      signalEngine: signalEngine,
    );
  }

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

  bool get hasValidCandles => candles.length >= 60;

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

  /// Returns only a genuinely fresh quote for the requested trade symbol.
  double? priceFor(String value) {
    final quote = _tradeQuotes[value.toUpperCase()];
    if (quote == null ||
        !quote.isValid ||
        !quote.isFresh(maximumAge: const Duration(seconds: 15))) {
      return null;
    }
    return quote.midPrice;
  }

  MarketType _marketForSymbol(String value) =>
      value.toUpperCase().endsWith('=X')
          ? MarketType.forex
          : MarketType.crypto;

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
    _awaitNextClosedCandle = true;
    status = 'ربات آزمایشی در حال دریافت اطلاعات است؛ منتظر کندل جدید';
    lastError = null;

    notifyListeners();

    await refreshMarket();

    if (!_running || _disposed) return;

    _quoteTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        refreshQuote();
        refreshOpenPositionQuote();
        refreshTradeQuotes();
      },
    );

    _candleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshCandles(),
    );

    _scanner.reset();
    scannerStatus = 'اسکن هوشمند ۵۵ نماد رمزارز و فارکس آغاز شد';
    _scanTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => scanMarketUniverse(),
    );
    unawaited(scanMarketUniverse());
  }

  // -------------------- STOP --------------------

  void stop() {
    _running = false;

    _quoteTimer?.cancel();
    _candleTimer?.cancel();
    _scanTimer?.cancel();

    _quoteTimer = null;
    _candleTimer = null;
    _scanTimer = null;

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

    final requestedSymbol = symbol;
    final requestedMarket = selectedMarket;

    try {
      final quote = await marketHub.getBestQuote(
        requestedSymbol,
        market: requestedMarket,
      );

      if (_disposed || requestedSymbol != symbol || requestedMarket != selectedMarket) return;

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
      _tradeQuotes[symbol.toUpperCase()] = quote;

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

  Future<void> refreshOpenPositionQuote() async {
    if (_disposed || !_running || _refreshingPositionQuote ||
        portfolio.positions.isEmpty) return;

    final openSymbol = portfolio.positions.keys.first;
    if (openSymbol == symbol) return;

    _refreshingPositionQuote = true;
    try {
      final market = openSymbol.endsWith('=X')
          ? MarketType.forex
          : MarketType.crypto;
      final quote = await marketHub.getBestQuote(
        openSymbol,
        market: market,
      );
      if (_disposed || !_running || quote == null ||
          quote.symbol.toUpperCase() != openSymbol.toUpperCase() ||
          !quote.isValid ||
          !quote.isFresh(maximumAge: const Duration(seconds: 15))) {
        return;
      }

      _tradeQuotes[openSymbol.toUpperCase()] = quote;
      _lastPrices[openSymbol] = quote.midPrice;
      _manageOpenPositionFor(
        openSymbol,
        quote,
        _scannerCandles[openSymbol] ?? const <Candle>[],
      );
      portfolio.updateEquity(_currentPrices);
    } catch (_) {
      // A failed quote must never be treated as a valid exit price.
    } finally {
      _refreshingPositionQuote = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Refresh quotes for every symbol that appears in trade history so each
  /// trade row can show its own current market price, not the selected symbol.
  Future<void> refreshTradeQuotes() async {
    if (_disposed || !_running || _refreshingTradeQuotes) return;

    final symbols = <String>{
      ...portfolio.fills.map((fill) => fill.symbol),
      ...portfolio.positions.keys,
    };
    if (symbols.isEmpty) return;

    _refreshingTradeQuotes = true;
    try {
      await Future.wait(symbols.map((value) async {
        final market = _marketForSymbol(value);
        try {
          final quote = await marketHub.getBestQuote(value, market: market);
          if (_disposed || quote == null || !quote.isValid ||
              quote.symbol.toUpperCase() != value.toUpperCase() ||
              !quote.isFresh(maximumAge: const Duration(seconds: 15))) {
            return;
          }
          _tradeQuotes[value.toUpperCase()] = quote;
          _lastPrices[value] = quote.midPrice;
        } catch (_) {
          // Keep the last quote timestamp; priceFor() will hide it when stale.
        }
      }));
      if (!_disposed) {
        portfolio.updateEquity(_currentPrices);
      }
    } finally {
      _refreshingTradeQuotes = false;
      if (!_disposed) notifyListeners();
    }
  }

  // -------------------- REFRESH CANDLES --------------------

  Future<void> refreshCandles() async {
    if (_disposed || _refreshingCandles) return;

    _refreshingCandles = true;

    final requestedSymbol = symbol;
    final requestedMarket = selectedMarket;
    final requestedInterval = interval;

    try {
      final result = await marketHub.fetchCandles(
        requestedSymbol,
        requestedInterval,
        market: requestedMarket,
        limit: 200,
      );

      if (_disposed || requestedSymbol != symbol || requestedMarket != selectedMarket || requestedInterval != interval) return;

      if (result.length < 60) {
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

      // The first dataset after start/symbol/timeframe changes is historical.
      // Record its latest closed candle but do not execute its old signal.
      if (_awaitNextClosedCandle) {
        _awaitNextClosedCandle = false;
        if (_running) status = 'اطلاعات دریافت شد؛ برای جلوگیری از معامله فوری منتظر کندل بسته‌شده جدید هستیم';
        return;
      }

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

  // -------------------- AUTOMATIC WHOLE-MARKET SCANNER --------------------

  Future<void> scanMarketUniverse() async {
    if (_disposed || !_running || _scanningMarkets) return;

    _scanningMarkets = true;
    try {
      final cycle = await _scanner.scanNextBatch(
        interval: interval,
        style: style,
        batchSize: 4,
      );

      for (final result in cycle.batch) {
        _tradeQuotes[result.symbol.toUpperCase()] = result.quote;
        _lastPrices[result.symbol] = result.quote.midPrice;
        _scannerCandles[result.symbol] = result.candles;

        final position = portfolio.positions[result.symbol];
        if (position != null) {
          if (result.isNewCandle &&
              result.signal.direction == SignalDirection.sell) {
            final closed = portfolio.sell(
              symbol: result.symbol,
              price: result.quote.bid,
              quantity: position.quantity,
            );
            if (closed) {
              _clearProtectiveState();
              status = 'سیگنال خروج برای ${result.symbol} تأیید شد؛ موقعیت بسته شد';
            }
          } else {
            _manageOpenPositionFor(
              result.symbol,
              result.quote,
              result.candles,
            );
          }
        }
      }

      portfolio.updateEquity(_currentPrices);

      scannerStatus =
          'اسکن مرحله‌ای بازار: ${cycle.scanned} از ${cycle.total} نماد';

      if (cycle.cycleCompleted) {
        final candidate = cycle.bestOpportunity;
        final diagnostic =
            'قیمت نامعتبر: ${cycle.quoteRejected}، '
            'کندل نامعتبر: ${cycle.candleRejected}، '
            'بدون کندل جدید: ${cycle.noNewCandle}، '
            'بدون سیگنال خرید: ${cycle.noBuySignal}، '
            'اطمینان کمتر از ۶۰٪: ${cycle.lowConfidence}، '
            'خرید واجدشرایط: ${cycle.buySignals}';

        if (candidate == null) {
          scannerStatus = 'اسکن کامل شد؛ فرصت خرید پیدا نشد. $diagnostic';
          if (portfolio.positions.isEmpty) {
            status = 'در این دور اسکن فرصت خرید واجدشرایط پیدا نشد';
          }
        } else if (portfolio.positions.isNotEmpty) {
          scannerStatus = 'بهترین فرصت ${candidate.symbol} شناسایی شد؛ تا بسته‌شدن موقعیت فعلی معامله جدیدی باز نمی‌شود';
        } else {
          final freshQuote = await marketHub.getBestQuote(
            candidate.symbol,
            market: candidate.market,
          );
          if (freshQuote == null ||
              !freshQuote.isValid ||
              !freshQuote.isFresh(
                maximumAge: const Duration(seconds: 15),
              ) ||
              freshQuote.symbol.toUpperCase() !=
                  candidate.symbol.toUpperCase()) {
            scannerStatus = 'فرصت ${candidate.symbol} به دلیل نبود قیمت تازه رد شد';
          } else {
            _executeScannerBuy(candidate, freshQuote);
          }
        }
      }
    } catch (error) {
      scannerStatus = 'خطا در اسکن بازار: $error';
    } finally {
      _scanningMarkets = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _executeScannerBuy(
    MarketScanResult candidate,
    MarketQuote quote,
  ) {
    if (!_running ||
        portfolio.positions.isNotEmpty ||
        candidate.signal.direction != SignalDirection.buy ||
        candidate.signal.confidence < 0.60 ||
        !quote.isFresh(maximumAge: const Duration(seconds: 15))) {
      return;
    }

    if (_cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!)) {
      scannerStatus = 'پس از خروج زیان‌ده، دوره مکث فعال است';
      return;
    }

    _lastPrices[candidate.symbol] = quote.midPrice;
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

    final price = quote.ask;
    if (price <= 0 || !price.isFinite) return;

    final atr = _calculateAtr(candidate.candles, 14);
    if (atr <= 0 || !atr.isFinite) {
      scannerStatus = 'فرصت ${candidate.symbol} به دلیل ATR نامعتبر رد شد';
      return;
    }

    final riskDistance = (atr * _atrStopMultiplier)
        .clamp(price * 0.008, price * 0.04)
        .toDouble();
    final stopPrice = price - riskDistance;
    final takeProfitPrice = price + riskDistance * 2.0;
    final quantity = riskManager.calculatePositionSize(
      equity: currentEquity,
      entryPrice: price,
      stopPrice: stopPrice,
      confidence: candidate.signal.confidence,
    );

    if (quantity <= 0 ||
        (price * quantity * (1 + portfolio.feeRate)) >
            portfolio.cashUsdt) {
      scannerStatus = 'فرصت ${candidate.symbol} با موجودی و محدودیت ریسک سازگار نبود';
      return;
    }

    final success = portfolio.buy(
      symbol: candidate.symbol,
      price: price,
      quantity: quantity,
      stopLoss: stopPrice,
      takeProfit: takeProfitPrice,
      targetPoints: takeProfitPrice - price,
    );

    if (success) {
      _activeStopPrice = stopPrice;
      _activeTakeProfitPrice = takeProfitPrice;
      _initialRiskDistance = riskDistance;
      _highestPriceSinceEntry = price;
      _lastPrices[candidate.symbol] = quote.midPrice;
      scannerStatus = 'بهترین فرصت انتخاب شد: ${candidate.symbol}';
      status = 'خرید آزمایشی خودکار روی ${candidate.symbol} ثبت شد';
    }
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
    _manageOpenPositionFor(symbol, latestQuote!, candles);
  }

  void _manageOpenPositionFor(
    String positionSymbol,
    MarketQuote quote,
    List<Candle> positionCandles,
  ) {
    if (!_running) return;
    final position = portfolio.positions[positionSymbol];
    if (position == null || _activeStopPrice == null) return;

    final bid = quote.bid;
    if (bid <= 0 || !bid.isFinite) return;

    final previousHigh = _highestPriceSinceEntry ?? position.averageEntryPrice;
    if (bid > previousHigh) _highestPriceSinceEntry = bid;
    final high = _highestPriceSinceEntry ?? bid;
    final atr = _calculateAtr(positionCandles, 14);
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

    if (_activeTakeProfitPrice != null && bid >= _activeTakeProfitPrice!) {
      final success = portfolio.sell(
        symbol: positionSymbol,
        price: bid,
        quantity: position.quantity,
      );
      if (success) {
        _clearProtectiveState();
        status = 'حد سود (TP) فعال شد؛ معامله با سود بسته شد';
        notifyListeners();
      }
      return;
    }

    if (bid <= _activeStopPrice!) {
      final success = portfolio.sell(
        symbol: positionSymbol,
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
    _activeTakeProfitPrice = null;
    _initialRiskDistance = null;
    _highestPriceSinceEntry = null;
  }

  // -------------------- SETTINGS --------------------

  void changeMarket(MarketType value) {
    if (_disposed || selectedMarket == value ||
        marketHub.getProviders(value).isEmpty) return;

    selectedMarket = value;
    symbol = value == MarketType.forex ? 'EURUSD=X' : 'BTCUSDT';
    _awaitNextClosedCandle = true;
    latestQuote = null;
    latestSignal = null;
    candles = [];
    _quoteHealthy = false;
    _candlesHealthy = false;
    status = 'در حال دریافت اطلاعات بازار ${value == MarketType.forex ? 'فارکس' : 'رمزارز'}';
    _updateErrorStatus();
    notifyListeners();

    if (_running) refreshMarket();
  }

  void changeSymbol(String value) {
    if (_disposed || value.trim().isEmpty) return;

    final nextSymbol = value.trim().toUpperCase();

    if (symbol == nextSymbol) return;

    symbol = nextSymbol;
    _awaitNextClosedCandle = true;

    latestQuote = null;
    latestSignal = null;
    candles = [];

    _quoteHealthy = false;
    _candlesHealthy = false;

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
    _awaitNextClosedCandle = true;
    _scanner.reset();

    latestSignal = null;
    candles = [];

    _candlesHealthy = false;

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
    _scanner.reset();
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
    _scannerCandles.clear();
    _scanner.reset();

    _quoteHealthy = false;
    _candlesHealthy = false;

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
    _scanTimer?.cancel();

    unawaited(marketHub.dispose());

    super.dispose();
  }
}
