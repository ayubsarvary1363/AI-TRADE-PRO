
import 'dart:math';

// =====================================================
// AI TRADE PRO
// Trading Engine Foundation - Version 0.5.0
// Paper trading enabled | Live trading locked
// Spot only | No leverage | No short selling
// =====================================================

enum TradeMode { paper, live }

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
  double _sma(List<double> values, int period) {
    if (values.length < period) return 0;
    final slice = values.sublist(values.length - period);
    return slice.reduce((a, b) => a + b) / period;
  }

  double _ema(List<double> values, int period) {
    if (values.length < period) return 0;
    final multiplier = 2 / (period + 1);
    double result = _sma(values.take(period).toList(), period);
    for (final value in values.skip(period)) {
      result += (value - result) * multiplier;
    }
    return result;
  }

  double _rsi(List<double> values, int period) {
    if (values.length <= period) return 50;
    double gains = 0, losses = 0;
    for (int i = values.length - period; i < values.length; i++) {
      final change = values[i] - values[i - 1];
      if (change > 0) { gains += change; } else { losses += change.abs(); }
    }
    if (losses == 0) return gains == 0 ? 50 : 100;
    if (gains == 0) return 0;
    final rs = (gains / period) / (losses / period);
    return 100 - (100 / (1 + rs));
  }

  double _stdDev(List<double> values, int period) {
    if (values.length < period) return 0;
    final sample = values.sublist(values.length - period);
    final mean = sample.reduce((a, b) => a + b) / period;
    final variance = sample.fold<double>(0,
      (sum, value) => sum + (value - mean) * (value - mean)) / period;
    return sqrt(variance);
  }

  double _atr(List<Candle> data, int period) {
    if (data.length < period + 1) return 0;
    double total = 0;
    for (int i = data.length - period; i < data.length; i++) {
      final c = data[i], previousClose = data[i - 1].close;
      total += [c.high - c.low, (c.high - previousClose).abs(),
        (c.low - previousClose).abs()].reduce((a, b) => a > b ? a : b);
    }
    return total / period;
  }

  double _adx(List<Candle> data, int period) {
    if (data.length < period * 2 + 1) return 0;
    double dxTotal = 0;
    int samples = 0;
    for (int end = data.length - period; end < data.length; end++) {
      final start = end - period + 1;
      double trSum = 0, plusSum = 0, minusSum = 0;
      for (int i = start; i <= end; i++) {
        final current = data[i], previous = data[i - 1];
        final up = current.high - previous.high;
        final down = previous.low - current.low;
        plusSum += up > down && up > 0 ? up : 0;
        minusSum += down > up && down > 0 ? down : 0;
        trSum += [current.high - current.low,
          (current.high - previous.close).abs(),
          (current.low - previous.close).abs()]
          .reduce((x, y) => x > y ? x : y);
      }
      if (trSum <= 0) continue;
      final plusDi = 100 * plusSum / trSum;
      final minusDi = 100 * minusSum / trSum;
      final total = plusDi + minusDi;
      if (total > 0) {
        dxTotal += 100 * (plusDi - minusDi).abs() / total;
        samples++;
      }
    }
    return samples == 0 ? 0 : dxTotal / samples;
  }

  double _superTrendDirection(List<Candle> data, {
    int period = 10, double multiplier = 3,
  }) {
    if (data.length < period + 2) return 0;
    double finalUpper = 0, finalLower = 0;
    int direction = 1;
    for (int i = period; i < data.length; i++) {
      final current = data[i], previous = data[i - 1];
      double trSum = 0;
      for (int j = i - period + 1; j <= i; j++) {
        final candle = data[j], priorClose = data[j - 1].close;
        trSum += [candle.high - candle.low,
          (candle.high - priorClose).abs(),
          (candle.low - priorClose).abs()]
          .reduce((x, y) => x > y ? x : y);
      }
      final atrValue = trSum / period;
      final hl2 = (current.high + current.low) / 2;
      final basicUpper = hl2 + multiplier * atrValue;
      final basicLower = hl2 - multiplier * atrValue;
      if (i == period) {
        finalUpper = basicUpper;
        finalLower = basicLower;
        direction = current.close >= hl2 ? 1 : -1;
        continue;
      }
      final priorUpper = finalUpper;
      final priorLower = finalLower;
      finalUpper = basicUpper < priorUpper || previous.close > priorUpper
          ? basicUpper : priorUpper;
      finalLower = basicLower > priorLower || previous.close < priorLower
          ? basicLower : priorLower;
      if (direction < 0 && current.close > finalUpper) {
        direction = 1;
      } else if (direction > 0 && current.close < finalLower) {
        direction = -1;
      }
    }
    return direction.toDouble();
  }

  double _aroonOscillator(List<Candle> data, int period) {
    if (data.length < period) return 0;
    final sample = data.sublist(data.length - period);
    int hi = 0, lo = 0;
    for (int i = 1; i < sample.length; i++) {
      if (sample[i].high >= sample[hi].high) hi = i;
      if (sample[i].low <= sample[lo].low) lo = i;
    }
    return 100 * (hi - lo) / (period - 1);
  }

  double _accumulationDistribution(List<Candle> data, int period) {
    if (data.length < period) return 0;
    double ad = 0;
    for (final c in data.skip(data.length - period)) {
      final range = c.high - c.low;
      if (range <= 0 || c.volume <= 0) continue;
      ad += (((c.close - c.low) - (c.high - c.close)) / range) * c.volume;
    }
    return ad;
  }

  double _vwap(List<Candle> data, int period) {
    if (data.length < period) return 0;
    double pv = 0, volume = 0;
    for (final c in data.skip(data.length - period)) {
      if (c.volume <= 0) continue;
      pv += ((c.high + c.low + c.close) / 3) * c.volume;
      volume += c.volume;
    }
    return volume > 0 ? pv / volume : 0;
  }

  double _stochasticRsi(List<double> values, int rsiPeriod, int stochPeriod) {
    if (values.length < rsiPeriod + stochPeriod + 1) return 50;
    final rsiValues = <double>[];
    for (int i = values.length - stochPeriod - rsiPeriod;
        i < values.length; i++) {
      rsiValues.add(_rsi(values.sublist(0, i + 1), rsiPeriod));
    }
    final window = rsiValues.sublist(rsiValues.length - stochPeriod);
    final low = window.reduce(min), high = window.reduce((a, b) => a > b ? a : b);
    if ((high - low).abs() < 1e-12) return 50;
    return 100 * (window.last - low) / (high - low);
  }

  TradeSignal analyze(List<Candle> candles, {
    TradingStyle style = TradingStyle.mediumTerm,
  }) {
    final valid = candles.where((c) => c.isValid).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    if (valid.length < 60) {
      return TradeSignal(
        direction: SignalDirection.hold, confidence: 0,
        price: valid.isEmpty ? 0 : valid.last.close,
        reasons: ['برای تحلیل چنداندیکاتوری حداقل ۶۰ کندل معتبر لازم است'],
        createdAt: DateTime.now(),
      );
    }

    final closes = valid.map((c) => c.close).toList();
    final last = valid.last, previous = valid[valid.length - 2];
    final sma20 = _sma(closes, 20), sma50 = _sma(closes, 50);
    final ema9 = _ema(closes, 9), ema21 = _ema(closes, 21);
    final macd = _ema(closes, 12) - _ema(closes, 26);
    final oldCloses = closes.sublist(0, closes.length - 1);
    final oldMacd = _ema(oldCloses, 12) - _ema(oldCloses, 26);
    final rsi = _rsi(closes, 14), adx = _adx(valid, 14);
    final aroon = _aroonOscillator(valid, 25);
    final ad = _accumulationDistribution(valid, 20);
    final oldAd = _accumulationDistribution(valid.sublist(0, valid.length - 1), 20);
    final deviation = _stdDev(closes, 20);
    final zScore = deviation > 0 ? (last.close - sma20) / deviation : 0.0;
    final upper = sma20 + 2 * deviation, lower = sma20 - 2 * deviation;
    final atr = _atr(valid, 14), vwap = _vwap(valid, 20);
    final stochRsi = _stochasticRsi(closes, 14, 14);

    double midpoint(int period) {
      final sample = valid.sublist(valid.length - period);
      return (sample.map((c) => c.high).reduce((a, b) => a > b ? a : b) +
        sample.map((c) => c.low).reduce(min)) / 2;
    }
    final tenkan = midpoint(9), kijun = midpoint(26);
    final spanA = (tenkan + kijun) / 2, spanB = midpoint(52);
    final superTrendDirection = _superTrendDirection(valid);

    int score = 0;
    final reasons = <String>[];
    void vote(int value, String reason) {
      score += value;
      reasons.add(reason);
    }

    if (last.close > sma20 && sma20 > sma50) {
      vote(2, 'SMA20 بالاتر از SMA50 و قیمت بالای هر دو است');
    } else if (last.close < sma20 && sma20 < sma50) {
      vote(-2, 'SMA20 پایین‌تر از SMA50 و قیمت زیر هر دو است');
    }
    if (ema9 > ema21) {
      vote(1, 'EMA9 بالاتر از EMA21 است');
    } else if (ema9 < ema21) {
      vote(-1, 'EMA9 پایین‌تر از EMA21 است');
    }
    if (macd > oldMacd && macd > 0) {
      vote(1, 'MACD مثبت و رو به تقویت است');
    } else if (macd < oldMacd && macd < 0) {
      vote(-1, 'MACD منفی و رو به تضعیف است');
    }
    if (rsi >= 52 && rsi < 70) {
      vote(1, 'RSI مومنتوم صعودی دارد');
    } else if (rsi <= 48 && rsi > 30) {
      vote(-1, 'RSI مومنتوم نزولی دارد');
    } else if (rsi >= 70 || rsi <= 30) {
      reasons.add('RSI در محدوده اشباع است؛ ورود با احتیاط');
    }
    if (adx >= 20) {
      if (last.close > sma20) {
        vote(1, 'ADX قدرت روند صعودی را تأیید می‌کند');
      } else if (last.close < sma20) {
        vote(-1, 'ADX قدرت روند نزولی را تأیید می‌کند');
      }
    } else {
      reasons.add('ADX روند قدرتمندی نشان نمی‌دهد');
    }
    if (aroon > 25) {
      vote(1, 'Aroon برتری روند صعودی را نشان می‌دهد');
    } else if (aroon < -25) {
      vote(-1, 'Aroon برتری روند نزولی را نشان می‌دهد');
    }
    if (ad > oldAd && ad > 0) {
      vote(1, 'خط A/D افزایش فشار انباشت را نشان می‌دهد');
    } else if (ad < oldAd && ad < 0) {
      vote(-1, 'خط A/D افزایش فشار توزیع را نشان می‌دهد');
    } else {
      reasons.add('A/D: حجم معتبر یا جهت روشنی وجود ندارد');
    }
    if (zScore < -1.5 && last.close < lower) {
      vote(1, 'Mean Reversion احتمال بازگشت از محدوده پایین را نشان می‌دهد');
    } else if (zScore > 1.5 && last.close > upper) {
      vote(-1, 'Mean Reversion احتمال بازگشت از محدوده بالا را نشان می‌دهد');
    }
    if (last.close <= lower) {
      vote(1, 'قیمت به باند پایینی بولینگر رسیده است');
    } else if (last.close >= upper) {
      vote(-1, 'قیمت به باند بالایی بولینگر رسیده است');
    }
    if (vwap > 0 && last.close > vwap) {
      vote(1, 'قیمت بالاتر از VWAP است');
    } else if (vwap > 0 && last.close < vwap) {
      vote(-1, 'قیمت پایین‌تر از VWAP است');
    } else {
      reasons.add('VWAP به دلیل نبود حجم معتبر قابل اتکا نیست');
    }
    if (superTrendDirection > 0) {
      vote(1, 'SuperTrend جهت صعودی را تأیید می‌کند');
    } else if (superTrendDirection < 0) {
      vote(-1, 'SuperTrend جهت نزولی را تأیید می‌کند');
    }
    if (last.close > spanA && last.close > spanB && tenkan > kijun) {
      vote(1, 'ابر ایچیموکو روند صعودی را تأیید می‌کند');
    } else if (last.close < spanA && last.close < spanB && tenkan < kijun) {
      vote(-1, 'ابر ایچیموکو روند نزولی را تأیید می‌کند');
    }
    if (stochRsi < 20 && last.close > previous.close) {
      vote(1, 'Stochastic RSI از اشباع فروش رو به بالا برگشته است');
    } else if (stochRsi > 80 && last.close < previous.close) {
      vote(-1, 'Stochastic RSI از اشباع خرید رو به پایین برگشته است');
    }
    if (deviation > 0) {
      reasons.add('انحراف معیار نوسان: ' + deviation.toStringAsPrecision(5));
    }
    if (atr > 0) reasons.add('ATR برای تنظیم فاصله حد ضرر و حد سود محاسبه شد');

    final threshold = switch (style) {
      TradingStyle.fast => 2,
      TradingStyle.mediumTerm => 4,
      TradingStyle.longTerm => 6,
    };
    SignalDirection direction = SignalDirection.hold;
    if (score >= threshold) {
      direction = SignalDirection.buy;
    } else if (score <= -threshold) {
      direction = SignalDirection.sell;
    }
    // Rule-confluence score, not a statistically calibrated profit probability.
    final confidence = direction == SignalDirection.hold
      ? 0.0 : min(0.95, 0.50 + score.abs() / 16.0);
    return TradeSignal(
      direction: direction, confidence: confidence, price: last.close,
      reasons: reasons, createdAt: DateTime.now(),
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

    final riskAmount = equity * riskPerTrade;
    final riskPerUnit = entryPrice - stopPrice;

    final confidenceFactor = confidence.clamp(0.0, 1.0);
    final quantity = (riskAmount / riskPerUnit) * confidenceFactor;

    // سقف ارزش معامله: ۲۵ درصد موجودی
    final maximumQuantity = (equity * 0.25) / entryPrice;

    return min(quantity, maximumQuantity).toDouble();
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

  PaperPosition({
    required this.symbol,
    required this.quantity,
    required this.averageEntryPrice,
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
  final double? stopLoss;
  final double? takeProfit;
  final double? targetPoints;
  final DateTime time;

  const PaperFill({
    required this.id,
    required this.symbol,
    required this.side,
    required this.price,
    required this.quantity,
    required this.fee,
    required this.realizedPnl,
    this.stopLoss,
    this.takeProfit,
    this.targetPoints,
    required this.time,
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
    this.initialUsdt = 50,
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
    double? stopLoss,
    double? takeProfit,
    double? targetPoints,
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
      positions[symbol] = PaperPosition(
        symbol: symbol,
        quantity: quantity,
        averageEntryPrice: (cost + fee) / quantity,
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
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      targetPoints: targetPoints,
      time: DateTime.now(),
    ));

    return true;
  }

  bool sell({
    required String symbol,
    required double price,
    required double quantity,
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
