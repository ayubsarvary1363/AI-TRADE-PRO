
import 'dart:async';

import 'exchange_router.dart';

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

  double get midpoint => (bid + ask) / 2;

  bool get isValid {
    return bid.isFinite &&
        ask.isFinite &&
        volume.isFinite &&
        bid > 0 &&
        ask >= bid &&
        volume >= 0;
  }
}

abstract class MarketProvider {
  String get id;

  String get name;

  MarketType get market;

  Future<bool> checkConnection();

  Future<MarketQuote> fetchQuote(String symbol);

  Future<void> close();
}

class MarketProviderException implements Exception {
  final String message;

  const MarketProviderException(this.message);

  @override
  String toString() => message;
}

class MarketProviderRegistry {
  final Map<String, MarketProvider> _providers = {};

  void register(MarketProvider provider) {
    if (provider.id.trim().isEmpty) {
      throw const MarketProviderException(
        'شناسه ارائه‌دهنده معتبر نیست.',
      );
    }

    _providers[provider.id] = provider;
  }

  void unregister(String id) {
    _providers.remove(id);
  }

  MarketProvider? getProvider(String id) {
    return _providers[id];
  }

  List<MarketProvider> providersFor(MarketType market) {
    return _providers.values
        .where((provider) => provider.market == market)
        .toList(growable: false);
  }

  List<String> get providerIds =>
      List.unmodifiable(_providers.keys);

  Future<void> closeAll() async {
    for (final provider in _providers.values) {
      await provider.close();
    }

    _providers.clear();
  }
}

class MarketConnectionStatus {
  final String providerId;
  final String providerName;
  final bool connected;
  final String message;

  const MarketConnectionStatus({
    required this.providerId,
    required this.providerName,
    required this.connected,
    required this.message,
  });
}

class MarketConnectionChecker {
  Future<List<MarketConnectionStatus>> checkAll(
    List<MarketProvider> providers,
  ) async {
    final results = <MarketConnectionStatus>[];

    for (final provider in providers) {
      try {
        final connected = await provider
            .checkConnection()
            .timeout(const Duration(seconds: 10));

        results.add(
          MarketConnectionStatus(
            providerId: provider.id,
            providerName: provider.name,
            connected: connected,
            message: connected
                ? 'اتصال برقرار است.'
                : 'اتصال برقرار نشد.',
          ),
        );
      } catch (e) {
        results.add(
          MarketConnectionStatus(
            providerId: provider.id,
            providerName: provider.name,
            connected: false,
            message: 'خطای اتصال: $e',
          ),
        );
      }
    }

    return results;
  }
}
