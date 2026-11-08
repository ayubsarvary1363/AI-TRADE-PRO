
import 'dart:async';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

// =====================================================
// AI TRADE PRO
// Market Hub Version 0.8.0
// Multi-provider + diagnostics + fallback
// =====================================================

class MarketHub {
  final MarketProviderRegistry registry;

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
    this.quoteTimeout = const Duration(seconds: 7),
    this.candleTimeout = const Duration(seconds: 12),
    this.maximumQuoteAge = const Duration(seconds: 15),
  });

  bool get isDisposed => _disposed;

  // -------------------- QUOTES --------------------

  Future<List<MarketQuote>> collectQuotes(
    String symbol, {
    MarketType market = MarketType.crypto,
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
      try {
        final quote = await provider
            .fetchQuote(symbol)
            .timeout(quoteTimeout);

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

    lastQuoteStatus = 'قیمت معتبر از ${quotes.first.providerId} دریافت شد';
    lastSuccessfulQuote = DateTime.now();

    return quotes;
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
