
import 'exchange_router.dart';
import 'market_provider.dart';
import 'binance_provider.dart';

class ProviderSetup {
  ProviderSetup._();

  static MarketProviderRegistry createRegistry() {
    final registry = MarketProviderRegistry();

    // منبع آزمایشی اطلاعات بازار رمزارز
    registry.register(BinanceProvider());

    return registry;
  }

  static List<MarketType> get supportedMarkets => [
        MarketType.crypto,
        MarketType.forex,
        MarketType.stocks,
        MarketType.commodities,
        MarketType.indices,
      ];
}
