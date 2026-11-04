
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
  final double latencyMs;
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

  bool get isEligible {
    return enabled &&
        connected &&
        tradingAllowed &&
        bid.isFinite &&
        ask.isFinite &&
        feeRate.isFinite &&
        liquidity.isFinite &&
        latencyMs.isFinite &&
        availableBalance.isFinite &&
        bid > 0 &&
        ask >= bid &&
        feeRate >= 0 &&
        liquidity > 0 &&
        latencyMs >= 0 &&
        availableBalance > 0;
  }

  double get spreadRate {
    final midpoint = (bid + ask) / 2;
    if (midpoint <= 0) return double.infinity;
    return (ask - bid) / midpoint;
  }

  double estimatedCost({
    required double orderValue,
  }) {
    if (orderValue <= 0 ||
        !orderValue.isFinite ||
        !isEligible) {
      return double.infinity;
    }

    final spreadCost = orderValue * spreadRate;
    final feeCost = orderValue * feeRate;

    return spreadCost + feeCost;
  }
}

class ExchangeRouteResult {
  final ExchangeCandidate? selected;
  final List<String> reasons;
  final String message;

  const ExchangeRouteResult({
    required this.selected,
    required this.reasons,
    required this.message,
  });

  bool get hasRoute => selected != null;
}

class SmartExchangeRouter {
  const SmartExchangeRouter();

  ExchangeRouteResult selectBest({
    required MarketType market,
    required List<ExchangeCandidate> candidates,
    required double orderValue,
  }) {
    if (!orderValue.isFinite || orderValue <= 0) {
      return const ExchangeRouteResult(
        selected: null,
        reasons: [],
        message: 'حجم سفارش معتبر نیست.',
      );
    }

    final eligible = candidates.where((candidate) {
      return candidate.market == market &&
          candidate.isEligible &&
          candidate.availableBalance >= orderValue;
    }).toList();

    if (eligible.isEmpty) {
      return const ExchangeRouteResult(
        selected: null,
        reasons: [],
        message: 'هیچ اتصال واجد شرایطی پیدا نشد.',
      );
    }

    eligible.sort((a, b) {
      final costA = a.estimatedCost(
        orderValue: orderValue,
      );

      final costB = b.estimatedCost(
        orderValue: orderValue,
      );

      final costComparison = costA.compareTo(costB);

      if (costComparison != 0) {
        return costComparison;
      }

      final liquidityComparison =
          b.liquidity.compareTo(a.liquidity);

      if (liquidityComparison != 0) {
        return liquidityComparison;
      }

      return a.latencyMs.compareTo(b.latencyMs);
    });

    final best = eligible.first;

    return ExchangeRouteResult(
      selected: best,
      reasons: [
        'اتصال فعال و مجاز است.',
        'موجودی کافی دارد.',
        'هزینه تخمینی شامل اسپرد و کارمزد بررسی شده است.',
        'نقدشوندگی و تأخیر اتصال مقایسه شده‌اند.',
      ],
      message: 'بهترین اتصال واجد شرایط انتخاب شد.',
    );
  }
}
