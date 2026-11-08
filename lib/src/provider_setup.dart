
import 'exchange_router.dart';
import 'market_provider.dart';
import 'binance_provider.dart';

// =====================================================
// AI TRADE PRO
// Provider Setup - Version 0.5.0
// =====================================================

class ProviderSetup {
  ProviderSetup._();

  // ساخت فهرست منابع داده فعال
  static MarketProviderRegistry createRegistry() {
    final registry = MarketProviderRegistry();

    // دریافت داده عمومی بازار رمزارز
    registry.register(BinanceProvider());

    return registry;
  }

  // بازارهایی که در این نسخه واقعاً منبع داده دارند
  static List<MarketType> get supportedMarkets => [
        MarketType.crypto,
      ];

  // بازارهایی که در معماری آینده در نظر گرفته شده‌اند
  // این فهرست به معنی اتصال فعال نیست.
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
    if (supportedMarkets.contains(market)) {
      return 'منبع داده ثبت شده';
    }

    if (plannedMarkets.contains(market)) {
      return 'در انتظار پیاده‌سازی اتصال';
    }

    return 'پشتیبانی نمی‌شود';
  }
}
