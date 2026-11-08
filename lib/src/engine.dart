
import 'dart:math';

// ============================================================
// AI TRADE PRO - Trading Engine 0.5.0
// Secure architecture - Paper trading enabled
// Live order execution intentionally disabled until integration
// ============================================================

enum TradeMode { paper, live }

enum SignalDirection { buy, sell, hold }

enum TradingStyle { fast, medium, longTerm }

enum MarketType { crypto, forex, stocks, commodities, indices }

enum OrderSide { buy, sell }

// ======================== CANDLE ==============================

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
    required this.volume,
  });

  bool get isValid =>
      open.isFinite &&
      high.isFinite &&
      low.isFinite &&
      close.isFinite &&
      volume.isFinite &&
      open > 0 &&
      high >= low &&
      high >= open &&
      high >= close &&
      low <= open &&
      low <= close &&
      close > 0 &&
      volume >= 0;
}

// ======================== SIGNAL ==============================

class TradeSignal {
  final String symbol;
  final SignalDirection direction;
  final double confidence;
  final double price;
  final DateTime createdAt;
  final List<String> reasons;

  const TradeSignal({
    required this.symbol,
    required this.direction,
    required this.confidence,
    required this.price,
    required this.createdAt,
    required this.reasons,
  });
}

// ===================== TECHNICAL ANALYSIS =====================

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

  TradeSignal analyze({
    required String symbol,
    required List<Candle> candles,
    TradingStyle style = TradingStyle.medium,
  }) {
    final valid = candles.where((c) => c.isValid).toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    final requiredCount = style == TradingStyle.fast ? 30 : 50;

    if (valid.length < requiredCount) {
      return _hold(symbol, valid.isEmpty ? 0 : valid.last.close,
          'داده کافی برای تحلیل وجود ندارد.');
    }

    final closes = valid.map((c) => c.close).toList();
    final price = closes.last;

    if (price <= 0 || !price.isFinite) {
      return _hold(symbol, 0, 'قیمت معتبر نیست.');
    }

    final shortPeriod = style == TradingStyle.fast ? 5 : 9;
    final longPeriod = style == TradingStyle.fast ? 13 : 21;

    final fastEma = _ema(closes, shortPeriod);
    final slowEma = _ema(closes, longPeriod);
    final rsi = _rsi(closes, 14);

    final ema12 = _ema(closes, 12);
    final ema26 = _ema(closes, 26);
    final macd = ema12 - ema26;

    final recentVolume = valid.skip(valid.length - 10)
        .map((c) => c.volume)
        .reduce((a, b) => a + b) / 10;

    final previousVolume = valid.skip(valid.length - 20)
        .take(10)
        .map((c) => c.volume)
        .reduce((a, b) => a + b) / 10;

    int score = 0;
    final reasons = <String>[];

    if (fastEma > slowEma) {
      score++;
      reasons.add('روند میانگین‌های متحرک صعودی است.');
    } else if (fastEma < slowEma) {
      score--;
      reasons.add('روند میانگین‌های متحرک نزولی است.');
    }

    if (rsi < 30) {
      score++;
      reasons.add('شاخص RSI در محدوده اشباع فروش است.');
    } else if (rsi > 70) {
      score--;
      reasons.add('شاخص RSI در محدوده اشباع خرید است.');
    }

    if (macd > 0) {
      score++;
      reasons.add('مومنتوم MACD مثبت است.');
    } else if (macd < 0) {
      score--;
      reasons.add('مومنتوم MACD منفی است.');
    }

    if (recentVolume > previousVolume && recentVolume > 0) {
      reasons.add('حجم معاملات نسبت به دوره قبل افزایش یافته است.');
    }

    final direction = score >= 2
        ? SignalDirection.buy
        : score <= -2
            ? SignalDirection.sell
            : SignalDirection.hold;

    final confidence = (50 + score.abs() * 12.0).clamp(0.0, 90.0);

    return TradeSignal(
      symbol: symbol,
      direction: direction,
      confidence: confidence,
      price: price,
      createdAt: DateTime.now().toUtc(),
      reasons: reasons,
    );
  }

  TradeSignal _hold(String symbol, double price, String reason) {
    return TradeSignal(
      symbol: symbol,
      direction: SignalDirection.hold,
      confidence: 0,
      price: price,
      createdAt: DateTime.now().toUtc(),
      reasons: [reason],
    );
  }
}

// ======================== RISK MANAGER ========================

class RiskManager {
  final double riskPerTrade;
  final double maxDailyLoss;
  final double maxDrawdown;

  double dailyStartEquity = 50;
  double peakEquity = 50;

  RiskManager({
    this.riskPerTrade = 0.005,
    this.maxDailyLoss = 0.01,
    this.maxDrawdown = 0.05,
  });

  void updateEquity(double equity) {
    if (!equity.isFinite || equity < 0) return;

    if (equity > peakEquity) {
      peakEquity = equity;
    }
  }

  void resetDaily(double equity) {
    if (equity.isFinite && equity > 0) {
      dailyStartEquity = equity;
    }
  }

  bool get dailyLossReached =>
      dailyStartEquity > 0 &&
      (dailyStartEquity - peakEquity) / dailyStartEquity >= maxDailyLoss;

  bool drawdownReached(double equity) {
    if (peakEquity <= 0 || !equity.isFinite) return true;

    return (peakEquity - equity) / peakEquity >= maxDrawdown;
  }

