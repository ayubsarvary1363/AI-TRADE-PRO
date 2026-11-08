
import 'dart:async';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

// =====================================================
// AI TRADE PRO
// Market Hub Version 0.9.0
// Smart Provider Routing + Diagnostics + Fallback
// Paper Trading Data Layer
// =====================================================

class MarketHub {
  final MarketProviderRegistry registry;
  final SmartExchangeRouter router;

  final Duration quoteTimeout;
  final Duration candleTimeout;
  final Duration maximumQuoteAge;

  bool _disposed = false;

  String lastQuoteStatus = 'هنوز قیمتی دریافت نشده است';
  String lastCandleStatus = 'هنوز کندلی دریافت نشده است';

  DateTime? lastSuccessfulQuote;
  DateTime? lastSuccessfulCandles;

  final Map<String, String> providerErrors = {};

  MarketHub({
    required this.registry,
    SmartExchangeRouter? router,
    this.quoteTimeout = const Duration(seconds: 7),
    this.candleTimeout = const Duration(seconds: 12),
    this.maximumQuoteAge = const Duration(seconds: 15),
  }) : router = router ?? const SmartExchangeRouter();

  bool get isDisposed => _disposed;

  // -------------------- SMART QUOTE ROUTING --------------------

  Future<MarketQuote?> getBestQuote(
    String symbol, {
    MarketType market = MarketType.crypto,
  }) async {
    if (_disposed || symbol.trim().isEmpty) return null;

    final providers = registry.providersFor(market);

    if (providers.isEmpty) {
      lastQuoteStatus = 'هیچ منبع فعالی برای این بازار وجود ندارد';
      return null;
    }

    final quoteByProvider = <String, MarketQuote>{};
    final candidates = <ExchangeCandidate>[];

    final futures = providers.map((provider) async {
      final stopwatch = Stopwatch()..start();

      try {
        final quote = await provider
            .fetchQuote(symbol)
            .timeout(quoteTimeout);

        stopwatch.stop();

        if (_disposed) return;

        if (quote == null) {
          providerErrors[provider.id] = 'قیمت دریافت نشد';
          return;
        }

        if (quote.providerId != provider.id ||
            quote.symbol.toUpperCase() != symbol.toUpperCase() ||
            quote.market != market ||
            !quote.isValid ||
            !quote.isFresh(maximumAge: maximumQuoteAge)) {
          providerErrors[provider.id] = 'قیمت نامعتبر یا قدیمی است';
          return;
        }

        final volume = quote.volume.isFinite && quote.volume > 0
            ? quote.volume
            : 0.0;

        quoteByProvider[provider.id] = quote;

        candidates.add(
          ExchangeCandidate(
            id: provider.id,
            name: provider.name,
            market: market,
            type: ProviderType.exchange,
            enabled: true,
            connected: true,
            tradingAllowed: false,
            bid: quote.bid,
            ask: quote.ask,
            feeRate: 0,
            liquidity: volume,
            latencyMs: stopwatch.elapsedMilliseconds,
            availableBalance: 0,
          ),
        );

        providerErrors.remove(provider.id);
      } on TimeoutException {
        stopwatch.stop();
        providerErrors[provider.id] = 'مهلت دریافت قیمت تمام شد';
      } catch (error) {
        stopwatch.stop();
        providerErrors[provider.id] = error.toString();
      }
    });

    await Future.wait(futures);

    if (_disposed) return null;

    if (candidates.isEmpty) {
      lastQuoteStatus = 'دریافت قیمت از تمام منابع ناموفق بود';
      return null;
    }

    final routingResult = router.route(
      candidates,
      purpose: RoutingPurpose.marketData,
    );

    final selected = routingResult.selected;

    if (selected == null) {
      lastQuoteStatus = 'روتر هوشمند منبع قیمت مناسبی پیدا نکرد';
      return null;
    }

    final selectedQuote = quoteByProvider[selected.id];

    if (selectedQuote == null ||
        !selectedQuote.isFresh(maximumAge: maximumQuoteAge)) {
      lastQuoteStatus = 'قیمت منبع انتخاب‌شده دیگر معتبر نیست';
      return null;
    }

    lastSuccessfulQuote = DateTime.now();
    lastQuoteStatus = 'منبع هوشمند انتخاب‌شده: ${selected.name}';

    return selectedQuote;
  }

  // -------------------- ALL VALID QUOTES --------------------

  Future<List<MarketQuote>> collectQuotes(
    String symbol, {
    MarketType market = MarketType.crypto,
  }) async {
    if (_disposed || symbol.trim().isEmpty) return const [];

    final providers = registry.providersFor(market);

    if (providers.isEmpty) {
      lastQuoteStatus = 'هیچ منبع فعالی برای این بازار وجود ندارد';
      return const [];
    }

    final futures = providers.map((provider) async {
      try {
        final quote = await provider
            .fetchQuote(symbol)
            .timeout(quoteTimeout);

        if (_disposed || quote == null) return null;

        if (quote.providerId != provider.id ||
            quote.symbol.toUpperCase() != symbol.toUpperCase() ||
            quote.market != market ||
            !quote.isValid ||
            !quote.isFresh(maximumAge: maximumQuoteAge)) {
          providerErrors[provider.id] = 'قیمت نامعتبر یا قدیمی است';
          return null;
        }

        providerErrors.remove(provider.id);
        return quote;
      } on TimeoutException {
        providerErrors[provider.id] = 'مهلت دریافت قیمت تمام شد';
        return null;
      } catch (error) {
        providerErrors[provider.id] = error.toString();
        return null;
      }
    });

    final results = await Future.wait(futures);

    if (_disposed) return const [];

    final quotes = results.whereType<MarketQuote>().toList()
      ..sort((a, b) => a.spreadPercent.compareTo(b.spreadPercent));

    if (quotes.isEmpty) {
      lastQuoteStatus = 'دریافت قیمت از تمام منابع ناموفق بود';
      return const [];
    }

    lastSuccessfulQuote = DateTime.now();
    lastQuoteStatus = '${quotes.length} منبع قیمت معتبر در دسترس است';

    return quotes;
  }

  // -------------------- CANDLES --------------------

  Future<List<Candle>> fetchCandles(
    String symbol,
    String interval, {
    MarketType market = MarketType.crypto,
    int limit = 200,
  }) async {
    if (_disposed || symbol.trim().isEmpty) return const [];

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
        providerErrors[marketProvider.id] = 'مهلت دریافت کندل تمام شد';
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

    lastSuccessfulCandles = DateTime.now();

    lastCandleStatus =
        '${results.first.length} کندل معتبر دریافت شد';

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
