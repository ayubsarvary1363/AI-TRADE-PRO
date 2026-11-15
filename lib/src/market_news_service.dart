import 'dart:io' show HttpDate;
import 'package:http/http.dart' as http;

class MarketNewsItem {
  final String title;
  final String link;
  final String source;
  final DateTime? publishedAt;
  final int sentiment; // -1 negative, 0 neutral, 1 positive

  const MarketNewsItem({
    required this.title,
    required this.link,
    required this.source,
    required this.publishedAt,
    required this.sentiment,
  });
}

class MarketNewsService {
  static const _topics = <String>[
    'cryptocurrency market bitcoin ethereum',
    'forex currency market central banks',
    'global financial markets stocks commodities',
  ];

  Future<List<MarketNewsItem>> fetchLatest({int perTopic = 8}) async {
    final all = <MarketNewsItem>[];
    for (final topic in _topics) {
      final uri = Uri.https('news.google.com', '/rss/search', {
        'q': topic,
        'hl': 'en-US',
        'gl': 'US',
        'ceid': 'US:en',
      });
      final response = await http.get(uri, headers: {
        'User-Agent': 'AI-Trade-Pro/0.7 (market-news-reader)',
      }).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('دریافت اخبار ناموفق بود: HTTP ${response.statusCode}');
      }
      final items = RegExp(r'<item>([\s\S]*?)</item>')
          .allMatches(response.body)
          .take(perTopic);
      for (final match in items) {
        final xml = match.group(1) ?? '';
        final title = _tag(xml, 'title');
        final link = _tag(xml, 'link');
        final source = _tag(xml, 'source');
        final dateText = _tag(xml, 'pubDate');
        if (title.isEmpty || link.isEmpty) continue;
        all.add(MarketNewsItem(
          title: title,
          link: link,
          source: source.isEmpty ? 'Google News' : source,
          publishedAt: DateTime.tryParse(dateText) ??
              _tryHttpDate(dateText),
          sentiment: _sentiment(title),
        ));
      }
    }
    final unique = <String, MarketNewsItem>{};
    for (final item in all) {
      unique[item.link] = item;
    }
    final result = unique.values.toList()
      ..sort((a, b) => (b.publishedAt ?? DateTime(1970))
          .compareTo(a.publishedAt ?? DateTime(1970)));
    return result;
  }

  String _tag(String xml, String name) {
    final match = RegExp('<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name>')
        .firstMatch(xml);
    if (match == null) return '';
    var value = (match.group(1) ?? '').trim();
    value = value.replaceAll(RegExp(r'^<!\[CDATA\['), '')
        .replaceAll(RegExp(r'\]\]>, '');
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  DateTime? _tryHttpDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      try {
        return HttpDate.parse(value);
      } catch (_) {
        return null;
      }
    }
  }

  int _sentiment(String title) {
    final value = title.toLowerCase();
    const positive = [
      'surge', 'rally', 'gain', 'rise', 'bullish', 'approval',
      'adoption', 'record high', 'breakout', 'inflow', 'recovery',
    ];
    const negative = [
      'crash', 'plunge', 'drop', 'fall', 'bearish', 'hack',
      'lawsuit', 'ban', 'outflow', 'sell-off', 'liquidation',
      'recession', 'inflation shock',
    ];
    final up = positive.where(value.contains).length;
    final down = negative.where(value.contains).length;
    if (up > down) return 1;
    if (down > up) return -1;
    return 0;
  }
}
), '');
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  DateTime? _tryHttpDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      try {
        return HttpDate.parse(value);
      } catch (_) {
        return null;
      }
    }
  }

  int _sentiment(String title) {
    final value = title.toLowerCase();
    const positive = [
      'surge', 'rally', 'gain', 'rise', 'bullish', 'approval',
      'adoption', 'record high', 'breakout', 'inflow', 'recovery',
    ];
    const negative = [
      'crash', 'plunge', 'drop', 'fall', 'bearish', 'hack',
      'lawsuit', 'ban', 'outflow', 'sell-off', 'liquidation',
      'recession', 'inflation shock',
    ];
    final up = positive.where(value.contains).length;
    final down = negative.where(value.contains).length;
    if (up > down) return 1;
    if (down > up) return -1;
    return 0;
  }
}
