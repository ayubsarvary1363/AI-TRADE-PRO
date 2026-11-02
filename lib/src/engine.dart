
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

// ================= MARKET DATA =================

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

class MarketDataException implements Exception {
  final String message;
  const MarketDataException(this.message);

  @override
  String toString() => message;
}

class MarketDataService {
  static const String _baseUrl = 'https://apiv2.nobitex.ir';

  final http.Client _client;

  MarketDataService({http.Client? client})
      : _client = client ?? http.Client();

  Future<List<Candle>> fetchCandles({
    String symbol = 'BTCUSDT',
    String resolution = '60',
    int countback = 100,
  }) async {
    if (countback < 30 || countback > 500) {
      throw const MarketDataException('تعداد کندل باید بین ۳۰ تا ۵۰۰ باشد.');
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final uri = Uri.parse('$_baseUrl/market/udf/history').replace(
      queryParameters: {
        'symbol': symbol,
        'resolution': resolution,
        'to': '$now',
        'countback': '$countback',
      },
    );

    try {
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw MarketDataException(
          'خطای دریافت بازار: HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic> || data['s'] != 'ok') {
        throw MarketDataException(
          data is Map ? '${data['errmsg'] ?? 'داده بازار موجود نیست.'}' :
              'پاسخ نامعتبر بازار.',
        );
      }

      final times = data['t'] as List?;
      final highs = data['h'] as List?;
      final lows = data['l'] as List?;
      final closes = data['c'] as List?;
      final volumes = data['v'] as List?;

      if (times == null ||
          highs == null ||
          lows == null ||
          closes == null ||
          volumes == null) {
        throw const MarketDataException('ساختار کندل‌ها ناقص است.');
      }

      final length = [
        times.length,
        highs.length,
        lows.length,
        closes.length,
        volumes.length,
      ].reduce(min);

      if (length < 30) {
        throw const MarketDataException('کمتر از ۳۰ کندل معتبر دریافت شد.');
      }

      final candles = <Candle>[];

      for (var i = 0; i < length; i++) {
        final close = _number(closes[i]);
        final high = _number(highs[i]);
        final low = _number(lows[i]);
        final volume = _number(volumes[i]);
        final timestamp = _number(times[i]);

        if (close <= 0 || high <= 0 || low <= 0 ||
            timestamp <= 0 || high < low) {
          continue;
        }

        candles.add(Candle(
          time: DateTime.fromMillisecondsSinceEpoch(
            timestamp.toInt() * 1000,
            isUtc: true,
          ),
          close: close,
          high: high,
          low: low,
          volume: max(0, volume),
        ));
      }

      if (candles.length < 30) {
        throw const MarketDataException('کندل معتبر کافی دریافت نشد.');
      }

      candles.sort((a, b) => a.time.compareTo(b.time));
      return candles;
    } on MarketDataException {
      rethrow;
    } catch (e) {
      throw MarketDataException('دریافت اطلاعات بازار ناموفق بود: $e');
    }
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  void dispose() {
    _client.close();
  }
}

// ================= SIGNAL ENGINE =================

enum TradeMode { paper, live }
enum SignalDirection { buy, sell, hold }

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

class SignalEngine {
  SignalResult analyze(List<Candle> candles) {
    if (candles.length < 30) {
      return const SignalResult(
        direction: SignalDirection.hold,
        confidence: 0,
        reasons: ['حداقل ۳۰ کندل برای تحلیل لازم است.'],
      );
    }

    final closes = candles.map((c) => c.close).toList();

    if (closes.any((price) => !price.isFinite || price <= 0)) {
      return const SignalResult(
        direction: SignalDirection.hold,
        confidence: 0,
        reasons: ['داده قیمت نامعتبر است.'],
      );
    }

    final ema9 = _ema(closes, 9);
    final ema21 = _ema(closes, 21);
    final rsi = _rsi(closes, 14);

    final macdValues = _macd(closes);
    final macd = macdValues.last;
    final previousMacd = macdValues[macdValues.length - 2];

    var score = 0;
    final reasons = <String>[];

    if (ema9 > ema21) {
      score += 2;
      reasons.add('EMA 9 بالاتر از EMA 21 است.');
    } else {
      score -= 2;
      reasons.add('EMA 9 پایین‌تر از EMA 21 است.');
    }

    if (rsi >= 52 && rsi <= 68) {
      score++;
      reasons.add('RSI نشان‌دهنده مومنتوم مثبت است.');
    } else if (rsi <= 45) {
      score--;
      reasons.add('RSI نشان‌دهنده ضعف مومنتوم است.');
    } else {
      reasons.add('RSI سیگنال مشخصی ندارد.');
    }

    if (macd > 0 && macd > previousMacd) {
      score++;
      reasons.add('MACD مثبت و تقویت‌شونده است.');
    } else if (macd < 0 && macd < previousMacd) {
      score--;
      reasons.add('MACD منفی و تضعیف‌شونده است.');
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
    final k = 2 / (period + 1);
    var result = values.take(period).reduce((a, b) => a + b) / period;

    for (final value in values.skip(period)) {
      result = value * k + result * (1 - k);
    }

    return result;
  }

  double _rsi(List<double> values, int period) {
    if (values.length <= period) return 50;

    var gains = 0.0;
    var losses = 0.0;

    for (var i = 1; i <= period; i++) {
      final change = values[i] - values[i - 1];
      if (change > 0) {
        gains += change;
      } else {
        losses -= change;
      }
    }

    var averageGain = gains / period;
    var averageLoss = losses / period;

    for (var i = period + 1; i < values.length; i++) {
      final change = values[i] - values[i - 1];

      averageGain =
          (averageGain * (period - 1) + max(0, change)) / period;

      averageLoss =
          (averageLoss * (period - 1) + max(0, -change)) / period;
    }

    if (averageLoss == 0) return 100;
    final rs = averageGain / averageLoss;
    return 100 - (100 / (1 + rs));
  }

  List<double> _macd(List<double> values) {
    final result = <double>[];

    for (var i = 27; i < values.length; i++) {
      final sample = values.sublist(0, i + 1);
      result.add(_ema(sample, 12) - _ema(sample, 26));
    }

    return result;
  }
}

// ================= RISK MANAGEMENT =================

class RiskManager {
  const RiskManager({
    this.riskPerTrade = 0.005,
    this.maxDailyLoss = 0.01,
    this.maxDrawdown = 0.05,
  });

  final double riskPerTrade;
  final double maxDailyLoss;
  final double maxDrawdown;

  double positionNotional({
    required double equity,
    required double entry,
    required double stop,
  }) {
    if (equity <= 0 || entry <= 0 || stop <= 0 || entry == stop) {
      return 0;
    }

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

    return (startingEquity - currentEquity) / startingEquity
        >= maxDailyLoss;
  }

  bool drawdownLimitReached({
    required double initialEquity,
    required double currentEquity,
  }) {
    if (initialEquity <= 0) return true;

    return (initialEquity - currentEquity) / initialEquity
        >= maxDrawdown;
  }
}

// ================= PAPER PORTFOLIO =================

class PaperPosition {
  final String symbol;
  final double quantity;
  final double averageCost;

  const PaperPosition({
    required this.symbol,
    required this.quantity,
    required this.averageCost,
  });

  double marketValue(double price) => quantity * price;
  double unrealizedPnl(double price) =>
      (price - averageCost) * quantity;
}

class PaperPortfolio {
  PaperPortfolio({
    this.initialUsdt = 50,
    this.feeRate = 0.001,
  }) : _cash = initialUsdt;

  final double initialUsdt;
  final double feeRate;

  double _cash;
  double _realizedPnl = 0;

  final List<PaperFill> _fills = [];
  final Map<String, PaperPosition> _positions = {};

  double get cash => _cash;
  double get realizedPnl => _realizedPnl;

  List<PaperFill> get fills => List.unmodifiable(_fills);

  Map<String, PaperPosition> get positions =>
      Map.unmodifiable(_positions);

  double get totalFees =>
      _fills.fold(0, (sum, fill) => sum + fill.fee);

  double equity(Map<String, double> prices) {
    var result = _cash;

    for (final entry in _positions.entries) {
      final price = prices[entry.key];

      if (price != null && price > 0) {
        result += entry.value.marketValue(price);
      }
    }

    return result;
  }

  double unrealizedPnl(Map<String, double> prices) {
    var result = 0.0;

    for (final entry in _positions.entries) {
      final price = prices[entry.key];

      if (price != null && price > 0) {
        result += entry.value.unrealizedPnl(price);
      }
    }

    return result;
  }

  bool buy({
    required String symbol,
    required double price,
    required double quantity,
  }) {
    if (!price.isFinite || !quantity.isFinite ||
        price <= 0 || quantity <= 0) {
      return false;
    }

    final cost = price * quantity;
    final fee = cost * feeRate;
    final total = cost + fee;

    if (total > _cash) return false;

    final old = _positions[symbol];
    final oldQuantity = old?.quantity ?? 0;
    final oldCost = oldQuantity * (old?.averageCost ?? 0);

    final newQuantity = oldQuantity + quantity;
    final newAverageCost =
        (oldCost + total) / newQuantity;

    _cash -= total;

    _positions[symbol] = PaperPosition(
      symbol: symbol,
      quantity: newQuantity,
      averageCost: newAverageCost,
    );

    _fills.add(PaperFill(
      symbol: symbol,
      side: 'BUY',
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
    if (!price.isFinite || !quantity.isFinite ||
        price <= 0 || quantity <= 0) {
      return false;
    }

    final position = _positions[symbol];

    if (position == null || quantity > position.quantity) {
      return false;
    }

    final gross = price * quantity;
    final fee = gross * feeRate;
    final proceeds = gross - fee;

    final pnl = proceeds - position.averageCost * quantity;

    _cash += proceeds;
    _realizedPnl += pnl;

    final remaining = position.quantity - quantity;

    if (remaining <= 0.000000000001) {
      _positions.remove(symbol);
    } else {
      _positions[symbol] = PaperPosition(
        symbol: symbol,
        quantity: remaining,
        averageCost: position.averageCost,
      );
    }

    _fills.add(PaperFill(
      symbol: symbol,
      side: 'SELL',
      price: price,
      quantity: quantity,
      fee: fee,
      realizedPnl: pnl,
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
    required this.fee,
    required this.realizedPnl,
    required this.time,
  });

  final String symbol;
  final String side;
  final double price;
  final double quantity;
  final double fee;
  final double realizedPnl;
  final DateTime time;
}
