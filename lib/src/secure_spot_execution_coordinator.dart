import 'trading_execution.dart';
import 'exchange_router.dart';
import 'market_provider.dart';

/// Routes a single Spot order to the best eligible registered adapter.
/// This coordinator deliberately refuses live mode until a separately
/// reviewed production adapter and explicit live-consent flow exist.
class SecureSpotExecutionCoordinator {
  final SmartExchangeRouter router;
  final CapitalProtectionGate protection;
  final OrderSubmissionGuard submissionGuard;
  final Map<String, SpotTradingProvider> providers;

  SecureSpotExecutionCoordinator({
    required this.protection,
    required this.providers,
    SmartExchangeRouter? router,
    OrderSubmissionGuard? submissionGuard,
  })  : router = router ?? const SmartExchangeRouter(),
        submissionGuard = submissionGuard ?? OrderSubmissionGuard();

  Future<SpotOrderResult> execute({
    required ExecutionMode mode,
    required SpotOrderRequest request,
    required MarketQuote quote,
    required List<ExchangeCandidate> candidates,
    required RiskSnapshot account,
  }) async {
    if (mode != ExecutionMode.testnet) {
      throw StateError('اجرای سفارش فقط در محیط آزمایشی مجاز است');
    }
    if (!request.isValid || !quote.isValid || quote.symbol != request.symbol) {
      throw ArgumentError('نماد یا مشخصات سفارش با قیمت بازار سازگار نیست');
    }
    if (submissionGuard.hasBeenSubmitted(request.clientOrderId)) {
      throw StateError('این سفارش قبلاً ارسال شده یا وضعیت آن باید بررسی شود');
    }

    final estimatedPrice = request.type == SpotOrderType.limit
        ? request.limitPrice!
        : request.side == SpotOrderSide.buy
            ? quote.ask
            : quote.bid;
    final orderValue = request.quantity * estimatedPrice;
    final decision = protection.evaluate(RiskSnapshot(
      equityUsdt: account.equityUsdt,
      dailyRealizedLossUsdt: account.dailyRealizedLossUsdt,
      peakEquityUsdt: account.peakEquityUsdt,
      proposedOrderUsdt: orderValue,
      quote: quote,
    ));
    if (!decision.approved) {
      throw StateError(decision.reason);
    }
    if (orderValue > decision.allowedOrderUsdt + 0.00000001) {
      throw StateError('مبلغ سفارش از سقف مجاز حفاظت سرمایه بیشتر است');
    }

    final route = router.route(
      candidates: candidates,
      market: MarketType.crypto,
      purpose: RoutingPurpose.orderExecution,
      orderValue: orderValue,
    );
    final selected = route.selected;
    if (selected == null) throw StateError(route.explanation);
    final provider = providers[selected.id];
    if (provider == null || !provider.supportsSpot ||
        provider.market != MarketType.crypto) {
      throw StateError('آداپتور Spot برای صرافی منتخب ثبت نشده است');
    }

    // Mark before network I/O. If a request times out, reconcile this same
    // clientOrderId with the exchange; do not create a new order ID and retry.
    submissionGuard.markSubmitted(request.clientOrderId);
    return provider.submitSpotOrder(request);
  }
}
