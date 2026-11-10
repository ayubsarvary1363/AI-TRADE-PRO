import 'engine.dart';
import 'exchange_router.dart';
import 'market_hub.dart';
import 'market_provider.dart';

class MarketScanResult {
  final String symbol;
  final MarketType market;
  final MarketQuote quote;
  final List<Candle> candles;
  final TradeSignal signal;
  final bool isNewCandle;

  const MarketScanResult({
    required this.symbol,
    required this.market,
    required this.quote,
    required this.candles,
    required this.signal,
    required this.isNewCandle,
  });
}

class MarketScanCycle {
  final List<MarketScanResult> batch;
  final MarketScanResult? bestOpportunity;
  final bool cycleCompleted;
  final int scanned;
  final int total;
  final int quoteRejected;
  final int candleRejected;
  final int noNewCandle;
  final int noBuySignal;
  final int lowConfidence;
  final int buySignals;

  const MarketScanCycle({
    required this.batch,
    required this.bestOpportunity,
    required this.cycleCompleted,
    required this.scanned,
    required this.total,
    this.quoteRejected = 0,
    this.candleRejected = 0,
    this.noNewCandle = 0,
    this.noBuySignal = 0,
    this.lowConfidence = 0,
    this.buySignals = 0,
  });
}

class MarketScanner {
  final MarketHub marketHub;
  final SignalEngine signalEngine;

  MarketScanner({required this.marketHub, required this.signalEngine});

  static const List<String> cryptoSymbols = [
    'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT',
    'ADAUSDT', 'DOGEUSDT', 'LTCUSDT', 'BCHUSDT', 'LINKUSDT',
    'DOTUSDT', 'AVAXUSDT', 'XLMUSDT', 'ATOMUSDT', 'UNIUSDT',
    'ETCUSDT', 'FILUSDT', 'AAVEUSDT', 'NEARUSDT', 'ALGOUSDT',
    'TRXUSDT', 'SHIBUSDT', 'PEPEUSDT', 'SUIUSDT', 'TONUSDT',
    'ICPUSDT', 'INJUSDT', 'OPUSDT', 'ARBUSDT', 'APTUSDT',
  ];

  static const List<String> forexSymbols = [
    'EURUSD=X', 'GBPUSD=X', 'USDJPY=X', 'AUDUSD=X', 'USDCAD=X',
    'USDCHF=X', 'NZDUSD=X', 'EURGBP=X', 'EURJPY=X', 'EURCHF=X',
    'EURAUD=X', 'EURCAD=X', 'EURNZD=X', 'GBPJPY=X', 'GBPCHF=X',
    'GBPAUD=X', 'GBPCAD=X', 'GBPNZD=X', 'AUDJPY=X', 'AUDNZD=X',
    'AUDCAD=X', 'AUDCHF=X', 'NZDJPY=X', 'CADJPY=X', 'CHFJPY=X',
  ];

  final Map<String, DateTime> _lastCandleBySymbol = {};
  int _cursor = 0;
  MarketScanResult? _bestInCycle;

  int _quoteRejected = 0;
  int _candleRejected = 0;
  int _noNewCandle = 0;
  int _noBuySignal = 0;
  int _lowConfidence = 0;
  int _buySignals = 0;

  int get totalSymbols => cryptoSymbols.length + forexSymbols.length;

  void reset() {
    _lastCandleBySymbol.clear();
    _cursor = 0;
    _bestInCycle = null;
    _quoteRejected = 0;
    _candleRejected = 0;
    _noNewCandle = 0;
    _noBuySignal = 0;
    _lowConfidence = 0;
    _buySignals = 0;
  }

  Duration _intervalDuration(String interval) {
    if (interval.length < 2) return const Duration(hours: 1);
    final amount = int.tryParse(interval.substring(0, interval.length - 1)) ?? 1;
    final unit = interval.substring(interval.length - 1);
    switch (unit) {
      case 's': return Duration(seconds: amount);
      case 'm': return Duration(minutes: amount);
      case 'h': return Duration(hours: amount);
      case 'd': return Duration(days: amount);
      default: return const Duration(hours: 1);
    }
  }

