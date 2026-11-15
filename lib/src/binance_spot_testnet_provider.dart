import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'exchange_credential_store.dart';
import 'exchange_router.dart';
import 'market_provider.dart';
import 'trading_execution.dart';

/// Binance Spot TESTNET only. The host is intentionally fixed to testnet;
/// this adapter cannot place orders on the production exchange.
class BinanceSpotTestnetProvider implements SpotTradingProvider {
  static const String _baseUrl = 'https://testnet.binance.vision';

  final ExchangeCredentialStore credentials;
  final http.Client _client;
  final Duration timeout;
  bool _closed = false;

  BinanceSpotTestnetProvider({
    required this.credentials,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  @override
  String get id => 'binance_spot_testnet';

  @override
  String get name => 'Binance Spot Testnet';

  @override
  MarketType get market => MarketType.crypto;

  @override
  bool get supportsSpot => true;

  Future<Map<String, String>> _authHeaders() async {
    final key = await credentials.readApiKey(id);
    if (key == null || key.isEmpty) {
      throw StateError('کلید API آزمایشی بایننس ثبت نشده است');
    }
    return {'X-MBX-APIKEY': key};
  }

  String _signature(String payload, String secret) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(payload)).toString();
  }

  Future<http.Response> _signedRequest(
    String method,
    String path,
    Map<String, String> parameters,
  ) async {
    if (_closed) throw StateError('Provider is closed');
    final secret = await credentials.readApiSecret(id);
    if (secret == null || secret.isEmpty) {
      throw StateError('کلید محرمانه API آزمایشی ثبت نشده است');
    }

    final params = <String, String>{
      ...parameters,
      'recvWindow': '5000',
      'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    final payload = Uri(queryParameters: params).query;
    final signature = _signature(payload, secret);
    final uri = Uri.parse('$_baseUrl$path?$payload&signature=$signature');
    final headers = await _authHeaders();

    http.Response response;
    try {
      if (method == 'GET') {
        response = await _client.get(uri, headers: headers).timeout(timeout);
      } else if (method == 'POST') {
        response = await _client.post(uri, headers: headers).timeout(timeout);
      } else if (method == 'DELETE') {
        response = await _client.delete(uri, headers: headers).timeout(timeout);
      } else {
        throw ArgumentError('Unsupported HTTP method');
      }
    } on Exception {
      // A POST timeout has unknown execution status. Caller must reconcile
      // by clientOrderId/order query; never automatically retry a new order.
      rethrow;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'HTTP ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['msg'] != null) {
          message = body['msg'].toString();
        }
      } catch (_) {}
      throw StateError('Binance Testnet: $message');
    }
    return response;
  }

  Future<Map<String, dynamic>> _signedJson(
    String method,
    String path,
    Map<String, String> parameters,
  ) async {
    final response = await _signedRequest(method, path, parameters);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('پاسخ نامعتبر از Binance Testnet');
    }
    return decoded;
  }

  @override
  Future<bool> checkTradingConnection() async {
    try {
      await _signedJson('GET', '/api/v3/account', const {});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ExchangeBalance>> fetchBalances() async {
    final data = await _signedJson('GET', '/api/v3/account', const {});
    final raw = data['balances'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) {
      return ExchangeBalance(
        asset: item['asset']?.toString() ?? '',
        free: double.tryParse(item['free']?.toString() ?? '') ?? 0,
        locked: double.tryParse(item['locked']?.toString() ?? '') ?? 0,
      );
    }).where((balance) => balance.asset.isNotEmpty).toList(growable: false);
  }

  Future<void> _validateSpotSymbolAndQuantity(
    SpotOrderRequest request,
  ) async {
    final symbol = request.symbol.toUpperCase();
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/v3/exchangeInfo').replace(
        queryParameters: {'symbol': symbol},
      ),
    ).timeout(timeout);
    if (response.statusCode != 200) {
      throw StateError('دریافت قوانین نماد از Binance Testnet ناموفق بود');
    }
    final data = jsonDecode(response.body);
    final symbols = data is Map ? data['symbols'] : null;
    if (symbols is! List || symbols.isEmpty || symbols.first is! Map) {
      throw StateError('نماد در Binance Spot Testnet پیدا نشد');
    }
    final info = Map<String, dynamic>.from(symbols.first as Map);
    if (info['status'] != 'TRADING' ||
        info['isSpotTradingAllowed'] == false) {
      throw StateError('معامله Spot برای این نماد فعال نیست');
    }
    final permissions = info['permissions'];
    if (permissions is List && !permissions.contains('SPOT')) {
      throw StateError('این نماد مجوز Spot ندارد');
    }
    final filters = info['filters'];
    if (filters is! List) throw StateError('قوانین حجم نماد در دسترس نیست');

    Map<String, dynamic>? lot;
    Map<String, dynamic>? notional;
    for (final filter in filters.whereType<Map>()) {
      final item = Map<String, dynamic>.from(filter);
      if (item['filterType'] == 'LOT_SIZE') lot = item;
      if (item['filterType'] == 'MIN_NOTIONAL' ||
          item['filterType'] == 'NOTIONAL') notional ??= item;
    }
    if (lot == null) throw StateError('قانون LOT_SIZE موجود نیست');
    final minQty = double.tryParse(lot['minQty']?.toString() ?? '') ?? 0;
    final maxQty = double.tryParse(lot['maxQty']?.toString() ?? '') ?? 0;
    final step = double.tryParse(lot['stepSize']?.toString() ?? '') ?? 0;
    if (request.quantity < minQty ||
        (maxQty > 0 && request.quantity > maxQty) ||
        step <= 0) {
      throw StateError('حجم سفارش با فیلتر LOT_SIZE سازگار نیست');
    }
    final steps = request.quantity / step;
    if ((steps - steps.round()).abs() > 0.0000001) {
      throw StateError('حجم سفارش باید مضرب stepSize صرافی باشد');
    }

    final priceResponse = await _client.get(
      Uri.parse('$_baseUrl/api/v3/ticker/price').replace(
        queryParameters: {'symbol': symbol},
      ),
    ).timeout(timeout);
    if (priceResponse.statusCode != 200) {
      throw StateError('قیمت مرجع نماد دریافت نشد');
    }
    final priceData = jsonDecode(priceResponse.body);
    final marketPrice = priceData is Map
        ? double.tryParse(priceData['price']?.toString() ?? '')
        : null;
    final estimatedPrice = request.type == SpotOrderType.limit
        ? request.limitPrice!
        : marketPrice;
    if (estimatedPrice == null || estimatedPrice <= 0) {
      throw StateError('قیمت مرجع معتبر نیست');
    }
    if (notional != null) {
      final minimum = double.tryParse(
            (notional['minNotional'] ?? notional['minNotionalValue'])
                ?.toString() ?? '',
          ) ?? 0;
      if (request.quantity * estimatedPrice < minimum) {
        throw StateError('ارزش سفارش کمتر از حداقل مجاز صرافی است');
      }
    }
  }

  SpotOrderResult _parseOrder(Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? 'UNKNOWN';
    final state = switch (status) {
      'NEW' => OrderState.open,
      'PARTIALLY_FILLED' => OrderState.partiallyFilled,
      'FILLED' => OrderState.filled,
      'CANCELED' || 'EXPIRED' => OrderState.canceled,
      'REJECTED' => OrderState.rejected,
      _ => OrderState.unknown,
    };
    return SpotOrderResult(
      exchangeId: id,
      orderId: data['orderId']?.toString() ?? '',
      clientOrderId: data['clientOrderId']?.toString() ?? '',
      state: state,
      executedQuantity:
          double.tryParse(data['executedQty']?.toString() ?? '') ?? 0,
      cumulativeQuote:
          double.tryParse(data['cummulativeQuoteQty']?.toString() ?? '') ?? 0,
      fee: 0,
      feeAsset: '',
      updatedAt: DateTime.now(),
      message: state == OrderState.unknown ? status : null,
    );
  }

  @override
  Future<SpotOrderResult> submitSpotOrder(SpotOrderRequest request) async {
    if (!request.isValid) throw ArgumentError('درخواست سفارش نامعتبر است');
    await _validateSpotSymbolAndQuantity(request);
    final params = <String, String>{
      'symbol': request.symbol.toUpperCase(),
      'side': request.side == SpotOrderSide.buy ? 'BUY' : 'SELL',
      'type': request.type == SpotOrderType.market ? 'MARKET' : 'LIMIT',
      'quantity': request.quantity.toString(),
      'newClientOrderId': request.clientOrderId,
      'newOrderRespType': 'FULL',
      if (request.type == SpotOrderType.limit) ...{
        'timeInForce': 'GTC',
        'price': request.limitPrice!.toString(),
      },
    };
    final data = await _signedJson('POST', '/api/v3/order', params);
    return _parseOrder(data);
  }

  @override
  Future<SpotOrderResult> fetchOrder({
    required String symbol,
    required String orderId,
  }) async {
    final data = await _signedJson('GET', '/api/v3/order', {
      'symbol': symbol.toUpperCase(),
      'orderId': orderId,
    });
    return _parseOrder(data);
  }

  @override
  Future<void> cancelOrder({
    required String symbol,
    required String orderId,
  }) async {
    await _signedJson('DELETE', '/api/v3/order', {
      'symbol': symbol.toUpperCase(),
      'orderId': orderId,
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
