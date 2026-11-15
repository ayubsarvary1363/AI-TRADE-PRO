
import 'dart:math';

// =====================================================
// AI TRADE PRO
// Trading Engine Foundation - Version 0.5.0
// Paper trading enabled | Live trading locked
// Spot only | No leverage | No short selling
// =====================================================

enum TradeMode { paper, live }

const double defaultStopLossPercent = 0.01;
const double defaultTakeProfitPercent = 0.05;

enum SignalDirection { buy, sell, hold }

enum TradingStyle { fast, mediumTerm, longTerm }

// -------------------- CANDLE --------------------

class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });

  bool get isValid =>
      open > 0 &&
      high > 0 &&
      low > 0 &&
      close > 0 &&
      high >= low &&
      high >= open &&
      high >= close &&
      low <= open &&
      low <= close &&
      volume >= 0 &&
      open.isFinite &&
      high.isFinite &&
      low.isFinite &&
      close.isFinite &&
      volume.isFinite;
}

// -------------------- SIGNAL --------------------

class TradeSignal {
  final SignalDirection direction;
  final double confidence;
  final double price;
  final List<String> reasons;
  final DateTime createdAt;

  const TradeSignal({
    required this.direction,
    required this.confidence,
    required this.price,
    required this.reasons,
    required this.createdAt,
  });
}

// -------------------- INDICATORS --------------------

class SignalEngine {
  double _ema(List<double> values, int period) {
    if (values.length < period) return 0;

    final multiplier = 2 / (period + 1);
    double result = values.take(period).reduce((a, b) => a + b) / period;

    for (final value in values.skip(period)) {
      result = (value - result) * multiplier + result;
    }

    return result;
  }

  double _rsi(List<double> values, int period) {
    if (values.length <= period) return 50;

    double gains = 0;
    double losses = 0;

    for (int i = values.length - period; i < values.length; i++) {
      final change = values[i] - values[i - 1];

      if (change > 0) {
        gains += change;
      } else {
        losses += change.abs();
      }
    }

    if (losses == 0) return 100;

    final averageGain = gains / period;
    final averageLoss = losses / period;
    final rs = averageGain / averageLoss;

    return 100 - (100 / (1 + rs));
  }

