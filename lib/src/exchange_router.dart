
// =====================================================
// AI TRADE PRO
// Smart Provider Router - Version 0.5.0
// Separate market-data routing from order execution
// =====================================================

enum MarketType {
  crypto,
  forex,
  stocks,
  commodities,
  indices,
}

enum ProviderType {
  exchange,
  broker,
  dataProvider,
}

enum RoutingPurpose {
  marketData,
  orderExecution,
}

// -------------------- EXCHANGE CANDIDATE --------------------

class ExchangeCandidate {
  final String id;
  final String name;
  final MarketType market;
  final ProviderType type;

  final bool enabled;
  final bool connected;
  final bool tradingAllowed;

  final double bid;
  final double ask;
  final double feeRate;
  final double liquidity;
  final int latencyMs;
  final double availableBalance;

  const ExchangeCandidate({
    required this.id,
    required this.name,
    required this.market,
    required this.type,
    required this.enabled,
    required this.connected,
    required this.tradingAllowed,
    required this.bid,
    required this.ask,
    required this.feeRate,
    required this.liquidity,
    required this.latencyMs,
    required this.availableBalance,
  });

  bool get hasValidQuote =>
      bid > 0 &&
      ask >= bid &&
      bid.isFinite &&
      ask.isFinite;

  bool get isEligibleForData {
    return enabled &&
        connected &&
        hasValidQuote &&
        latencyMs >= 0;
  }

  bool get isEligibleForTrading {
    return enabled &&
        connected &&
        tradingAllowed &&
        type != ProviderType.dataProvider &&
        hasValidQuote &&
        feeRate >= 0 &&
        feeRate.isFinite &&
        availableBalance > 0 &&
        availableBalance.isFinite;
  }

  double get spreadPercent {
    if (!hasValidQuote) return double.infinity;

    final mid = (bid + ask) / 2;
    if (mid <= 0) return double.infinity;

    return ((ask - bid) / mid) * 100;
  }

  double estimatedCost({
    double orderValue = 100,
  }) {
    if (!hasValidQuote ||
        orderValue <= 0 ||
        !feeRate.isFinite ||
        feeRate < 0) {
      return double.infinity;
    }

    final spreadCost = (ask - bid) / ((ask + bid) / 2);
    final feeCost = feeRate * 2;

    return orderValue * (spreadCost + feeCost);
  }
}

// -------------------- ROUTING RESULT --------------------

class RoutingResult {
  final ExchangeCandidate? selected;
  final List<ExchangeCandidate> ranked;
  final RoutingPurpose purpose;
  final String explanation;

  const RoutingResult({
    required this.selected,
    required this.ranked,
    required this.purpose,
    required this.explanation,
  });

  bool get hasSelection => selected != null;
}

// -------------------- SMART ROUTER --------------------

class SmartExchangeRouter {
  const SmartExchangeRouter();

  RoutingResult route({
    required List<ExchangeCandidate> candidates,
    required MarketType market,
    required RoutingPurpose purpose,
    double orderValue = 100,
  }) {
    final matching = candidates.where((candidate) {
      if (candidate.market != market) return false;

      if (purpose == RoutingPurpose.marketData) {
        return candidate.isEligibleForData;
      }

      return candidate.isEligibleForTrading;
    }).toList();

    matching.sort((a, b) {
      final costA = a.estimatedCost(orderValue: orderValue);
      final costB = b.estimatedCost(orderValue: orderValue);

      final costComparison = costA.compareTo(costB);
      if (costComparison != 0) return costComparison;

      // در هزینه برابر، نقدشوندگی بالاتر اولویت دارد.
      final liquidityComparison =
          b.liquidity.compareTo(a.liquidity);

      if (liquidityComparison != 0) {
        return liquidityComparison;
      }

      return a.latencyMs.compareTo(b.latencyMs);
    });

    if (matching.isEmpty) {
      return RoutingResult(
        selected: null,
        ranked: const [],
        purpose: purpose,
        explanation: purpose == RoutingPurpose.marketData
            ? 'منبع قیمت معتبر و متصل پیدا نشد'
            : 'هیچ محل اجرای سفارش واجد شرایط نیست',
      );
    }

    return RoutingResult(
      selected: matching.first,
      ranked: List.unmodifiable(matching),
      purpose: purpose,
      explanation: purpose == RoutingPurpose.marketData
          ? 'منبع قیمت بر اساس هزینه، نقدشوندگی و سرعت انتخاب شد'
          : 'محل اجرای سفارش بر اساس هزینه، نقدشوندگی و سرعت انتخاب شد',
    );
  }

  ExchangeCandidate? selectBest({
    required List<ExchangeCandidate> candidates,
    required MarketType market,
    double orderValue = 100,
  }) {
    return route(
      candidates: candidates,
      market: market,
      purpose: RoutingPurpose.orderExecution,
      orderValue: orderValue,
    ).selected;
  }

  List<ExchangeCandidate> rankCandidates({
    required List<ExchangeCandidate> candidates,
    required MarketType market,
    double orderValue = 100,
  }) {
    return route(
      candidates: candidates,
      market: market,
      purpose: RoutingPurpose.orderExecution,
      orderValue: orderValue,
    ).ranked;
  }
}
