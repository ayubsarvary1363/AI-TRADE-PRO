import 'dart:io' show HttpDate;
import 'package:http/http.dart' as http;

class MarketNewsItem {
  final String title;
  final String link;
  final String source;
  final DateTime? publishedAt;
  final int sentiment; // -1 negative, 0 neutral, 1 positive
  final String market;
  final String impact;
  final int importance; // 1..5, heuristic estimate
  final bool highRisk;

  const MarketNewsItem({
    required this.title,
    required this.link,
    required this.source,
    required this.publishedAt,
    required this.sentiment,
    required this.market,
    required this.impact,
    required this.importance,
    required this.highRisk,
  });
}

class MarketNewsService {
  // Separate searches improve coverage; Google News RSS is an aggregator,
  // not a guarantee that every publisher or market is represented.
  static const _topics = <String>[
    'Bitcoin cryptocurrency Ethereum regulation ETF exchange hack',
    'crypto market Bitcoin institutional adoption flows',
    'forex currency markets central banks exchange rates',
    'Federal Reserve FOMC interest rate decision US dollar',
    'ECB BOE BOJ interest rates monetary policy',
    'US CPI inflation jobs payroll GDP economic calendar',
    'geopolitics oil gold global financial markets',
  ];

  Future<List<MarketNewsItem>> fetchLatest({int perTopic = 10}) async {
    final all = <MarketNewsItem>[];
    final client = http.Client();
    try {
      final responses = await Future.wait(_topics.map((topic) async {
        final uri = Uri.https('news.google.com', '/rss/search', {
          'q': topic,
          'hl': 'en-US',
          'gl': 'US',
          'ceid': 'US:en',
        });
        final response = await client.get(uri, headers: {
          'User-Agent': 'AI-Trade-Pro/0.8 (market-news-reader)',
        }).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) return <MarketNewsItem>[];
        final parsed = <MarketNewsItem>[];
        for (final match in RegExp(r'<item>([\\s\\S]*?)</item>')
            .allMatches(response.body).take(perTopic)) {
          final xml = match.group(1) ?? '';
          final title = _tag(xml, 'title');
          final link = _tag(xml, 'link');
          if (title.isEmpty || link.isEmpty) continue;
          final source = _tag(xml, 'source');
          final dateText = _tag(xml, 'pubDate');
          final analysis = _analyse(title);
          parsed.add(MarketNewsItem(
            title: title,
            link: link,
            source: source.isEmpty ? 'Google News' : source,
            publishedAt: _tryDate(dateText),
            sentiment: analysis.sentiment,
            market: analysis.market,
            impact: analysis.impact,
            importance: analysis.importance,
            highRisk: analysis.highRisk,
          ));
        }
        return parsed;
      }));
      for (final batch in responses) {
        all.addAll(batch);
      }
    } finally {
      client.close();
    }

    final unique = <String, MarketNewsItem>{};
    for (final item in all) {
      final key = item.link.isNotEmpty
          ? item.link
          : item.title.toLowerCase().trim();
      unique.putIfAbsent(key, () => item);
    }
    final result = unique.values.where(_isRecent).toList()
      ..sort((a, b) => (b.publishedAt ?? DateTime(1970))
          .compareTo(a.publishedAt ?? DateTime(1970)));
    return result;
  }

  bool _isRecent(MarketNewsItem item) {
    final date = item.publishedAt;
    if (date == null) return true;
    return DateTime.now().difference(date).inDays <= 7;
  }

  String _tag(String xml, String name) {
    final match = RegExp('<$name(?:\\\\s[^>]*)?>([\\\\s\\\\S]*?)</$name>')
        .firstMatch(xml);
    if (match == null) return '';
    var value = (match.group(1) ?? '').trim();
    value = value.replaceAll(RegExp(r'^<!\\[CDATA\\['), '')
        .replaceAll(RegExp(r'\\]\\]>$'), '');
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  DateTime? _tryDate(String value) {
    if (value.isEmpty) return null;
    try {
      return HttpDate.parse(value);
    } catch (_) {
      return DateTime.tryParse(value);
    }
  }

  _NewsAnalysis _analyse(String title) {
    final text = title.toLowerCase();
    const positive = [
      'surge', 'rally', 'gain', 'rise', 'bullish', 'approval',
      'adoption', 'record high', 'breakout', 'inflow', 'recovery',
      'rate cut', 'cuts rates', 'eases policy',
    ];
    const negative = [
      'crash', 'plunge', 'drop', 'fall', 'bearish', 'hack',
      'lawsuit', 'ban', 'outflow', 'sell-off', 'liquidation',
      'recession', 'inflation shock', 'rate hike', 'raises rates',
      'war', 'sanction', 'default',
    ];
    const highRiskTerms = [
      'fed', 'fomc', 'interest rate', 'rate decision', 'cpi',
      'inflation', 'payroll', 'jobs report', 'central bank',
      'hack', 'ban', 'lawsuit', 'war', 'sanction', 'emergency',
    ];
    const cryptoTerms = [
      'bitcoin', 'btc', 'ethereum', 'crypto', 'cryptocurrency',
      'stablecoin', 'blockchain', 'token', 'exchange', 'etf',
    ];
    const forexTerms = [
      'forex', 'currency', 'dollar', 'usd', 'euro', 'eur',
      'yen', 'jpy', 'pound', 'gbp', 'fed', 'federal reserve',
      'ecb', 'boe', 'boj', 'interest rate', 'central bank',
      'cpi', 'payroll', 'gdp',
    ];
    final up = positive.where(text.contains).length;
    final down = negative.where(text.contains).length;
    final sentiment = up > down ? 1 : (down > up ? -1 : 0);
    final cryptoHits = cryptoTerms.where(text.contains).length;
    final forexHits = forexTerms.where(text.contains).length;
    final market = cryptoHits > 0 && forexHits > 0
        ? 'رمزارز و فارکس'
        : cryptoHits > 0
            ? 'رمزارز'
            : forexHits > 0
                ? 'فارکس'
                : 'بازارهای جهانی';
    final highRisk = highRiskTerms.any(text.contains);
    final importance = highRisk
        ? 5
        : (cryptoHits + forexHits >= 2 ? 4 : (sentiment != 0 ? 3 : 2));
    final impact = sentiment > 0
        ? 'احتمال اثر مثبت'
        : sentiment < 0
            ? 'احتمال اثر منفی'
            : 'اثر نامشخص یا خنثی';
    return _NewsAnalysis(
      sentiment: sentiment,
      market: market,
      impact: impact,
      importance: importance,
      highRisk: highRisk,
    );
  }
}

class _NewsAnalysis {
  final int sentiment;
  final String market;
  final String impact;
  final int importance;
  final bool highRisk;

  const _NewsAnalysis({
    required this.sentiment,
    required this.market,
    required this.impact,
    required this.importance,
    required this.highRisk,
  });
}