  double calculateQuantity({
    required double equity,
    required double entryPrice,
    required double stopPrice,
    required double confidence,
  }) {
    if (!equity.isFinite ||
        !entryPrice.isFinite ||
        !stopPrice.isFinite ||
        !confidence.isFinite ||
        equity <= 0 ||
        entryPrice <= 0 ||
        stopPrice <= 0 ||
        stopPrice >= entryPrice ||
        confidence < 60) {
      return 0;
    }

    final riskAmount = equity * riskPerTrade;
    final riskPerUnit = entryPrice - stopPrice;

    if (riskPerUnit <= 0) return 0;

    final confidenceFactor = (confidence / 90).clamp(0.0, 1.0);
    final riskAdjusted = riskAmount * confidenceFactor;

    return riskAdjusted / riskPerUnit;
  }

  bool canTrade(double equity) {
    if (!equity.isFinite || equity <= 0) return false;
    if (dailyLossReached) return false;
    if (drawdownReached(equity)) return false;
    return true;
  }
}

// ======================== PAPER POSITION ======================

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
}

// ======================== PAPER FILL ==========================

class PaperFill {
  final String symbol;
  final OrderSide side;
  final double price;
  final double quantity;
  final double fee;
  final double realizedPnl;
  final DateTime time;

  const PaperFill({
    required this.symbol,
    required this.side,
    required this.price,
    required this.quantity,
    required this.fee,
    required this.realizedPnl,
    required this.time,
  });
}

// ======================== PAPER PORTFOLIO =====================

class PaperPortfolio {
  final double initialUsdt;
  final double feeRate;

  double cash;
  double realizedPnl = 0;
  double peakEquity;
  final Map<String, PaperPosition> positions = {};
  final List<PaperFill> fills = [];

  PaperPortfolio({
    this.initialUsdt = 50,
    this.feeRate = 0.001,
  })  : cash = initialUsdt,
        peakEquity = initialUsdt;

  double get totalFees =>
      fills.fold(0.0, (total, fill) => total + fill.fee);

  double get totalRealizedPnl => realizedPnl;

  double get equity {
    double total = cash;

    for (final position in positions.values) {
      total += position.quantity * position.averageEntryPrice;
    }

    if (equity > peakEquity) {
      peakEquity = equity;
    }

    return total;
  }

  double unrealizedPnl(Map<String, double> prices) {
    double result = 0;

    for (final position in positions.values) {
      final price = prices[position.symbol];

      if (price == null || !price.isFinite || price <= 0) continue;

      result +=
          (price - position.averageEntryPrice) * position.quantity;
    }

    return result;
  }

  bool buy({
    required String symbol,
    required double price,
    required double quantity,
  }) {
    if (symbol.trim().isEmpty ||
        !price.isFinite ||
        !quantity.isFinite ||
        price <= 0 ||
        quantity <= 0) {
      return false;
    }

    final value = price * quantity;
    final fee = value * feeRate;
    final totalCost = value + fee;

    if (!totalCost.isFinite || totalCost > cash) return false;

    final existing = positions[symbol];

    if (existing == null) {
      positions[symbol] = PaperPosition(
        symbol: symbol,
        quantity: quantity,
        averageEntryPrice: totalCost / quantity,
      );
    } else {
      final newQuantity = existing.quantity + quantity;
      final oldCost = existing.quantity * existing.averageEntryPrice;

      existing.averageEntryPrice =
          (oldCost + totalCost) / newQuantity;
      existing.quantity = newQuantity;
    }

    cash -= totalCost;

    fills.add(PaperFill(
      symbol: symbol,
      side: OrderSide.buy,
      price: price,
      quantity: quantity,
      fee: fee,
      realizedPnl: 0,
      time: DateTime.now().toUtc(),
    ));

    return true;
  }

  bool sell({
    required String symbol,
    required double price,
    required double quantity,
  }) {
    if (symbol.trim().isEmpty ||
        !price.isFinite ||
        !quantity.isFinite ||
        price <= 0 ||
        quantity <= 0) {
      return false;
    }

    final position = positions[symbol];

    if (position == null || quantity > position.quantity) {
      return false;
    }

    final value = price * quantity;
    final fee = value * feeRate;
    final proceeds = value - fee;

    if (!proceeds.isFinite || proceeds < 0) return false;

    final pnl = (price - position.averageEntryPrice) * quantity - fee;

    cash += proceeds;
    realizedPnl += pnl;
    position.quantity -= quantity;

    if (position.quantity <= 0.00000001) {
      positions.remove(symbol);
    }

    fills.add(PaperFill(
      symbol: symbol,
      side: OrderSide.sell,
      price: price,
      quantity: quantity,
      fee: fee,
      realizedPnl: pnl,
      time: DateTime.now().toUtc(),
    ));

    return true;
  }
}

// ======================== LIVE TRADING GATE ===================

// This interface does not send orders.
// A separately audited broker adapter is required.

abstract class TradingGateway {
  Future<bool> checkConnection();

  Future<void> close();
}

class LiveTradingGate {
  LiveTradingGate._();

  static const bool enabled = false;

  static String get status =>
      'معاملات واقعی تا تکمیل اتصال امن و آزمون مستقل غیرفعال است.';

  static Future<void> submitOrder() async {
    throw StateError(
      'ارسال سفارش واقعی هنوز فعال نشده است.',
    );
  }
}
