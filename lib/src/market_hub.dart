
import 'dart:async';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

// =====================================================
// AI TRADE PRO
// Market Hub Version 0.9.0
// Smart routing + multi-provider + diagnostics
// Paper trading data only
// =====================================================

class _QuoteResult {
  final MarketQuote quote;
  final int latencyMs;
  final String providerName;

  const _QuoteResult({
    required this.quote,
    required this.latencyMs,
    required this.providerName,
  });
}

class MarketHub {
  final MarketProviderRegistry registry;

  final Duration quoteTimeout;
  final Duration candleTimeout;
  final Duration maximumQuoteAge;

  final SmartExchangeRouter router = const SmartExchangeRouter();

  bool _disposed = false;

  String lastQuoteStatus = 'هنوز قیمتی دریافت نشده است';
  String lastCandleStatus = 'هنوز کندلی دریافت نشده است';

  DateTime? lastSuccessfulQuote;
  DateTime? lastSuccessfulCandles;

  final Map<String, String> providerErrors = {};

  MarketHub({
    required this.registry,
    this.quoteTimeout = const Duration(seconds: 7),
    this.candleTimeout = const Duration(seconds: 12),
    this.maximumQuoteAge = const Duration(seconds: 15),
  });

  bool get isDisposed => _disposed;

  // -------------------- QUOTE COLLECTION --------------------

  Future<List<_QuoteResult>> _collectQuoteResults(
    String symbol, {
    required MarketType market,
  }) async {
    if (_disposed || symbol.trim().isEmpty) {
      return const [];
    }

    final providers = registry.providersFor(market);

    if (providers.isEmpty) {
      lastQuoteStatus = 'هیچ منبع فعالی برای این بازار وجود ندارد';
      return const [];
    }

    final futures = providers.map((provider) async {
      final stopwatch = Stopwatch()..start();

      try {
        final quote = await provider
            .fetchQuote(symbol)
            .timeout(quoteTimeout);

        stopwatch.stop();

        if (quote == null) {
          providerErrors[provider.id] = 'قیمت دریافت نشد';
          return null;
        }

        if (quote.providerId != provider.id ||
            quote.symbol.toUpperCase() != symbol.toUpperCase() ||
            quote.market != market ||
            !quote.isValid ||
            !quote.isFresh(maximumAge: maximumQuoteAge)) {
          providerErrors[provider.id] = 'قیمت نامعتبر یا قدیمی است';
          return null;
        }

        providerErrors.remove(provider.id);

        return _QuoteResult(
          quote: quote,
          latencyMs: stopwatch.elapsedMilliseconds,
          providerName: provider.name,
        );
      } on TimeoutException {
        stopwatch.stop();
        providerErrors[provider.id] = 'مهلت دریافت قیمت تمام شد';
        return null;
      } catch (error) {
        stopwatch.stop();
        providerErrors[provider.id] = error.toString();
        return null;
      }
    });

    final results = await Future.wait(futures);

    if (_disposed) return const [];

    return results.whereType<_QuoteResult>().toList();
  }

  // -------------------- SMART ROUTING --------------------