  TradeSignal analyze(
    List<Candle> candles, {
    TradingStyle style = TradingStyle.mediumTerm,
    int newsSentiment = 0,
  }) {
    final valid = candles.where((c) => c.isValid).toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    if (valid.length < 30) {
      return TradeSignal(
        direction: SignalDirection.hold,
        confidence: 0,
        price: valid.isEmpty ? 0 : valid.last.close,
        reasons: ['داده کافی برای تحلیل وجود ندارد'],
        createdAt: DateTime.now(),
      );
    }

    final prices = valid.map((c) => c.close).toList();

    final ema9 = _ema(prices, 9);
    final ema21 = _ema(prices, 21);
    final ema26 = _ema(prices, 26);
    final ema12 = _ema(prices, 12);
    final rsi = _rsi(prices, 14);

    final macd = ema12 - ema26;
    final previousMacd = _ema(prices.sublist(0, prices.length - 1), 12) -
        _ema(prices.sublist(0, prices.length - 1), 26);

    final last = valid.last;
    final previous = valid[valid.length - 2];

    // Additional technical-analysis set: Bollinger Bands, Stochastic,
    // ATR volatility, swing support/resistance and candle patterns.
    final recent = valid.skip(valid.length - 20).toList();
    final sma20 = recent.map((c) => c.close).reduce((a, b) => a + b) / recent.length;
    final variance = recent
        .map((c) => (c.close - sma20) * (c.close - sma20))
        .reduce((a, b) => a + b) / recent.length;
    final deviation = sqrt(variance);
    final bollingerUpper = sma20 + (2 * deviation);
    final bollingerLower = sma20 - (2 * deviation);

    final stochasticCandles = valid.skip(valid.length - 14).toList();
    final stochasticHigh = stochasticCandles
        .map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final stochasticLow = stochasticCandles
        .map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final stochastic = stochasticHigh > stochasticLow
        ? ((last.close - stochasticLow) /
            (stochasticHigh - stochasticLow)) * 100
        : 50.0;

    double atrTotal = 0;
    for (int i = valid.length - 14; i < valid.length; i++) {
      final candle = valid[i];
      final priorClose = valid[i - 1].close;
      atrTotal += max(
        candle.high - candle.low,
        max((candle.high - priorClose).abs(),
            (candle.low - priorClose).abs()),
      );
    }
    final atr = atrTotal / 14;

    final swingCandles = valid.skip(valid.length - 30).toList();
    final support = swingCandles.map((c) => c.low).reduce(min);
    final resistance = swingCandles.map((c) => c.high).reduce(max);
    final swingRange = resistance - support;

    final body = (last.close - last.open).abs();
    final candleRange = last.high - last.low;
    final upperWick = last.high - (last.open > last.close ? last.open : last.close);
    final lowerWick = (last.open < last.close ? last.open : last.close) - last.low;
    final bullishEngulfing = previous.close < previous.open &&
        last.close > last.open &&
        last.open <= previous.close &&
        last.close >= previous.open;
    final bearishEngulfing = previous.close > previous.open &&
        last.close < last.open &&
        last.open >= previous.close &&
        last.close <= previous.open;
    final hammer = candleRange > 0 &&
        lowerWick >= body * 2 &&
        upperWick <= body &&
        last.close >= last.open;
    final shootingStar = candleRange > 0 &&
        upperWick >= body * 2 &&
        lowerWick <= body &&
        last.close <= last.open;
    final doji = candleRange > 0 && body / candleRange <= 0.1;

    int score = 0;
    final reasons = <String>[];

    if (ema9 > ema21) {
      score++;
      reasons.add('روند کوتاه‌مدت صعودی است');
    } else if (ema9 < ema21) {
      score--;
      reasons.add('روند کوتاه‌مدت نزولی است');
    }

    if (last.close > ema21) {
      score++;
      reasons.add('قیمت بالاتر از میانگین ۲۱ دوره است');
    } else {
      score--;
      reasons.add('قیمت پایین‌تر از میانگین ۲۱ دوره است');
    }

    if (macd > previousMacd) {
      score++;
      reasons.add('مومنتوم MACD در حال تقویت است');
    } else {
      score--;
      reasons.add('مومنتوم MACD در حال تضعیف است');
    }

    if (rsi >= 50 && rsi < 70) {
      score++;
      reasons.add('RSI وضعیت صعودی متعادل دارد');
    } else if (rsi < 50 && rsi > 30) {
      score--;
      reasons.add('RSI وضعیت نزولی دارد');
    } else if (rsi >= 70) {
      reasons.add('RSI در محدوده اشباع خرید است');
    } else {
      reasons.add('RSI در محدوده اشباع فروش است');
    }

    if (last.close > previous.close) {
      score++;
      reasons.add('آخرین کندل نسبت به کندل قبل صعودی است');
    } else if (last.close < previous.close) {
      score--;
      reasons.add('آخرین کندل نسبت به کندل قبل نزولی است');
    }

    if (last.close < bollingerLower) {
      score++;
      reasons.add('قیمت زیر باند پایینی بولینگر است؛ احتمال بازگشت بررسی شود');
    } else if (last.close > bollingerUpper) {
      score--;
      reasons.add('قیمت بالای باند بالایی بولینگر است؛ احتمال اصلاح بررسی شود');
    } else {
      reasons.add('قیمت داخل باندهای بولینگر قرار دارد');
    }

    if (stochastic < 20) {
      score++;
      reasons.add('استوکاستیک در محدوده اشباع فروش است');
    } else if (stochastic > 80) {
      score--;
      reasons.add('استوکاستیک در محدوده اشباع خرید است');
    }

    if (bullishEngulfing || hammer) {
      score++;
      reasons.add(bullishEngulfing
          ? 'الگوی کندلی پوشای صعودی شناسایی شد'
          : 'الگوی چکش صعودی شناسایی شد');
    } else if (bearishEngulfing || shootingStar) {
      score--;
      reasons.add(bearishEngulfing
          ? 'الگوی کندلی پوشای نزولی شناسایی شد'
          : 'الگوی ستاره ثاقب نزولی شناسایی شد');
    } else if (doji) {
      reasons.add('الگوی دوجی؛ بلاتکلیفی بازار');
    }

    if (swingRange > 0) {
      final fib382 = resistance - swingRange * 0.382;
      final fib500 = resistance - swingRange * 0.500;
      final fib618 = resistance - swingRange * 0.618;
      final fibLevels = [fib382, fib500, fib618];
      final nearFib = fibLevels.any((level) =>
          (last.close - level).abs() / last.close <= 0.003);
      if (nearFib) {
        reasons.add('قیمت نزدیک یکی از سطوح اصلاح فیبوناچی ۳۸٫۲، ۵۰ یا ۶۱٫۸٪ است');
      }
      if ((last.close - support).abs() / last.close <= 0.003) {
        reasons.add('قیمت نزدیک حمایت ۳۰ کندل اخیر است');
      } else if ((last.close - resistance).abs() / last.close <= 0.003) {
        reasons.add('قیمت نزدیک مقاومت ۳۰ کندل اخیر است');
      }
    }

    if (atr > 0 && last.close > 0) {
      final volatilityPercent = atr / last.close * 100;
      reasons.add('نوسان ATR: ${volatilityPercent.toStringAsFixed(2)}٪');
    }

    if (newsSentiment > 0) {
      score++;
      reasons.add('جهت کلی تیترهای خبری اخیر مثبت است؛ اثر خبری با وزن محدود لحاظ شد');
    } else if (newsSentiment < 0) {
      score--;
      reasons.add('جهت کلی تیترهای خبری اخیر منفی است؛ اثر خبری با وزن محدود لحاظ شد');
    } else {
      reasons.add('اخبار جهت غالب مشخصی ندارند یا داده خبری کافی نیست');
    }

    final threshold = switch (style) {
      TradingStyle.fast => 2,
      TradingStyle.mediumTerm => 3,
      TradingStyle.longTerm => 4,
    };

    SignalDirection direction = SignalDirection.hold;

    if (score >= threshold) {
      direction = SignalDirection.buy;
    } else if (score <= -threshold) {
      direction = SignalDirection.sell;
    }

    final confidence = direction == SignalDirection.hold
        ? 0.0
        : min(0.95, 0.50 + (score.abs() * 0.07));

    return TradeSignal(
      direction: direction,
      confidence: confidence,
      price: last.close,
      reasons: reasons,
      createdAt: DateTime.now(),
    );
  }
}

