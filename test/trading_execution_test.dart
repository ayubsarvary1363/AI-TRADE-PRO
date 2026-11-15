import 'package:flutter_test/flutter_test.dart';
import 'package:rise_s_trade/src/exchange_router.dart';
import 'package:rise_s_trade/src/market_provider.dart';
import 'package:rise_s_trade/src/trading_execution.dart';

void main() {
  MarketQuote quote({DateTime? time}) => MarketQuote(
        providerId: 'binance',
        symbol: 'BTCUSDT',
        market: MarketType.crypto,
        bid: 60000,
        ask: 60001,
        volume: 100,
        timestamp: time ?? DateTime.now(),
      );

  group('CapitalProtectionGate', () {
    const gate = CapitalProtectionGate(CapitalProtectionConfig());

    test('approves a small order with fresh quote and healthy equity', () {
      final decision = gate.evaluate(RiskSnapshot(
        equityUsdt: 100,
        dailyRealizedLossUsdt: 0,
        peakEquityUsdt: 100,
        proposedOrderUsdt: 5,
        quote: quote(),
      ));
      expect(decision.approved, isTrue);
      expect(decision.allowedOrderUsdt, 5);
    });

    test('rejects stale quote', () {
      final decision = gate.evaluate(RiskSnapshot(
        equityUsdt: 100,
        dailyRealizedLossUsdt: 0,
        peakEquityUsdt: 100,
        proposedOrderUsdt: 5,
        quote: quote(time: DateTime.now().subtract(const Duration(minutes: 1))),
      ));
      expect(decision.approved, isFalse);
    });

    test('blocks after daily loss limit', () {
      final decision = gate.evaluate(RiskSnapshot(
        equityUsdt: 99,
        dailyRealizedLossUsdt: 1,
        peakEquityUsdt: 100,
        proposedOrderUsdt: 5,
        quote: quote(),
      ));
      expect(decision.approved, isFalse);
    });

    test('blocks after maximum drawdown', () {
      final decision = gate.evaluate(RiskSnapshot(
        equityUsdt: 95,
        dailyRealizedLossUsdt: 0,
        peakEquityUsdt: 100,
        proposedOrderUsdt: 5,
        quote: quote(),
      ));
      expect(decision.approved, isFalse);
    });

    test('caps order size to configured maximum', () {
      final decision = gate.evaluate(RiskSnapshot(
        equityUsdt: 100,
        dailyRealizedLossUsdt: 0,
        peakEquityUsdt: 100,
        proposedOrderUsdt: 50,
        quote: quote(),
      ));
      expect(decision.approved, isTrue);
      expect(decision.allowedOrderUsdt, 10);
    });
  });

  test('OrderSubmissionGuard rejects duplicate client IDs', () {
    final guard = OrderSubmissionGuard();
    guard.markSubmitted('client-1');
    expect(guard.hasBeenSubmitted('client-1'), isTrue);
    expect(() => guard.markSubmitted('client-1'), throwsStateError);
  });

  test('live trading is disabled by default', () {
    expect(const CapitalProtectionConfig().allowLiveTrading, isFalse);
    expect(const CapitalProtectionConfig().spotOnly, isTrue);
  });
}