  Future<List<MarketQuote>> collectQuotes(
    String symbol, {
    MarketType market = MarketType.crypto,
  }) async {
    final results = await _collectQuoteResults(
      symbol,
      market: market,
    );

    if (_disposed || results.isEmpty) {
      lastQuoteStatus = 'دریافت قیمت از تمام منابع ناموفق بود';
      return const [];
    }

    final candidates = results.map((item) {
      final quote = item.quote;

      final safeVolume = quote.volume.isFinite && quote.volume > 0
          ? quote.volume
          : 0.0;

      return ExchangeCandidate(
        id: quote.providerId,
        name: item.providerName,
        market: quote.market,
        type: ProviderType.exchange,
        enabled: true,
        connected: true,
        tradingAllowed: false,
        bid: quote.bid,
        ask: quote.ask,
        feeRate: 0,
        liquidity: safeVolume,
        latencyMs: item.latencyMs,
        availableBalance: 0,
      );
    }).toList();

    final routing = router.route(
      candidates,
      purpose: RoutingPurpose.marketData,
    );

    if (_disposed) return const [];

    final quoteByProvider = {
      for (final item in results)
        item.quote.providerId: item.quote,
    };

    final rankedQuotes = <MarketQuote>[];

    for (final candidate in routing.ranked) {
      final quote = quoteByProvider[candidate.id];

      if (quote != null) {
        rankedQuotes.add(quote);
      }
    }

    if (rankedQuotes.isEmpty) {
      lastQuoteStatus = 'مسیریاب هوشمند منبع قیمت معتبری انتخاب نکرد';
      return const [];
    }

    final selected = routing.selected;

    if (selected == null) {
      lastQuoteStatus = 'انتخاب منبع قیمت ناموفق بود';
      return const [];
    }

    lastQuoteStatus =
        'منبع هوشمند انتخاب‌شده: ${selected.name}';

    lastSuccessfulQuote = DateTime.now();

    return rankedQuotes;
  }

  Future<MarketQuote?> getBestQuote(
    String symbol, {
    MarketType market = MarketType.crypto,
  }) async {
    final quotes = await collectQuotes(
      symbol,
      market: market,
    );

    if (quotes.isEmpty) return null;

    return quotes.first;
  }

  // -------------------- CANDLES --------------------

  Future<List<Candle>> fetchCandles(
    String symbol,
    String interval, {
    MarketType market = MarketType.crypto,
    int limit = 200,
  }) async {
    if (_disposed || symbol.trim().isEmpty) {
      return const [];
    }

    final providers = registry.providersFor(market)
        .where((provider) => provider is CandleMarketProvider)
        .cast<CandleMarketProvider>()
        .toList();

    if (providers.isEmpty) {
      lastCandleStatus = 'هیچ منبع کندلی برای این بازار وجود ندارد';
      return const [];
    }

    final futures = providers.map((provider) async {
      final marketProvider = provider as MarketProvider;

      try {
        final candles = await provider
            .fetchCandles(
              symbol,
              interval,
              limit: limit,
            )
            .timeout(candleTimeout);

        final valid = candles.where((candle) {
          return candle.isValid &&
              candle.time.isBefore(
                DateTime.now().add(const Duration(seconds: 5)),
              );
        }).toList()
          ..sort((a, b) => a.time.compareTo(b.time));

        if (valid.length < 30) {
          providerErrors[marketProvider.id] =
              'تعداد کندل معتبر کمتر از ۳۰ است';
          return <Candle>[];
        }

        providerErrors.remove(marketProvider.id);
        return valid;
      } on TimeoutException {
        providerErrors[marketProvider.id] =
            'مهلت دریافت کندل تمام شد';
        return <Candle>[];
      } catch (error) {
        providerErrors[marketProvider.id] = error.toString();
        return <Candle>[];
      }
    });

    final results = await Future.wait(futures);

    if (_disposed) return const [];

    results.sort((a, b) => b.length.compareTo(a.length));

    if (results.isEmpty || results.first.isEmpty) {
      lastCandleStatus = 'دریافت کندل از تمام منابع ناموفق بود';
      return const [];
    }

    lastCandleStatus =
        '${results.first.length} کندل معتبر دریافت شد';

    lastSuccessfulCandles = DateTime.now();

    return results.first;
  }

  // -------------------- CONNECTIONS --------------------

  Future<List<ProviderStatus>> checkConnections() async {
    if (_disposed) return const [];

    final checker = MarketConnectionChecker(registry);
    return checker.checkAll();
  }

  // -------------------- PROVIDERS --------------------

  List<MarketProvider> getProviders(MarketType market) {
    if (_disposed) return const [];

    return registry.providersFor(market);
  }

  int get providerCount => registry.length;

  // -------------------- DISPOSE --------------------

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    await registry.closeAll();
  }
}