// -------------------- RISK MANAGEMENT --------------------

class RiskManager {
  final double riskPerTrade;
  final double maxDailyLoss;
  final double maxDrawdown;

  RiskManager({
    this.riskPerTrade = 0.005,
    this.maxDailyLoss = 0.01,
    this.maxDrawdown = 0.05,
  });

  double calculatePositionSize({
    required double equity,
    required double entryPrice,
    required double stopPrice,
    required double confidence,
  }) {
    if (equity <= 0 ||
        entryPrice <= 0 ||
        stopPrice <= 0 ||
        stopPrice >= entryPrice ||
        confidence <= 0) {
      return 0;
    }

    final confidenceFactor = confidence.clamp(0.0, 1.0);
    // تخصیص متناسب با قدرت سیگنال و حداکثر ۱۰ USDT برای هر معامله.
    final allocation = min(10.0, max(2.0, 10.0 * confidenceFactor));
    final affordableAllocation = min(allocation, equity * 0.95);
    return (affordableAllocation / entryPrice).toDouble();
  }

  bool canTrade({
    required double currentEquity,
    required double dayStartingEquity,
    required double peakEquity,
  }) {
    if (currentEquity <= 0 ||
        dayStartingEquity <= 0 ||
        peakEquity <= 0) {
      return false;
    }

    final dailyLoss =
        (dayStartingEquity - currentEquity) / dayStartingEquity;

    final drawdown = (peakEquity - currentEquity) / peakEquity;

    return dailyLoss < maxDailyLoss && drawdown < maxDrawdown;
  }
}

// -------------------- POSITION --------------------

class PaperPosition {
  final String symbol;
  double quantity;
  double averageEntryPrice;
  final double allocatedUsdt;
  final DateTime openedAt;
  double stopPrice;
  final double targetPrice;
  double highestPrice;
  double trailingStop;

  PaperPosition({
    required this.symbol,
    required this.quantity,
    required this.averageEntryPrice,
    required this.allocatedUsdt,
    required this.openedAt,
    required this.stopPrice,
    required this.targetPrice,
    required this.highestPrice,
    this.trailingStop = 0,
  });

  double marketValue(double price) => quantity * price;

  double unrealizedPnl(double price) =>
      (price - averageEntryPrice) * quantity;
}

// -------------------- TRADE RECORD --------------------

class PaperFill {
  final String id;
  final String symbol;
  final SignalDirection side;
  final double price;
  final double quantity;
  final double fee;
  final double realizedPnl;
  final DateTime time;
  final double? entryPrice;
  final double? allocatedUsdt;
  final String? exitReason;
  final DateTime? openedAt;
  final Duration? holdingDuration;

  const PaperFill({
    required this.id,
    required this.symbol,
    required this.side,
    required this.price,
    required this.quantity,
    required this.fee,
    required this.realizedPnl,
    required this.time,
    this.entryPrice,
    this.allocatedUsdt,
    this.exitReason,
    this.openedAt,
    this.holdingDuration,
  });
}

// -------------------- PAPER PORTFOLIO --------------------

class PaperPortfolio {
  final double initialUsdt;
  final double feeRate;

  double cashUsdt;
  double peakEquity;
  double dayStartingEquity;
  DateTime _currentDay;

  final Map<String, PaperPosition> positions = {};
  final List<PaperFill> fills = [];

