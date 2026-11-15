
import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_hub.dart';
import 'market_provider.dart';
import 'market_symbols.dart';

// =====================================================
// AI TRADE PRO
// Trading Controller - Version 0.9.0
// Improved market data and paper trading safety
// =====================================================

class TradingController extends ChangeNotifier {
  final MarketHub marketHub;

  final PaperPortfolio portfolio = PaperPortfolio(
    initialUsdt: 100,
  );

  final RiskManager riskManager = RiskManager();
  final SignalEngine signalEngine = SignalEngine();

  TradingStyle style = TradingStyle.fast;

  String symbol = 'BTCUSDT';
  String interval = '5m';

  Timer? _quoteTimer;
  Timer? _candleTimer;
  Timer? _scanTimer;
  bool _scanningMarkets = false;
  int scannedMarketCount = 0;
  int quoteFailureCount = 0;
  int candleFailureCount = 0;
  int holdSignalCount = 0;
  int lowConfidenceCount = 0;
  int buySignalCount = 0;
  int sellSignalCount = 0;
  int executedBuyCount = 0;
  int executedSellCount = 0;
  int skippedPositionCount = 0;
  int riskBlockedCount = 0;
  int insufficientFundsCount = 0;
  String lastScanReason = 'هنوز اسکن انجام نشده است';
  final Map<String, String> _lastTradeActionBySymbol = {};

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
  final Map<String, MarketQuote> _lastQuotes = {};

  /// Returns a fresh quote for a symbol that has a recorded trade.
  /// Historical prices are retained for account valuation, but are not
  /// presented as live prices when their quote has become stale.
  double? priceFor(String value) {
    final quote = _lastQuotes[value.trim().toUpperCase()];
    if (quote == null ||
        !quote.isFresh(maximumAge: const Duration(seconds: 15))) {
      return null;
    }
    return quote.midPrice;
  }

  String status = 'آماده دریافت اطلاعات بازار';
  String? lastError;

  TradingController({
    required this.marketHub,
  }) {
    unawaited(_restoreTradeHistory());
  }

  static const String _tradeHistoryKey = 'rise_s_trade_paper_history_v1';

