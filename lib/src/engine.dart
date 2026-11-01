import 'dart:math';

enum TradeMode { paper, live }
enum SignalDirection { buy, sell, hold }

class Candle {
  final DateTime time;
  final double close;
  final double high;
  final double low;
  final double volume;

  const Candle({
    required this.time,
    required this.close,
    required this.high,
    required this.low,
    required this.volume,
  });
}

class SignalResult {
  final SignalDirection direction;
  final int confidence;
  final List<String> reasons;

  const SignalResult({
    required this.direction,
    required this.confidence,
    required this.reasons,
  });
}

/// Deterministic multi-indicator scoring foundation.
/// It is not a machine-learning model and must be backtested before live use.
class SignalEngine {
  SignalResult analyze(List<Candle> candles) {
    if (candles.length < 30) {
      return const SignalResult(
        direction: SignalDirection.hold,
        confidence: 0,
        reasons: ['برای تحلیل معتبر حداقل ۳۰ کندل لازم است.'],
      );
    }

    final closes = candles.map((c) => c.close).toList();
    final ema9 = _ema(closes, 9);
    final ema21 = _ema(closes, 21);
    final rsi = _rsi(closes, 14);
    final macdFast = _ema(closes, 12);
    final macdSlow = _ema(closes, 26);
    final macd = macdFast - macdSlow;
    final previousMacd = _ema(closes.sublist(0, closes.length - 1), 12) -
        _ema(closes.sublist(0, closes.length - 1), 26);

    var score = 0;
    final reasons = <String>[];

    if (ema9 > ema21) {
      score += 2;
      reasons.add('EMA 9 بالاتر از EMA 21 است؛ تمایل روند صعودی.');
    } else {
      score -= 2;
      reasons.add('EMA 9 پایین‌تر از EMA 21 است؛ تمایل روند نزولی.');
    }

    if (rsi >= 52 && rsi <= 68) {
      score += 1;
      reasons.add('RSI در محدوده مومنتوم مثبت است.');
    } else if (rsi <= 45) {
      score -= 1;
      reasons.add('RSI ضعف مومنتوم را نشان می‌دهد.');
    } else {
      reasons.add('RSI سیگنال قطعی خرید یا فروش نمی‌دهد.');
    }

    if (macd > 0 && macd >= previousMacd) {
      score += 1;
      reasons.add('MACD مثبت و رو به تقویت است.');
    } else if (macd < 0 && macd <= previousMacd) {
      score -= 1;
      reasons.add('MACD منفی و رو به تضعیف است.');
    }

    final direction = score >= 3
        ? SignalDirection.buy
        : score <= -3
            ? SignalDirection.sell
            : SignalDirection.hold;
    return SignalResult(
      direction: direction,
      confidence: min(95, (score.abs() / 4 * 100).round()),
      reasons: reasons,
    );
  }

  double _ema(List<double> values, int period) {
    if (values.isEmpty) return 0;
    final k = 2 / (period + 1);
    var value = values.take(period).reduce((a, b) => a + b) /
        min(period, values.length);
    for (final item in values.skip(period)) {
      value = item * k + value * (1 - k);
    }
    return value;
  }

  double _rsi(List<double> values, int period) {
    if (values.length <= period) return 50;
    var gains = 0.0;
    var losses = 0.0;
    for (var i = values.length - period; i < values.length; i++) {
      final change = values[i] - values[i - 1];
      if (change >= 0) {
        gains += change;
      } else {
        losses -= change;
      }
    }
    if (losses == 0) return 100;
    final rs = (gains / period) / (losses / period);
    return 100 - (100 / (1 + rs));
  }
}

class RiskManager {
  const RiskManager({
    this.riskPerTrade = 0.005,
    this.maxDailyLoss = 0.01,
  });

  final double riskPerTrade;
  final double maxDailyLoss;

  double positionNotional({
    required double equity,
    required double entry,
    required double stop,
  }) {
    if (equity <= 0 || entry <= 0 || stop <= 0 || entry == stop) return 0;
    final riskAmount = equity * riskPerTrade;
    final riskFraction = (entry - stop).abs() / entry;
    if (riskFraction <= 0) return 0;
    return min(equity, riskAmount / riskFraction);
  }

  bool dailyLossLimitReached({
    required double startingEquity,
    required double currentEquity,
  }) {
    if (startingEquity <= 0) return true;
    final lossFraction = (startingEquity - currentEquity) / startingEquity;
    return lossFraction >= maxDailyLoss;
  }
}

class PaperPortfolio {
  PaperPortfolio({this.initialUsdt = 50}) : _cash = initialUsdt;

  final double initialUsdt;
  double _cash;
  final List<PaperFill> _fills = [];

  double get cash => _cash;
  List<PaperFill> get fills => List.unmodifiable(_fills);

  bool buy({
    required String symbol,
    required double price,
    required double quantity,
  }) {
    final cost = price * quantity;
    if (price <= 0 || quantity <= 0 || cost > _cash) return false;
    _cash -= cost;
    _fills.add(PaperFill(
      symbol: symbol,
      side: 'BUY',
      price: price,
      quantity: quantity,
      time: DateTime.now(),
    ));
    return true;
  }

  bool sell({
    required String symbol,
    required double price,
    required double quantity,
  }) {
    if (price <= 0 || quantity <= 0) return false;
    _cash += price * quantity;
    _fills.add(PaperFill(
      symbol: symbol,
      side: 'SELL',
      price: price,
      quantity: quantity,
      time: DateTime.now(),
    ));
    return true;
  }
}

class PaperFill {
  const PaperFill({
    required this.symbol,
    required this.side,
    required this.price,
    required this.quantity,
    required this.time,
  });

  final String symbol;
  final String side;
  final double price;
  final double quantity;
  final DateTime time;
}