  PaperPortfolio({
    this.initialUsdt = 100,
    this.feeRate = 0.001,
  })  : cashUsdt = initialUsdt,
        peakEquity = initialUsdt,
        dayStartingEquity = initialUsdt,
        _currentDay = DateTime.now();

  double get realizedPnl =>
      fills.fold(0.0, (sum, fill) => sum + fill.realizedPnl);

  double get totalFees =>
      fills.fold(0.0, (sum, fill) => sum + fill.fee);

  double unrealizedPnl(Map<String, double> prices) {
    double result = 0;

    for (final entry in positions.entries) {
      final price = prices[entry.key];
      if (price != null && price > 0) {
        result += entry.value.unrealizedPnl(price);
      }
    }

    return result;
  }

  double equity(Map<String, double> prices) {
    double result = cashUsdt;

    for (final entry in positions.entries) {
      final price = prices[entry.key];
      if (price != null && price > 0) {
        result += entry.value.marketValue(price);
      }
    }

    return result;
  }

  double updateEquity(Map<String, double> prices) {
    final value = equity(prices);

    if (value > peakEquity) {
      peakEquity = value;
    }

    final now = DateTime.now();

    if (now.year != _currentDay.year ||
        now.month != _currentDay.month ||
        now.day != _currentDay.day) {
      _currentDay = now;
      dayStartingEquity = value;
    }

    return value;
  }

  bool buy({
    required String symbol,
    required double price,
    required double quantity,
    double? allocatedUsdt,
    double stopLossPercent = defaultStopLossPercent,
    double takeProfitPercent = defaultTakeProfitPercent,
  }) {
    if (symbol.isEmpty ||
        price <= 0 ||
        quantity <= 0 ||
        !price.isFinite ||
        !quantity.isFinite) {
      return false;
    }

    final cost = price * quantity;
    final fee = cost * feeRate;
    final total = cost + fee;

    if (total > cashUsdt) return false;

    cashUsdt -= total;

    final existing = positions[symbol];

    if (existing == null) {
      final effectiveEntry = (cost + fee) / quantity;
      positions[symbol] = PaperPosition(
        symbol: symbol,
        quantity: quantity,
        averageEntryPrice: effectiveEntry,
        allocatedUsdt: allocatedUsdt ?? total,
        openedAt: DateTime.now(),
        stopPrice: effectiveEntry * (1 - stopLossPercent),
        targetPrice: effectiveEntry * (1 + takeProfitPercent),
        highestPrice: effectiveEntry,
      );
    } else {
      final newQuantity = existing.quantity + quantity;
      existing.averageEntryPrice =
          ((existing.averageEntryPrice * existing.quantity) + cost + fee) /
              newQuantity;
      existing.quantity = newQuantity;
    }

    fills.add(PaperFill(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      symbol: symbol,
      side: SignalDirection.buy,
      price: price,
      quantity: quantity,
      fee: fee,
      realizedPnl: 0,
      time: DateTime.now(),
    ));

    return true;
  }

  bool sell({
    required String symbol,
    required double price,
    required double quantity,
    String exitReason = 'خروج با سیگنال',
  }) {
    if (symbol.isEmpty ||
        price <= 0 ||
        quantity <= 0 ||
        !price.isFinite ||
        !quantity.isFinite) {
      return false;
    }

    final position = positions[symbol];

    if (position == null || quantity > position.quantity) {
      return false;
    }

    final gross = price * quantity;
    final fee = gross * feeRate;
    final proceeds = gross - fee;

    final costBasis = position.averageEntryPrice * quantity;
    final pnl = proceeds - costBasis;

    cashUsdt += proceeds;
    position.quantity -= quantity;

    if (position.quantity <= 0.00000001) {
      positions.remove(symbol);
    }

    fills.add(PaperFill(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      symbol: symbol,
      side: SignalDirection.sell,
      price: price,
      quantity: quantity,
      fee: fee,
      realizedPnl: pnl,
      time: DateTime.now(),
      entryPrice: position.averageEntryPrice,
      allocatedUsdt: position.allocatedUsdt,
      exitReason: exitReason,
      openedAt: position.openedAt,
      holdingDuration: DateTime.now().difference(position.openedAt),
    ));

    return true;
  }

  void reset() {
    cashUsdt = initialUsdt;
    peakEquity = initialUsdt;
    dayStartingEquity = initialUsdt;
    _currentDay = DateTime.now();
    positions.clear();
    fills.clear();
  }
}

// -------------------- LIVE TRADING SAFETY --------------------

class LiveTradingGuard {
  LiveTradingGuard._();

  // سفارش واقعی تا زمان تکمیل اتصال امن و تأیید کاربر غیرفعال است.
  static const bool enabled = false;

  static bool canSubmitRealOrder() => enabled;
}
