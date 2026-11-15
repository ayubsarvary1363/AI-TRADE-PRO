import 'dart:collection';

import 'exchange_router.dart';
import 'market_provider.dart';

/// Execution remains disabled until the user explicitly enables live mode.
enum ExecutionMode { paper, testnet, live }

enum SpotOrderSide { buy, sell }
enum SpotOrderType { market, limit }
enum OrderState { pending, open, partiallyFilled, filled, canceled, rejected, unknown }

class SpotOrderRequest {
  final String symbol;
  final SpotOrderSide side;
  final SpotOrderType type;
  final double quantity;
  final double? limitPrice;
  final String clientOrderId;

  const SpotOrderRequest({
    required this.symbol,
    required this.side,
    required this.type,
    required this.quantity,
    required this.clientOrderId,
    this.limitPrice,
  });

  bool get isValid =>
      symbol.trim().isNotEmpty &&
      quantity > 0 &&
      quantity.isFinite &&
      clientOrderId.trim().isNotEmpty &&
      (type != SpotOrderType.limit ||
          (limitPrice != null && limitPrice! > 0 && limitPrice!.isFinite));
}

class SpotOrderResult {
  final String exchangeId;
  final String orderId;
  final String clientOrderId;
  final OrderState state;
  final double executedQuantity;
  final double cumulativeQuote;
  final double fee;
  final String feeAsset;
  final DateTime updatedAt;
  final String? message;

  const SpotOrderResult({
    required this.exchangeId,
    required this.orderId,
    required this.clientOrderId,
    required this.state,
    required this.executedQuantity,
    required this.cumulativeQuote,
    required this.fee,
    required this.feeAsset,
    required this.updatedAt,
    this.message,
  });
}

class ExchangeBalance {
  final String asset;
  final double free;
  final double locked;

  const ExchangeBalance({
    required this.asset,
    required this.free,
    required this.locked,
  });
}

/// A trading adapter is deliberately separate from MarketProvider.
/// Implementations must never support margin, futures or withdrawals.
abstract class SpotTradingProvider {
  String get id;
  String get name;
  MarketType get market;
  bool get supportsSpot;
  Future<bool> checkTradingConnection();
  Future<List<ExchangeBalance>> fetchBalances();
  Future<SpotOrderResult> submitSpotOrder(SpotOrderRequest request);
  Future<SpotOrderResult> fetchOrder({
    required String symbol,
    required String orderId,
  });
  Future<void> cancelOrder({
    required String symbol,
    required String orderId,
  });
  Future<void> close();
}

class CapitalProtectionConfig {
  final double maxCapitalUsdt;
  final double maxOrderUsdt;
  final double riskPerTradePercent;
  final double dailyLossLimitPercent;
  final double maxDrawdownPercent;
  final double maxQuoteAgeSeconds;
  final bool spotOnly;
  final bool allowLiveTrading;

  const CapitalProtectionConfig({
    this.maxCapitalUsdt = 100,
    this.maxOrderUsdt = 10,
    this.riskPerTradePercent = 0.5,
    this.dailyLossLimitPercent = 1,
    this.maxDrawdownPercent = 5,
    this.maxQuoteAgeSeconds = 10,
    this.spotOnly = true,
    this.allowLiveTrading = false,
  });

  bool get isValid =>
      maxCapitalUsdt > 0 &&
      maxCapitalUsdt.isFinite &&
      maxOrderUsdt > 0 &&
      maxOrderUsdt <= maxCapitalUsdt &&
      maxOrderUsdt.isFinite &&
      riskPerTradePercent > 0 &&
      riskPerTradePercent <= 1 &&
      dailyLossLimitPercent > 0 &&
      dailyLossLimitPercent <= 1 &&
      maxDrawdownPercent > 0 &&
      maxDrawdownPercent <= 5 &&
      maxQuoteAgeSeconds >= 1 &&
      spotOnly;
}

class RiskSnapshot {
  final double equityUsdt;
  final double dailyRealizedLossUsdt;
  final double peakEquityUsdt;
  final double proposedOrderUsdt;
  final MarketQuote quote;

