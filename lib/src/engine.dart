
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

// =====================================================
// AI TRADE PRO - ENGINE VERSION 0.4.0
// Paper trading only - No real orders
// =====================================================

enum TradeMode { paper, live }
enum SignalDirection { buy, sell, hold }

// ==================== CANDLE ====================

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

// ==================== MARKET DATA ====================

class MarketDataException implements Exception {
  final String message;
  const MarketDataException(this.message);

  @override
  String toString() => message;
}

class MarketDataService {
  static const String _binanceUrl = 'https://api.binance.com';
  static const String _nobitexUrl = 'https://apiv2.nobitex.ir';

  final http.Client _client;

  MarketDataService({http.Client? client})
      : _client = client ?? http.Client();

  Future<List<Candle>> fetchCandles({
    String symbol = 'BTCUSDT',
    String resolution = '60',
    int countback = 100,
    String provider = 'binance',
  }) async {
    if (countback < 30 || countback > 1000) {
      throw const MarketDataException(
        'تعداد کندل باید بین ۳۰ تا ۱۰۰۰ باشد.',
      );
    }

    final normalizedSymbol = symbol.trim().toUpperCase();

    if (normalizedSymbol.isEmpty) {
      throw const MarketDataException('نماد معتبر نیست.');
    }

    if (provider == 'binance') {
      return _fetchBinanceCandles(
        normalizedSymbol,
        resolution,
        countback,
      );
    }

    if (provider == 'nobitex') {
      return _fetchNobitexCandles(
        normalizedSymbol,
        resolution,
        countback,
      );
    }

    throw const MarketDataException(
      'منبع اطلاعات بازار پشتیبانی نمی‌شود.',
    );
  }

  Future<List<Candle>> _fetchBinanceCandles(
    String symbol,
    String resolution,
    int countback,
  ) async {
    const intervals = {
      '1': '1m',
      '3': '3m',
      '5': '5m',
      '15': '15m',
      '30': '30m',
      '60': '1h',
      '120': '2h',
      '240': '4h',
      '360': '6h',
      '480': '8h',
      '720': '12h',
      'D': '1d',
      'W': '1w',
      'M': '1M',
    };

    final interval = intervals[resolution];

    if (interval == null) {
      throw const MarketDataException(
        'تایم‌فریم Binance پشتیبانی نمی‌شود.',
      );
    }

    final uri = Uri.parse(
      '$_binanceUrl/api/v3/klines',
    ).replace(
      queryParameters: {
        'symbol': symbol,
        'interval': interval,
        'limit': '$countback',
      },
    );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw MarketDataException(
          'خطای Binance: ${response.statusCode}',
        );
      }

      final dynamic decoded = jsonDecode(response.body);

      if (decoded is! List) {
        throw const MarketDataException(
          'ساختار کندل‌های Binance معتبر نیست.',
        );
      }

      final candles = <Candle>[];

      for (final item in decoded) {
        if (item is! List || item.length < 6) continue;

        final timestamp = _number(item[0]);
        final high = _number(item[2]);
        final low = _number(item[3]);
        final close = _number(item[4]);
        final volume = _number(item[5]);

        if (!timestamp.isFinite ||
            !high.isFinite ||
            !low.isFinite ||
            !close.isFinite ||
            !volume.isFinite ||
            timestamp <= 0 ||
            high <= 0 ||
            low <= 0 ||
            close <= 0 ||
            high < low ||
            close > high ||
            close < low) {
          continue;
        }

        candles.add(
          Candle(
            time: DateTime.fromMillisecondsSinceEpoch(
              timestamp.toInt(),
              isUtc: true,
            ),
            close: close,
            high: high,
            low: low,
            volume: max(0.0, volume),
          ),
        );
      }

      candles.sort((a, b) => a.time.compareTo(b.time));

      if (candles.length < 30) {
        throw const MarketDataException(
          'کندل معتبر کافی از Binance دریافت نشد.',
        );
      }