  Future<MarketScanResult?> _scanOne(
    String symbol, MarketType market, String interval, TradingStyle style,
  ) async {
    try {
      final quoteFuture = marketHub.getBestQuote(symbol, market: market);
      final candlesFuture = marketHub.fetchCandles(
        symbol, interval, market: market, limit: 120,
      );
      final quote = await quoteFuture;
      final candles = await candlesFuture;

      if (quote == null || !quote.isValid ||
          !quote.isFresh(maximumAge: const Duration(seconds: 15)) ||
          quote.symbol.toUpperCase() != symbol.toUpperCase()) {
        _quoteRejected++;
        return null;
      }

      // Kraken and Coinbase can include the still-forming candle.
      // Only fully closed candles are eligible for a new trade signal.
      final candleDuration = _intervalDuration(interval);
      final now = DateTime.now();
      final closedCandles = candles.where((candle) {
        return candle.time.add(candleDuration).isBefore(now);
      }).toList()
        ..sort((a, b) => a.time.compareTo(b.time));

      if (closedCandles.length < 30) {
        _candleRejected++;
        return null;
      }

      final latestCandle = closedCandles.last;
      final candleAge = now.difference(latestCandle.time);
      final maximumCandleAge = candleDuration * 3;
      if (candleAge.isNegative || candleAge > maximumCandleAge) {
        _candleRejected++;
        return null;
      }

      final previousTime = _lastCandleBySymbol[symbol];
      final isNewCandle = previousTime != null &&
          latestCandle.time.isAfter(previousTime);
      if (previousTime == null || latestCandle.time.isAfter(previousTime)) {
        _lastCandleBySymbol[symbol] = latestCandle.time;
      }

      if (!isNewCandle) _noNewCandle++;
      final signal = signalEngine.analyze(closedCandles, style: style);
      if (isNewCandle) {
        if (signal.direction != SignalDirection.buy) {
          _noBuySignal++;
        } else if (signal.confidence < 0.60) {
          _lowConfidence++;
        } else {
          _buySignals++;
        }
      }
      return MarketScanResult(
        symbol: symbol, market: market, quote: quote, candles: closedCandles,
        signal: signal, isNewCandle: isNewCandle,
      );
    } catch (_) {
      _candleRejected++;
      return null;
    }
  }

  Future<MarketScanCycle> scanNextBatch({
    required String interval,
    required TradingStyle style,
    int batchSize = 4,
  }) async {
    final universe = <MapEntry<String, MarketType>>[
      ...cryptoSymbols.map((s) => MapEntry(s, MarketType.crypto)),
      ...forexSymbols.map((s) => MapEntry(s, MarketType.forex)),
    ];
    if (universe.isEmpty) {
      return const MarketScanCycle(
        batch: [], bestOpportunity: null, cycleCompleted: true,
        scanned: 0, total: 0,
      );
    }

    final start = _cursor;
    final end = (start + batchSize).clamp(0, universe.length).toInt();
    final entries = universe.sublist(start, end);
    final results = await Future.wait(entries.map((entry) {
      return _scanOne(entry.key, entry.value, interval, style);
    }));
    final valid = results.whereType<MarketScanResult>().toList();

    for (final result in valid) {
      if (result.isNewCandle &&
          result.signal.direction == SignalDirection.buy &&
          result.signal.confidence >= 0.60) {
        if (_bestInCycle == null ||
            result.signal.confidence > _bestInCycle!.signal.confidence) {
          _bestInCycle = result;
        }
      }
    }

    _cursor = end;
    final completed = _cursor >= universe.length;
    MarketScanResult? best;
    if (completed) {
      best = _bestInCycle;
      _cursor = 0;
      _bestInCycle = null;
    }

    return MarketScanCycle(
      batch: valid, bestOpportunity: best, cycleCompleted: completed,
      scanned: end,
      total: universe.length,
      quoteRejected: _quoteRejected,
      candleRejected: _candleRejected,
      noNewCandle: _noNewCandle,
      noBuySignal: _noBuySignal,
      lowConfidence: _lowConfidence,
      buySignals: _buySignals,
    );
  }
}