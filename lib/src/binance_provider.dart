
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exchange_router.dart';
import 'market_provider.dart';

class BinanceProvider implements MarketProvider {
  final http.Client _client = http.Client();

  @override
  String get id => 'binance';

  @override
  String get name => 'Binance';

  @override
  MarketType get market => MarketType.crypto;

  static const String _baseUrl = 'https://api.binance.com';

  @override
  Future<bool> checkConnection() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/v3/ping'))
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<MarketQuote> fetchQuote(String symbol) async {
    final normalizedSymbol = symbol.trim().toUpperCase();

    if (normalizedSymbol.isEmpty) {
      throw const MarketProviderException(
        'نماد معاملاتی معتبر نیست.',
      );
    }

    final uri = Uri.parse(
      '$_baseUrl/api/v3/ticker/24hr',
    ).replace(
      queryParameters: {'symbol': normalizedSymbol},
    );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw MarketProviderException(
          'خطای دریافت اطلاعات بایننس: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        throw const MarketProviderException(
          'پاسخ دریافتی معتبر نیست.',
        );
      }

      final bid = double.parse(data['bidPrice'].toString());
      final ask = double.parse(data['askPrice'].toString());
      final volume = double.parse(data['volume'].toString());

      final quote = MarketQuote(
        providerId: id,
        symbol: normalizedSymbol,
        market: market,
        bid: bid,
        ask: ask,
        volume: volume,
        timestamp: DateTime.now().toUtc(),
      );

      if (!quote.isValid || ask <= 0) {
        throw const MarketProviderException(
          'اطلاعات قیمت معتبر نیست.',
        );
      }

      return quote;
    } on MarketProviderException {
      rethrow;
    } catch (e) {
      throw MarketProviderException(
        'دریافت قیمت ناموفق بود: $e',
      );
    }
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}