      return candles;
    } on MarketDataException {
      rethrow;
    } catch (e) {
      throw MarketDataException(
        'خطا در دریافت کندل Binance: $e',
      );
    }
  }

  Future<List<Candle>> _fetchNobitexCandles(
    String symbol,
    String resolution,
    int countback,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final uri = Uri.parse(
      '$_nobitexUrl/market/udf/history',
    ).replace(
      queryParameters: {
        'symbol': symbol,
        'resolution': resolution,
        'to': '$now',
        'countback': '$countback',
      },
    );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw MarketDataException(
          'خطای نوبیتکس: ${response.statusCode}',
        );
      }

      final dynamic decoded = jsonDecode(response.body);

      if (decoded is! Map || decoded['s'] != 'ok') {
        throw const MarketDataException(
          'اطلاعات کندل نوبیتکس موجود نیست.',
        );
      }

      final times = decoded['t'];
      final highs = decoded['h'];
      final lows = decoded['l'];
      final closes = decoded['c'];
      final volumes = decoded['v'];

      if (times is! List ||
          highs is! List ||
          lows is! List ||
          closes is! List ||
          volumes is! List) {
        throw const MarketDataException(
          'ساختار اطلاعات نوبیتکس ناقص است.',
        );
      }

      final length = [
        times.length,
        highs.length,
        lows.length,
        closes.length,
        volumes.length,
      ].reduce((a, b) => a < b ? a : b);

      final candles = <Candle>[];

      for (var i = 0; i < length; i++) {
        final timestamp = _number(times[i]);
        final high = _number(highs[i]);
        final low = _number(lows[i]);
        final close = _number(closes[i]);
        final volume = _number(volumes[i]);

        if (!timestamp.isFinite ||
            !high.isFinite ||
            !low.isFinite ||
            !close.isFinite ||
            !volume.isFinite ||
            timestamp <= 0 ||
            high <= 0 ||
            low <= 0 ||
            close <= 0 ||
            high < low ||
            close > high ||
            close < low) {
          continue;
        }

        candles.add(
          Candle(
            time: DateTime.fromMillisecondsSinceEpoch(
              timestamp.toInt() * 1000,
              isUtc: true,
            ),
            close: close,
            high: high,
            low: low,
            volume: max(0.0, volume),
          ),
        );
      }

      candles.sort((a, b) => a.time.compareTo(b.time));

      if (candles.length < 30) {
        throw const MarketDataException(
          'کندل معتبر کافی از نوبیتکس دریافت نشد.',
        );
      }

      return candles;
    } on MarketDataException {
      rethrow;
    } catch (e) {
      throw MarketDataException(
        'خطا در دریافت کندل نوبیتکس: $e',
      );
    }
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0.0;
  }

  void dispose() {
    _client.close();
  }
}

// ==================== SIGNAL RESULT ====================

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

// ==================== SIGNAL ENGINE ====================

class SignalEngine {
  SignalResult analyze(List<Candle> candles) {
    if (candles.length < 30) {
      return const SignalResult(
        direction: SignalDirection.hold,
        confidence: 0,
        reasons: ['برای تحلیل حداقل ۳۰ کندل لازم است.'],
      );
    }

    final closes = candles.map((c) => c.close).toList();

    if (closes.any((v) => !v.isFinite || v <= 0)) {
      return const SignalResult(
        direction: SignalDirection.hold,
        confidence: 0,
        reasons: ['اطلاعات قیمت نامعتبر است.'],
      );
    }

    final ema9 = _ema(closes, 9);
    final ema21 = _ema(closes, 21);
    final rsi = _rsi(closes, 14);
    final macdValues = _macd(closes);

    if (macdValues.length < 2) {
      return const SignalResult(
        direction: SignalDirection.hold,
        confidence: 0,
        reasons: ['داده کافی برای MACD وجود ندارد.'],
      );
    }

    final macd = macdValues.last;
    final previousMacd = macdValues[macdValues.length - 2];

    var score = 0;
    final reasons = <String>[];

    if (ema9 > ema21) {
      score += 2;
      reasons.add('روند EMA صعودی است.');
    } else {
      score -= 2;
      reasons.add('روند EMA نزولی است.');
    }

    if (rsi >= 52 && rsi <= 68) {
      score++;
      reasons.add('RSI مومنتوم مثبت دارد.');
    } else if (rsi <= 45) {
      score--;
      reasons.add('RSI ضعف مومنتوم را نشان می‌دهد.');
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

    final confidence = min(
      95,
      (score.abs() / 4 * 100).round(),
    );

    return SignalResult(
      direction: direction,
      confidence: confidence,
      reasons: reasons,
    );
  }

  double _ema(List<double> values, int period) {
    if (values.length < period) return 0.0;

    final k = 2.0 / (period + 1);

    var result =
        values.take(period).reduce((a, b) => a + b) / period;

    for (final value in values.skip(period)) {
      result = value * k + result * (1 - k);
    }

    return result;
  }

  double _rsi(List<double> values, int period) {
    if (values.length <= period) return 50.0;

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
          (averageGain * (period - 1) +
                  (change > 0 ? change : 0.0)) /
              period;

      averageLoss =
          (averageLoss * (period - 1) +
                  (change < 0 ? -change : 0.0)) /
              period;
    }

    if (averageLoss == 0) return 100.0;

    final rs = averageGain / averageLoss;
    return 100.0 - (100.0 / (1.0 + rs));
  }

  List<double> _macd(List<double> values) {
    final result = <double>[];

    for (var i = 26; i < values.length; i++) {
      final sample = values.sublist(0, i + 1);
      result.add(_ema(sample, 12) - _ema(sample, 26));
    }

    return result;
  }
}

