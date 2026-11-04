
import 'exchange_router.dart';
import 'market_provider.dart';

class MarketHub {
  final MarketProviderRegistry registry;
  final MarketConnectionChecker connectionChecker;
  final SmartExchangeRouter router;

  MarketHub({
    required this.registry,
    MarketConnectionChecker? connectionChecker,
    SmartExchangeRouter? router,
  })  : connectionChecker =
            connectionChecker ?? MarketConnectionChecker(),
        router = router ?? const SmartExchangeRouter();

  Future<List<MarketConnectionStatus>> checkConnections({
    required MarketType market,
  }) {
    final providers = registry.providersFor(market);
    return connectionChecker.checkAll(providers);
  }

  Future<List<MarketQuote>> collectQuotes({
    required MarketType market,
    required String symbol,
  }) async {
    final providers = registry.providersFor(market);

    final quotes = <MarketQuote>[];

    for (final provider in providers) {
      try {
        final quote = await provider
            .fetchQuote(symbol)
            .timeout(const Duration(seconds: 12));

        if (quote.isValid &&
            quote.market == market &&
            quote.symbol == symbol &&
            quote.providerId == provider.id) {
          quotes.add(quote);
        }
      } catch (_) {
        // خطای یک منبع نباید کل منابع دیگر را متوقف کند.
        continue;
      }
    }

    return quotes;
  }

  ExchangeRouteResult selectRoute({
    required MarketType market,
    required List<ExchangeCandidate> candidates,
    required double orderValue,
  }) {
    return router.selectBest(
      market: market,
      candidates: candidates,
      orderValue: orderValue,
    );
  }

  Future<void> dispose() async {
    await registry.closeAll();
  }
}
