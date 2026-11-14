
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
    double gains = 0, losses = 0;
    for (int i = values.length - period; i < values.length; i++) {
      final change = values[i] - values[i - 1];
      if (change > 0) { gains += change; } else { losses += change.abs(); }
    }
    if (losses == 0) return 100;
    if (gains == 0) return 0;
    final rs = (gains / period) / (losses / period);
    return 100 - (100 / (1 + rs));
  }

  double _average(List<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  TradeSignal analyze(
    List<Candle> candles, {
    TradingStyle style = TradingStyle.mediumTerm,
  }) {
    final data = candles.where((c) => c.isValid).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    if (data.length < 50) {
      return TradeSignal(
        direction: SignalDirection.hold,
        confidence: 0,
        price: data.isEmpty ? 0 : data.last.close,
        reasons: ['برای تحلیل چندلایه حداقل ۵۰ کندل معتبر لازم است'],
        createdAt: DateTime.now(),
      );
    }

    final closes = data.map((c) => c.close).toList();
    final last = data.last;
    final prev = data[data.length - 2];
    final ema9 = _ema(closes, 9);
    final ema21 = _ema(closes, 21);
    final ema50 = _ema(closes, 50);
    final ema200 = closes.length >= 200 ? _ema(closes, 200) : ema50;
    final ema12 = _ema(closes, 12);
    final ema26 = _ema(closes, 26);
    final previousCloses = closes.sublist(0, closes.length - 1);
    final macd = ema12 - ema26;
    final previousMacd = _ema(previousCloses, 12) - _ema(previousCloses, 26);
    final rsi = _rsi(closes, 14);

    final recent = data.sublist(data.length - 20, data.length - 1);
    final resistance = recent.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final support = recent.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final averageVolume = _average(data.skip(data.length - 21).take(20).map((c) => c.volume).toList());
    final volumeConfirmed = averageVolume <= 0 || last.volume >= averageVolume * 1.15;

    int score = 0;
    final reasons = <String>[];

    // Trend stack: EMA alignment and price position.
    if (ema9 > ema21 && ema21 > ema50) {
      score += 2;
      reasons.add('چیدمان EMA9/21/50 روند صعودی چندمرحله‌ای را تأیید می‌کند');
    } else if (ema9 < ema21 && ema21 < ema50) {
      score -= 2;
      reasons.add('چیدمان EMA9/21/50 روند نزولی چندمرحله‌ای را تأیید می‌کند');
    } else {
      reasons.add('میانگین‌های متحرک هم‌جهت نیستند؛ روند نیازمند تأیید است');
    }
    if (last.close > ema200) {
      score++;
      reasons.add('قیمت بالاتر از EMA200 است');
    } else {
      score--;
      reasons.add('قیمت پایین‌تر از EMA200 است');
    }

    // MACD momentum and RSI regime.
    if (macd > previousMacd && macd > 0) {
      score++;
      reasons.add('مومنتوم MACD صعودی و در حال تقویت است');
    } else if (macd < previousMacd && macd < 0) {
      score--;
      reasons.add('مومنتوم MACD نزولی و در حال تضعیف است');
    }
    if (rsi >= 52 && rsi < 70) {
      score++;
      reasons.add('RSI از مومنتوم مثبت بدون اشباع شدید حمایت می‌کند');
    } else if (rsi <= 48 && rsi > 30) {
      score--;
      reasons.add('RSI مومنتوم منفی را نشان می‌دهد');
    } else if (rsi >= 70) {
      reasons.add('RSI در اشباع خرید است؛ از تعقیب قیمت پرهیز شود');
    } else if (rsi <= 30) {
      reasons.add('RSI در اشباع فروش است؛ احتمال برگشت نیازمند تأیید است');
    }

    // Price action: engulfing, hammer and shooting-star approximations.
    final body = (last.close - last.open).abs();
    final range = max(last.high - last.low, 0.000000001);
    final lowerWick = min(last.open, last.close) - last.low;
    final upperWick = last.high - max(last.open, last.close);
    final bullishEngulfing = prev.close < prev.open &&
        last.close > last.open && last.open <= prev.close && last.close >= prev.open;
    final bearishEngulfing = prev.close > prev.open &&
        last.close < last.open && last.open >= prev.close && last.close <= prev.open;
    final hammer = lowerWick >= body * 2 && upperWick <= body && last.close > last.open;
    final shootingStar = upperWick >= body * 2 && lowerWick <= body && last.close < last.open;
    if (bullishEngulfing || hammer) {
      score++;
      reasons.add(bullishEngulfing ? 'الگوی کندلی پوشای صعودی شناسایی شد' : 'الگوی چکش صعودی شناسایی شد');
    }
    if (bearishEngulfing || shootingStar) {
      score--;
      reasons.add(bearishEngulfing ? 'الگوی کندلی پوشای نزولی شناسایی شد' : 'الگوی ستاره ثاقب نزولی شناسایی شد');
    }
    if (body / range < 0.1) {
      reasons.add('کندل دوجی و تردید بازار مشاهده شد');
    }

    // Support/resistance breakout and volume confirmation.
    if (last.close > resistance && volumeConfirmed) {
      score += 2;
      reasons.add('شکست مقاومت ۲۰ کندل اخیر با تأیید حجم رخ داده است');
    } else if (last.close < support && volumeConfirmed) {
      score -= 2;
      reasons.add('شکست حمایت ۲۰ کندل اخیر با تأیید حجم رخ داده است');
    } else if ((last.close - support).abs() / last.close < 0.003) {
      reasons.add('قیمت نزدیک ناحیه حمایت اخیر است');
    } else if ((resistance - last.close).abs() / last.close < 0.003) {
      reasons.add('قیمت نزدیک ناحیه مقاومت اخیر است');
    }
    if (averageVolume > 0 && !volumeConfirmed) {
      reasons.add('حجم معاملات شکست یا حرکت اخیر را تأیید نمی‌کند');
    }

    // Simple double-top / double-bottom detection from recent swing points.
    final pivotsHigh = <double>[];
    final pivotsLow = <double>[];
    final pivotStart = max(1, data.length - 35).toInt();
    for (int i = pivotStart; i < data.length - 1; i++) {
      if (data[i].high >= data[i - 1].high && data[i].high >= data[i + 1].high) {
        pivotsHigh.add(data[i].high);
      }
      if (data[i].low <= data[i - 1].low && data[i].low <= data[i + 1].low) {
        pivotsLow.add(data[i].low);
      }
    }
    if (pivotsHigh.length >= 2) {
      final x = pivotsHigh[pivotsHigh.length - 1];
      final y = pivotsHigh[pivotsHigh.length - 2];
      if ((x - y).abs() / max(x, y) < 0.004 && last.close < min(x, y)) {
        score--;
        reasons.add('احتمال سقف دوقلو در ناحیه مقاومت دیده می‌شود');
      }
    }
    if (pivotsLow.length >= 2) {
      final x = pivotsLow[pivotsLow.length - 1];
      final y = pivotsLow[pivotsLow.length - 2];
      if ((x - y).abs() / max(x, y) < 0.004 && last.close > max(x, y)) {
        score++;
        reasons.add('احتمال کف دوقلو در ناحیه حمایت دیده می‌شود');
      }
    }

    // Head-and-shoulders / inverse head-and-shoulders approximation.
    if (pivotsHigh.length >= 3) {
      final left = pivotsHigh[pivotsHigh.length - 3];
      final head = pivotsHigh[pivotsHigh.length - 2];
      final right = pivotsHigh[pivotsHigh.length - 1];
      final shouldersClose = (left - right).abs() / max(left, right) < 0.012;
      if (head > left * 1.005 && head > right * 1.005 &&
          shouldersClose && last.close < support) {
        score -= 2;
        reasons.add('ساختار احتمالی سر و شانه با شکست ناحیه گردن دیده شد');
      }
    }
    if (pivotsLow.length >= 3) {
      final left = pivotsLow[pivotsLow.length - 3];
      final head = pivotsLow[pivotsLow.length - 2];
      final right = pivotsLow[pivotsLow.length - 1];
      final shouldersClose = (left - right).abs() / max(left, right) < 0.012;
      if (head < left * 0.995 && head < right * 0.995 &&
          shouldersClose && last.close > resistance) {
        score += 2;
        reasons.add('ساختار احتمالی سر و شانه معکوس با شکست مقاومت دیده شد');
      }
    }

    // Contracting range: lower highs + higher lows, then directional breakout.
    final recentTen = data.sublist(data.length - 11, data.length - 1);
    final firstHalf = recentTen.take(5).toList();
    final secondHalf = recentTen.skip(5).toList();
    final firstHigh = firstHalf.map((c) => c.high).reduce((a, b) => a + b) / 5;
    final secondHigh = secondHalf.map((c) => c.high).reduce((a, b) => a + b) / 5;
    final firstLow = firstHalf.map((c) => c.low).reduce((a, b) => a + b) / 5;
    final secondLow = secondHalf.map((c) => c.low).reduce((a, b) => a + b) / 5;
    final contracting = secondHigh < firstHigh && secondLow > firstLow;
    if (contracting && last.close > resistance) {
      score += 2;
      reasons.add('الگوی فشردگی مثلثی و شکست صعودی محدوده تشخیص داده شد');
    } else if (contracting && last.close < support) {
      score -= 2;
      reasons.add('الگوی فشردگی مثلثی و شکست نزولی محدوده تشخیص داده شد');
    }

    final threshold = switch (style) {
      TradingStyle.fast => 3,
      TradingStyle.mediumTerm => 4,
      TradingStyle.longTerm => 5,
    };
    SignalDirection direction = SignalDirection.hold;
    if (score >= threshold) {
      direction = SignalDirection.buy;
    } else if (score <= -threshold) {
      direction = SignalDirection.sell;
    }
    final confidence = direction == SignalDirection.hold
        ? 0.0
        : min(0.95, 0.50 + (score.abs() * 0.045)).toDouble();
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
  final DateTime time;

  const PaperFill({
    required this.id,
    required this.symbol,
    required this.side,
    required this.price,
    required this.quantity,
    required this.fee,
    required this.realizedPnl,
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