// ==================== RISK MANAGER ====================

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
    if (!equity.isFinite ||
        !entry.isFinite ||
        !stop.isFinite ||
        equity <= 0 ||
        entry <= 0 ||
        stop <= 0 ||
        entry == stop) {
      return 0.0;
    }

    final riskAmount = equity * riskPerTrade;
    final riskFraction = (entry - stop).abs() / entry;

    if (riskFraction <= 0) return 0.0;

    return min(
      equity,
      riskAmount / riskFraction,
    ).toDouble();
  }

  bool dailyLossLimitReached({
    required double startingEquity,
    required double currentEquity,
  }) {
    if (!startingEquity.isFinite ||
        !currentEquity.isFinite ||
        startingEquity <= 0) {
      return true;
    }

    final loss =
        (startingEquity - currentEquity) / startingEquity;

    return loss >= maxDailyLoss;
  }

  bool drawdownLimitReached({
    required double initialEquity,
    required double currentEquity,
  }) {
    if (!initialEquity.isFinite ||
        !currentEquity.isFinite ||
        initialEquity <= 0) {
      return true;
    }

    final loss =
        (initialEquity - currentEquity) / initialEquity;

    return loss >= maxDrawdown;
  }
}

// ==================== PAPER POSITION ====================

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

// ==================== PAPER PORTFOLIO ====================

class PaperPortfolio {
  PaperPortfolio({
    this.initialUsdt = 50.0,
    this.feeRate = 0.001,
  })  : _cash = initialUsdt,
        _peakEquity = initialUsdt;

  final double initialUsdt;
  final double feeRate;

  double _cash;
  double _realizedPnl = 0.0;
  double _peakEquity;
  double _maximumDrawdown = 0.0;

  final List<PaperFill> _fills = [];
  final Map<String, PaperPosition> _positions = {};

  double get cash => _cash;
  double get realizedPnl => _realizedPnl;
  double get peakEquity => _peakEquity;
  double get maximumDrawdown => _maximumDrawdown;

  List<PaperFill> get fills => List.unmodifiable(_fills);

  Map<String, PaperPosition> get positions =>
      Map.unmodifiable(_positions);

  double get totalFees => _fills.fold(
        0.0,
        (sum, fill) => sum + fill.fee,
      );

  double equity(Map<String, double> prices) {
    var result = _cash;

    for (final entry in _positions.entries) {
      final price = prices[entry.key];

      if (price == null || !price.isFinite || price <= 0) {
        return double.nan;
      }

      result += entry.value.marketValue(price);
    }

    if (!result.isFinite) return double.nan;

    if (result > _peakEquity) {
      _peakEquity = result;
    }

    if (_peakEquity > 0) {
      final drawdown = (_peakEquity - result) / _peakEquity;

      if (drawdown > _maximumDrawdown) {
        _maximumDrawdown = drawdown;
      }
    }

    return result;
  }

  double unrealizedPnl(Map<String, double> prices) {
    var result = 0.0;

    for (final entry in _positions.entries) {
      final price = prices[entry.key];

      if (price == null || !price.isFinite || price <= 0) {
        return double.nan;
      }

      result += entry.value.unrealizedPnl(price);
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
        quantity <= 0 ||
        !feeRate.isFinite ||
        feeRate < 0) {
      return false;
    }

    final cost = price * quantity;
    final fee = cost * feeRate;
    final total = cost + fee;

    if (!total.isFinite || total > _cash) return false;

    final old = _positions[symbol];
    final oldQuantity = old?.quantity ?? 0.0;
    final oldCost = oldQuantity * (old?.averageCost ?? 0.0);
    final newQuantity = oldQuantity + quantity;

    if (!newQuantity.isFinite || newQuantity <= 0) return false;

    final newAverageCost = (oldCost + total) / newQuantity;

    _cash -= total;

    _positions[symbol] = PaperPosition(
      symbol: symbol,
      quantity: newQuantity,
      averageCost: newAverageCost,
    );

    _fills.add(
      PaperFill(
        symbol: symbol,
        side: 'BUY',
        price: price,
        quantity: quantity,
        fee: fee,
        realizedPnl: 0.0,
        time: DateTime.now(),
      ),
    );

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
        quantity <= 0 ||
        !feeRate.isFinite ||
        feeRate < 0) {
      return false;
    }

    final position = _positions[symbol];

    if (position == null || quantity > position.quantity) {
      return false;
    }

    final gross = price * quantity;
    final fee = gross * feeRate;
    final proceeds = gross - fee;

    if (!proceeds.isFinite || proceeds <= 0) return false;

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

    _fills.add(
      PaperFill(
        symbol: symbol,
        side: 'SELL',
        price: price,
        quantity: quantity,
        fee: fee,
        realizedPnl: pnl,
        time: DateTime.now(),
      ),
    );

    return true;
  }
}

// ==================== PAPER FILL ====================

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
