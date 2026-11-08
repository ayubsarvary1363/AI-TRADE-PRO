
import 'dart:async';

import 'exchange_router.dart';
import 'market_provider.dart';

// =====================================================
// AI TRADE PRO
// Multi-Provider Market Hub - Version 0.5.0
// Parallel market data collection
// =====================================================

class MarketHub {
  final MarketProviderRegistry registry;

  final Duration requestTimeout;
  final Duration maximumQuoteAge;

  bool _disposed = false;

  MarketHub({
    required this.registry,
    this.requestTimeout = const Duration(seconds: 10),
    this.maximumQuoteAge = const Duration(seconds: 30),
  });

  bool get isDisposed => _disposed;

  // -------------------- COLLECT QUOTES --------------------

  Future<List<MarketQuote>> collectQuotes(
    String symbol, {
    MarketType market = MarketType.crypto,
  }) async {
    if (_disposed || symbol.trim().isEmpty) {
      return const [];
    }

    final providers = registry.providersFor(market);

    if (providers.isEmpty) return const [];

    final futures = providers.map((provider) async {
      try {
        final quote = await provider
            .fetchQuote(symbol)
            .timeout(requestTimeout);

        if (quote == null) return null;

        if (quote.providerId != provider.id ||
            quote.symbol.toUpperCase() != symbol.toUpperCase() ||
            quote.market != market ||
            !quote.isFresh(maximumAge: maximumQuoteAge)) {
          return null;
        }

        return quote;
      } catch (_) {
        return null;
      }
    });

    final results = await Future.wait(futures);

    if (_disposed) return const [];

    return results.whereType<MarketQuote>().toList()
      ..sort((a, b) {
        // در این مرحله قیمت‌های معتبر با اسپرد کمتر اولویت دارند.
        return a.spreadPercent.compareTo(b.spreadPercent);
      });
  }

  // -------------------- BEST QUOTE --------------------

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

  // -------------------- CONNECTION STATUS --------------------

  Future<List<ProviderStatus>> checkConnections() async {
    if (_disposed) return const [];

    final checker = MarketConnectionChecker(registry);
    return checker.checkAll();
  }

  // -------------------- PROVIDER INFORMATION --------------------

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
