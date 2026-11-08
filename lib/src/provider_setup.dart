
import 'exchange_router.dart';
import 'market_provider.dart';
import 'kraken_provider.dart';
import 'coinbase_provider.dart';

class ProviderSetup {
  ProviderSetup._();

  static MarketProviderRegistry createRegistry() {
    final registry = MarketProviderRegistry();

    // تأمین‌کنندگان عمومی داده بازار رمزارز
    registry.register(KrakenProvider());
    registry.register(CoinbaseProvider());

    return registry;
  }

  static List<MarketType> get supportedMarkets => [
        MarketType.crypto,
      ];

  static List<MarketType> get plannedMarkets => [
        MarketType.forex,
        MarketType.stocks,
        MarketType.commodities,
        MarketType.indices,
      ];

  static bool isMarketSupported(MarketType market) {
    return supportedMarkets.contains(market);
  }

  static String marketStatus(MarketType market) {
    if (isMarketSupported(market)) {
      return 'فعال';
    }

    return 'در حال توسعه';
  }

  static List<String> get activeProviderNames => [
        'Kraken',
        'Coinbase',
      ];
}
