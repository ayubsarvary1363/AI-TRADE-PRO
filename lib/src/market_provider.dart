
import 'exchange_router.dart';

// =====================================================
// AI TRADE PRO
// Market Provider Interface - Version 0.5.0
// =====================================================

class MarketQuote {
  final String providerId;
  final String symbol;
  final MarketType market;
  final double bid;
  final double ask;
  final double volume;
  final DateTime timestamp;

  const MarketQuote({
    required this.providerId,
    required this.symbol,
    required this.market,
    required this.bid,
    required this.ask,
    required this.volume,
    required this.timestamp,
  });

  double get midPrice => (bid + ask) / 2;

  double get spread => ask - bid;

  double get spreadPercent {
    final mid = midPrice;
    if (mid <= 0) return 0;
    return spread / mid * 100;
  }

  bool get isValid {
    return providerId.isNotEmpty &&
        symbol.isNotEmpty &&
        bid > 0 &&
        ask > 0 &&
        ask >= bid &&
        volume >= 0 &&
        bid.isFinite &&
        ask.isFinite &&
        volume.isFinite;
  }

  bool isFresh({
    Duration maximumAge = const Duration(seconds: 30),
  }) {
    if (!isValid) return false;

    final age = DateTime.now().difference(timestamp);

    return !age.isNegative && age <= maximumAge;
  }
}

// -------------------- PROVIDER INTERFACE --------------------

abstract class MarketProvider {
  String get id;

  String get name;

  MarketType get market;

  Future<bool> checkConnection();

  Future<MarketQuote?> fetchQuote(String symbol);

  Future<void> close();
}

// -------------------- CONNECTION STATUS --------------------

class ProviderStatus {
  final String providerId;
  final String providerName;
  final MarketType market;
  final bool connected;
  final DateTime checkedAt;
  final String? error;

  const ProviderStatus({
    required this.providerId,
    required this.providerName,
    required this.market,
    required this.connected,
    required this.checkedAt,
    this.error,
  });
}

// -------------------- PROVIDER REGISTRY --------------------

class MarketProviderRegistry {
  final Map<String, MarketProvider> _providers = {};

  List<MarketProvider> get providers =>
      List.unmodifiable(_providers.values);

  int get length => _providers.length;

  bool get isEmpty => _providers.isEmpty;

  void register(MarketProvider provider) {
    if (provider.id.trim().isEmpty) {
      throw ArgumentError('شناسه منبع بازار نمی‌تواند خالی باشد');
    }

    if (_providers.containsKey(provider.id)) {
      throw StateError(
        'منبعی با این شناسه قبلاً ثبت شده است: ${provider.id}',
      );
    }

    _providers[provider.id] = provider;
  }

  MarketProvider? getProvider(String id) => _providers[id];

  List<MarketProvider> providersFor(MarketType market) {
    return _providers.values
        .where((provider) => provider.market == market)
        .toList(growable: false);
  }

  Future<bool> unregister(String id) async {
    final provider = _providers.remove(id);

    if (provider == null) return false;

    await provider.close();
    return true;
  }

  Future<void> closeAll() async {
    final current = _providers.values.toList();
    _providers.clear();

    await Future.wait(
      current.map((provider) async {
        try {
          await provider.close();
        } catch (_) {
          // خطای بستن یک منبع نباید مانع بستن بقیه شود.
        }
      }),
    );
  }
}

// -------------------- CONNECTION CHECKER --------------------

class MarketConnectionChecker {
  final MarketProviderRegistry registry;

  MarketConnectionChecker(this.registry);

  Future<List<ProviderStatus>> checkAll() async {
    final results = await Future.wait(
      registry.providers.map((provider) async {
        try {
          final connected = await provider
              .checkConnection()
              .timeout(const Duration(seconds: 10));

          return ProviderStatus(
            providerId: provider.id,
            providerName: provider.name,
            market: provider.market,
            connected: connected,
            checkedAt: DateTime.now(),
          );
        } catch (error) {
          return ProviderStatus(
            providerId: provider.id,
            providerName: provider.name,
            market: provider.market,
            connected: false,
            checkedAt: DateTime.now(),
            error: error.toString(),
          );
        }
      }),
    );

    return results;
  }
}