  const RiskSnapshot({
    required this.equityUsdt,
    required this.dailyRealizedLossUsdt,
    required this.peakEquityUsdt,
    required this.proposedOrderUsdt,
    required this.quote,
  });
}

class RiskDecision {
  final bool approved;
  final String reason;
  final double allowedOrderUsdt;

  const RiskDecision({
    required this.approved,
    required this.reason,
    this.allowedOrderUsdt = 0,
  });
}

/// Fail-closed risk gate. It rejects stale/invalid quotes, invalid balances,
/// excessive order sizes, daily loss breaches and equity drawdown breaches.
class CapitalProtectionGate {
  final CapitalProtectionConfig config;

  const CapitalProtectionGate(this.config);

  RiskDecision evaluate(RiskSnapshot snapshot) {
    if (!config.isValid) {
      return const RiskDecision(approved: false, reason: 'تنظیمات حفاظت سرمایه نامعتبر است');
    }
    if (!snapshot.quote.isValid ||
        !snapshot.quote.isFresh(
          maximumAge: Duration(
            milliseconds: (config.maxQuoteAgeSeconds * 1000).round(),
          ),
        )) {
      return const RiskDecision(approved: false, reason: 'قیمت بازار معتبر یا به‌روز نیست');
    }
    if (!snapshot.equityUsdt.isFinite ||
        snapshot.equityUsdt <= 0 ||
        !snapshot.dailyRealizedLossUsdt.isFinite ||
        snapshot.dailyRealizedLossUsdt < 0 ||
        !snapshot.peakEquityUsdt.isFinite ||
        snapshot.peakEquityUsdt <= 0 ||
        !snapshot.proposedOrderUsdt.isFinite ||
        snapshot.proposedOrderUsdt <= 0) {
      return const RiskDecision(approved: false, reason: 'اطلاعات موجودی یا اندازه سفارش نامعتبر است');
    }
    final dailyLimit = config.maxCapitalUsdt * config.dailyLossLimitPercent / 100;
    if (snapshot.dailyRealizedLossUsdt >= dailyLimit) {
      return const RiskDecision(approved: false, reason: 'سقف زیان روزانه پر شده است');
    }
    final drawdown = (snapshot.peakEquityUsdt - snapshot.equityUsdt) /
        snapshot.peakEquityUsdt * 100;
    if (drawdown >= config.maxDrawdownPercent) {
      return const RiskDecision(approved: false, reason: 'حداکثر افت سرمایه فعال شده است');
    }
    final allowed = [
      config.maxCapitalUsdt,
      config.maxOrderUsdt,
      snapshot.equityUsdt,
      snapshot.proposedOrderUsdt,
    ].reduce((a, b) => a < b ? a : b);
    if (allowed <= 0) {
      return const RiskDecision(approved: false, reason: 'سرمایه مجاز کافی نیست');
    }
    return RiskDecision(
      approved: true,
      reason: 'سفارش از کنترل‌های اولیه حفاظت سرمایه عبور کرد',
      allowedOrderUsdt: allowed,
    );
  }
}

/// Prevents duplicate submissions during retries within this process.
/// Persist client IDs before enabling production execution.
class OrderSubmissionGuard {
  final int maximumRememberedIds;
  final LinkedHashSet<String> _submitted = LinkedHashSet<String>();

  OrderSubmissionGuard({this.maximumRememberedIds = 2000});

  bool hasBeenSubmitted(String clientOrderId) =>
      _submitted.contains(clientOrderId);

  void markSubmitted(String clientOrderId) {
    final id = clientOrderId.trim();
    if (id.isEmpty) throw ArgumentError('clientOrderId cannot be empty');
    if (_submitted.contains(id)) {
      throw StateError('Duplicate client order ID');
    }
    _submitted.add(id);
    while (_submitted.length > maximumRememberedIds) {
      _submitted.remove(_submitted.first);
    }
  }
}