  Future<void> _restoreTradeHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tradeHistoryKey);
      if (raw == null || raw.isEmpty || _disposed) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      portfolio.fills
        ..clear()
        ..addAll(decoded.whereType<Map>().map((item) {
          final data = Map<String, dynamic>.from(item);
          return PaperFill(
            id: data['id'] as String,
            symbol: data['symbol'] as String,
            side: data['side'] == 'buy'
                ? SignalDirection.buy : SignalDirection.sell,
            price: (data['price'] as num).toDouble(),
            quantity: (data['quantity'] as num).toDouble(),
            fee: (data['fee'] as num).toDouble(),
            realizedPnl: (data['realizedPnl'] as num).toDouble(),
            time: DateTime.parse(data['time'] as String),
            entryPrice: (data['entryPrice'] as num?)?.toDouble(),
            allocatedUsdt: (data['allocatedUsdt'] as num?)?.toDouble(),
            exitReason: data['exitReason'] as String?,
            openedAt: data['openedAt'] == null
                ? null : DateTime.parse(data['openedAt'] as String),
            holdingDuration: data['holdingSeconds'] == null
                ? null : Duration(seconds: data['holdingSeconds'] as int),
          );
        }));
      if (!_disposed) notifyListeners();
    } catch (_) {
      // A damaged local history must not prevent the demo app from opening.
    }
  }

  Future<void> _persistTradeHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final records = portfolio.fills.map((fill) => <String, dynamic>{
        'id': fill.id,
        'symbol': fill.symbol,
        'side': fill.side.name,
        'price': fill.price,
        'quantity': fill.quantity,
        'fee': fill.fee,
        'realizedPnl': fill.realizedPnl,
        'time': fill.time.toIso8601String(),
        'entryPrice': fill.entryPrice,
        'allocatedUsdt': fill.allocatedUsdt,
        'exitReason': fill.exitReason,
        'openedAt': fill.openedAt?.toIso8601String(),
        'holdingSeconds': fill.holdingDuration?.inSeconds,
      }).toList();
      await prefs.setString(_tradeHistoryKey, jsonEncode(records));
    } catch (_) {
      // Trading remains paper-only if local history storage is unavailable.
    }
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

    _quoteTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => refreshQuote(),
    );

    _candleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshCandles(),
    );
    unawaited(scanAllMarkets());
    _scanTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => scanAllMarkets(),
    );
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

    try {
      // Refresh the selected symbol plus every symbol represented in the
      // trade history/open positions, so trade rows can show their own quote.
      final trackedSymbols = <String>{
        symbol.toUpperCase(),
        ...portfolio.fills.map((fill) => fill.symbol.toUpperCase()),
        ...portfolio.positions.keys.map((value) => value.toUpperCase()),
      };

      final results = await Future.wait(
        trackedSymbols.map((trackedSymbol) async {
          try {
            final quote = await marketHub.getBestQuote(
              trackedSymbol,
              market: MarketType.crypto,
            );
            return MapEntry(trackedSymbol, quote);
          } catch (_) {
            return MapEntry<String, MarketQuote?>(trackedSymbol, null);
          }
        }),
      );

      if (_disposed) return;

      MarketQuote? selectedQuote;
      for (final result in results) {
        final quote = result.value;
        if (quote == null ||
            !quote.isValid ||
            quote.symbol.toUpperCase() != result.key ||
            !quote.isFresh(maximumAge: const Duration(seconds: 15))) {
          continue;
        }

        _lastQuotes[result.key] = quote;
        _lastPrices[result.key] = quote.midPrice;
        _manageOpenPosition(result.key, quote);

        if (result.key == symbol.toUpperCase()) {
          selectedQuote = quote;
        }
      }

      if (selectedQuote == null) {
        _quoteHealthy = false;
        _updateErrorStatus();
      } else {
        latestQuote = selectedQuote;
        _quoteHealthy = true;
        portfolio.updateEquity(_currentPrices);
        _updateErrorStatus();

        if (lastError == null && _running) {
          status = 'قیمت بازار به‌روزرسانی شد';
        }
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

  // -------------------- MULTI-SYMBOL MARKET SCANNER --------------------

  Future<void> scanAllMarkets() async {
    if (_disposed || !_running || _scanningMarkets) return;
    _scanningMarkets = true;
    scannedMarketCount = 0;
    quoteFailureCount = 0;
    candleFailureCount = 0;
    holdSignalCount = 0;
    lowConfidenceCount = 0;
    buySignalCount = 0;
    sellSignalCount = 0;
    executedBuyCount = 0;
    executedSellCount = 0;
    skippedPositionCount = 0;
    riskBlockedCount = 0;
    insufficientFundsCount = 0;
    lastScanReason = 'در حال بررسی فرصت‌ها';
    status = 'اسکن خودکار ${MarketSymbols.crypto.length} رمزارز آغاز شد';
    notifyListeners();
    try {
      const batchSize = 4;
      final symbols = MarketSymbols.crypto;
      for (var offset = 0; offset < symbols.length; offset += batchSize) {
        if (_disposed || !_running) break;
        final batch = symbols.skip(offset).take(batchSize).toList();
        await Future.wait(batch.map(_scanOneSymbol));
        scannedMarketCount = (offset + batch.length).clamp(0, symbols.length).toInt();
        if (!_disposed) notifyListeners();
      }
      if (!_disposed && _running) {
        status = 'اسکن بازار کامل شد: $scannedMarketCount از ${symbols.length} نماد';
      }
    } catch (error) {
      if (!_disposed) status = 'خطا در اسکن بازار: $error';
    } finally {
      _scanningMarkets = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _scanOneSymbol(String marketSymbol) async {
    if (_disposed || !_running) return;
    try {
      final results = await Future.wait([
        marketHub.getBestQuote(marketSymbol, market: MarketType.crypto),
        marketHub.fetchCandles(marketSymbol, interval,
            market: MarketType.crypto, limit: 120),
      ]);
      if (_disposed || !_running) return;
      final quote = results[0] as MarketQuote?;
      final marketCandles = results[1] as List<Candle>;
      if (quote == null || !quote.isValid ||
          !quote.isFresh(maximumAge: const Duration(seconds: 15))) {
        quoteFailureCount++;
        return;
      }
      if (marketCandles.length < 30) {
        candleFailureCount++;
        return;
      }

      _lastQuotes[marketSymbol] = quote;
      _lastPrices[marketSymbol] = quote.midPrice;
      final signal = signalEngine.analyze(marketCandles, style: style);
      final candleTime = marketCandles.last.time;
      if (signal.direction == SignalDirection.hold) {
        holdSignalCount++;
        lastScanReason = '$marketSymbol: سیگنال انتظار';
        return;
      }
      if (signal.direction == SignalDirection.buy) {
        buySignalCount++;
      } else if (signal.direction == SignalDirection.sell) {
        sellSignalCount++;
      }
      if (signal.confidence < 0.60) {
        lowConfidenceCount++;
        lastScanReason = '$marketSymbol: اطمینان سیگنال کمتر از ۶۰٪';
        return;
      }

      // Re-evaluate each scan; avoid repeating an identical action on the same candle.
      final actionKey = '${candleTime.toIso8601String()}_${signal.direction.name}';
      if (_lastTradeActionBySymbol[marketSymbol] == actionKey) return;

      final equityNow = portfolio.updateEquity(_currentPrices);
      if (!riskManager.canTrade(currentEquity: equityNow,
          dayStartingEquity: portfolio.dayStartingEquity,
          peakEquity: portfolio.peakEquity)) {
        riskBlockedCount++;
        lastScanReason = 'ورود مسدود شد: محدودیت زیان روزانه یا افت سرمایه';
        stop();
        status = 'توقف خودکار به دلیل محدودیت ریسک';
        return;
      }
      if (signal.direction == SignalDirection.buy) {
        if (portfolio.positions.containsKey(marketSymbol)) {
          skippedPositionCount++;
          lastScanReason = '$marketSymbol: موقعیت خرید از قبل باز است';
          return;
        }
        final entry = quote.ask;
        final quantity = riskManager.calculatePositionSize(
          equity: equityNow, entryPrice: entry,
          stopPrice: entry * 0.98, confidence: signal.confidence);
        if (quantity > 0 && portfolio.buy(
          symbol: marketSymbol, price: entry, quantity: quantity,
          allocatedUsdt: min(10.0, quantity * entry),
          stopLossPercent: 0.02, takeProfitPercent: 0.10)) {
          executedBuyCount++;
          _lastTradeActionBySymbol[marketSymbol] = actionKey;
          lastScanReason = 'خرید آزمایشی $marketSymbol ثبت شد';
          status = lastScanReason;
          unawaited(_persistTradeHistory());
        } else {
          insufficientFundsCount++;
          lastScanReason = '$marketSymbol: حجم معامله یا موجودی کافی نیست';
        }
      } else if (signal.direction == SignalDirection.sell) {
        final position = portfolio.positions[marketSymbol];
        if (position == null) {
          skippedPositionCount++;
          lastScanReason = '$marketSymbol: موقعیت بازی برای فروش وجود ندارد';
          return;
        }
        if (portfolio.sell(symbol: marketSymbol, price: quote.bid,
            quantity: position.quantity, exitReason: 'خروج با سیگنال')) {
          executedSellCount++;
          _lastTradeActionBySymbol[marketSymbol] = actionKey;
          lastScanReason = 'فروش آزمایشی $marketSymbol ثبت شد';
          status = lastScanReason;
          unawaited(_persistTradeHistory());
        }
      }
    } catch (_) {
      // An unavailable pair does not interrupt scanning other symbols.
    }
  }

  void _manageOpenPosition(String marketSymbol, MarketQuote quote) {
    final position = portfolio.positions[marketSymbol];
    if (position == null || !quote.isValid) return;
    final price = quote.bid;
    if (price <= 0 || !price.isFinite) return;
    if (price > position.highestPrice) position.highestPrice = price;

    // پس از ۳٪ رشد، حد ضرر متحرک ۱٫۵٪ پایین‌تر از اوج قیمت قرار می‌گیرد.
    if (position.highestPrice >= position.averageEntryPrice * 1.03) {
      final candidate = position.highestPrice * 0.985;
      if (candidate > position.trailingStop) position.trailingStop = candidate;
    }
    final effectiveStop = max(position.stopPrice, position.trailingStop);
    if (price >= position.targetPrice) {
      portfolio.sell(symbol: marketSymbol, price: price,
        quantity: position.quantity, exitReason: 'رسیدن به هدف سود ۱۰٪');
      lastScanReason = '$marketSymbol: هدف سود ۱۰٪ محقق شد';
      status = lastScanReason;
      unawaited(_persistTradeHistory());
      notifyListeners();
    } else if (price <= effectiveStop) {
      final reason = position.trailingStop > position.stopPrice
          ? 'فعال شدن حد ضرر متحرک' : 'فعال شدن حد ضرر ۲٪';
      portfolio.sell(symbol: marketSymbol, price: price,
        quantity: position.quantity, exitReason: reason);
      lastScanReason = '$marketSymbol: $reason';
      status = lastScanReason;
      unawaited(_persistTradeHistory());
      notifyListeners();
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
      allocatedUsdt: min(10.0, quantity * price),
      stopLossPercent: 0.02,
      takeProfitPercent: 0.10,
    );

    status = success
        ? 'خرید آزمایشی ثبت شد'
        : 'موجودی برای خرید کافی نیست';
    if (success) unawaited(_persistTradeHistory());
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
      exitReason: 'خروج با سیگنال',
    );

    status = success
        ? 'فروش آزمایشی ثبت شد'
        : 'ثبت فروش ناموفق بود';
    if (success) unawaited(_persistTradeHistory());
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
    unawaited(SharedPreferences.getInstance().then(
      (prefs) => prefs.remove(_tradeHistoryKey),
    ));

    latestQuote = null;
    latestSignal = null;
    candles = [];

    _lastPrices.clear();
    _lastQuotes.clear();

    _quoteHealthy = false;
    _candlesHealthy = false;

    _lastProcessedCandle = null;
    _lastTradeActionBySymbol.clear();

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
