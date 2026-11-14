import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';

/// Local durable snapshot for the demo portfolio. Live funds are never stored here.
class PortfolioPersistence {
  static const _key = 'rise_s_trade.demo_portfolio.v1';
  static const _runtimeKey = 'rise_s_trade.runtime_state.v1';

  static Future<void> saveRuntimeState({
    required String market,
    required String symbol,
    required String interval,
    required String style,
    double? activeStopPrice,
    double? initialRiskDistance,
    double? highestPriceSinceEntry,
    DateTime? cooldownUntil,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_runtimeKey, jsonEncode({
      'market': market,
      'symbol': symbol,
      'interval': interval,
      'style': style,
      'activeStopPrice': activeStopPrice,
      'initialRiskDistance': initialRiskDistance,
      'highestPriceSinceEntry': highestPriceSinceEntry,
      'cooldownUntil': cooldownUntil?.toIso8601String(),
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    }));
  }

  static Future<Map<String, dynamic>?> restoreRuntimeState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_runtimeKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(PaperPortfolio portfolio) async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = <String, dynamic>{
      'cashUsdt': portfolio.cashUsdt,
      'peakEquity': portfolio.peakEquity,
      'dayStartingEquity': portfolio.dayStartingEquity,
      'positions': portfolio.positions.values.map((p) => {
        'symbol': p.symbol,
        'quantity': p.quantity,
        'averageEntryPrice': p.averageEntryPrice,
      }).toList(),
      'fills': portfolio.fills.map((f) => {
        'id': f.id,
        'symbol': f.symbol,
        'side': f.side.name,
        'price': f.price,
        'quantity': f.quantity,
        'fee': f.fee,
        'realizedPnl': f.realizedPnl,
        'time': f.time.toIso8601String(),
      }).toList(),
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await prefs.setString(_key, jsonEncode(snapshot));
  }

  static Future<bool> restore(PaperPortfolio portfolio) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return false;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      double number(dynamic value, double fallback) =>
          value is num && value.isFinite ? value.toDouble() : fallback;
      portfolio.cashUsdt = number(data['cashUsdt'], portfolio.initialUsdt);
      portfolio.peakEquity = number(data['peakEquity'], portfolio.initialUsdt);
      portfolio.dayStartingEquity = number(
        data['dayStartingEquity'], portfolio.initialUsdt,
      );
      portfolio.positions.clear();
      for (final item in (data['positions'] as List? ?? const [])) {
        final row = item as Map<String, dynamic>;
        final symbol = row['symbol'] as String? ?? '';
        final quantity = number(row['quantity'], 0);
        final entry = number(row['averageEntryPrice'], 0);
        if (symbol.isNotEmpty && quantity > 0 && entry > 0) {
          portfolio.positions[symbol] = PaperPosition(
            symbol: symbol,
            quantity: quantity,
            averageEntryPrice: entry,
          );
        }
      }
      portfolio.fills.clear();
      for (final item in (data['fills'] as List? ?? const [])) {
        final row = item as Map<String, dynamic>;
        final sideName = row['side'] as String? ?? 'hold';
        final side = SignalDirection.values.firstWhere(
          (value) => value.name == sideName,
          orElse: () => SignalDirection.hold,
        );
        final time = DateTime.tryParse(row['time'] as String? ?? '');
        if (time == null) continue;
        portfolio.fills.add(PaperFill(
          id: row['id'] as String? ?? time.microsecondsSinceEpoch.toString(),
          symbol: row['symbol'] as String? ?? '',
          side: side,
          price: number(row['price'], 0),
          quantity: number(row['quantity'], 0),
          fee: number(row['fee'], 0),
          realizedPnl: number(row['realizedPnl'], 0),
          time: time,
        ));
      }
      return true;
    } catch (_) {
      // A corrupt snapshot must not prevent the app from opening.
      return false;
    }
  }
}
