
import 'exchange_router.dart';
import 'market_provider.dart';
import 'kraken_provider.dart';

// =====================================================
// AI TRADE PRO
// Provider Setup - Version 0.8.0
// Kraken primary market data
// =====================================================

class ProviderSetup {
  ProviderSetup._();

  static MarketProviderRegistry createRegistry() {
    final registry = MarketProviderRegistry();

    // منبع فعال دریافت اطلاعات بازار رمزارز
    registry.register(KrakenProvider());

    return registry;
  }

  // بازارهایی که در این نسخه منبع فعال دارند
  static List<MarketType> get supportedMarkets => [
        MarketType.crypto,
      ];

  // بازارهایی که هنوز اتصال فعال ندارند
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
    if (market == MarketType.crypto) {
      return 'دریافت اطلاعات از Kraken';
    }

    if (plannedMarkets.contains(market)) {
      return 'در انتظار اتصال تأمین‌کننده';
    }

    return 'پشتیبانی نمی‌شود';
  }
}
