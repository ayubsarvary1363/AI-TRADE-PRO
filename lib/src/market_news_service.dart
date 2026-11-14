import 'dart:convert';
import 'package:http/http.dart' as http;
import 'exchange_router.dart';

/// Lightweight headline context. Keyword sentiment is a weak signal, not
/// a substitute for verified economic-calendar data or human review.
class MarketNewsService {
  final http.Client _client;
  MarketNewsService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<String>> fetchHeadlines({
    required MarketType market,
    required String symbol,
  }) async {
    final query = market == MarketType.forex
        ? '${symbol.toUpperCase()} forex central bank inflation rates'
        : '${symbol.toUpperCase()} cryptocurrency market';
    final uri = Uri.https('news.google.com', '/rss/search', {
      'q': '$query when:1d',
      'hl': 'en-US',
      'gl': 'US',
      'ceid': 'US:en',
    });
    final response = await _client.get(uri, headers: {
      'User-Agent': 'RISE-S-TRADE/1.0',
    }).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('News feed HTTP ${response.statusCode}');
    }
    final body = response.body;
    final matches = RegExp(r'<item>([\\s\\S]*?)</item>', caseSensitive: false)
        .allMatches(body);
    final headlines = <String>[];
    for (final match in matches.take(12)) {
      final item = match.group(1) ?? '';
      final titleMatch = RegExp(r'<title><!\\[CDATA\\[(.*?)\\]\\]></title>|<title>(.*?)</title>',
          caseSensitive: false, dotAll: true).firstMatch(item);
      final raw = titleMatch?.group(1) ?? titleMatch?.group(2);
      if (raw == null) continue;
      final title = _decode(raw.replaceAll(RegExp(r'<[^>]+>'), '')).trim();
      if (title.isNotEmpty && !headlines.contains(title)) headlines.add(title);
    }
    return headlines;
  }

  String _decode(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#x27;', "'");

  void dispose() => _client.close();
}
