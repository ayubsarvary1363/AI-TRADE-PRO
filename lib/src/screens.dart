
import 'dart:async';

import 'package:flutter/material.dart';

import 'engine.dart';
import 'exchange_router.dart';
import 'market_provider.dart';
import 'market_hub.dart';
import 'provider_setup.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _symbol = 'BTCUSDT';

  // تایم‌فریم
  String _resolution = '60';

  int _tab = 0;
  bool _botEnabled = false;
  bool _isBusy = false;

  final MarketDataService _market = MarketDataService();

  final MarketProviderRegistry _providerRegistry =
      ProviderSetup.createRegistry();

  late final MarketHub _marketHub = MarketHub(
    registry: _providerRegistry,
  );

  final SignalEngine _signalEngine = SignalEngine();
  final RiskManager _riskManager = const RiskManager();

  final PaperPortfolio _portfolio =
      PaperPortfolio(initialUsdt: 50.0);

  Timer? _timer;

  double? _lastPrice;
  MarketQuote? _lastQuote;

  bool _providerConnected = false;

  SignalResult? _lastSignal;

  String _message = 'برای شروع، دریافت اطلاعات بازار را بزنید.';
  String? _error;

  String _marketSourceMessage = 'منبع داده: Binance';

  DateTime? _lastCandleTime;
  DateTime _currentDay = DateTime.now();

  double _dayStartEquity = 50.0;

  bool _riskLimitTriggered = false;

  // ==================== TIMEFRAME ====================

  Duration get _selectedTimeframeDuration {
    switch (_resolution) {
      case '1':
        return const Duration(minutes: 1);
      case '5':
        return const Duration(minutes: 5);
      case '15':
        return const Duration(minutes: 15);
      case '30':
        return const Duration(minutes: 30);
      case '60':
        return const Duration(hours: 1);
      case '240':
        return const Duration(hours: 4);
      case 'D':
        return const Duration(days: 1);
      default:
        return const Duration(hours: 1);
    }
  }

  String get _timeframeLabel {
    switch (_resolution) {
      case '1':
        return '۱ دقیقه';
      case '5':
        return '۵ دقیقه';
      case '15':
        return '۱۵ دقیقه';
      case '30':
        return '۳۰ دقیقه';
      case '60':
        return '۱ ساعت';
      case '240':
        return '۴ ساعت';
      case 'D':
        return 'روزانه';
      default:
        return '۱ ساعت';
    }
  }

  void _changeTimeframe(String? value) {
    if (value == null || value == _resolution) return;

    setState(() {
      _resolution = value;
      _lastCandleTime = null;
      _lastSignal = null;
      _message = 'تایم‌فریم تغییر کرد؛ اطلاعات جدید دریافت می‌شود.';
    });

    _refreshMarket();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _market.dispose();
    _marketHub.dispose();
    super.dispose();
  }

  // ==================== BOT CONTROL ====================

  void _startBot() {
    if (_botEnabled || _riskLimitTriggered) return;

    setState(() {
      _botEnabled = true;
      _message = 'ربات آزمایشی فعال شد.';
      _error = null;
    });

    _timer?.cancel();

    _refreshMarket();

    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshMarket(),
    );
  }

  void _stopBot({String? reason}) {
    _timer?.cancel();
    _timer = null;

    if (!mounted) return;

    setState(() {
      _botEnabled = false;

      if (reason != null) {
        _message = reason;
      } else {
        _message = 'ربات متوقف شد.';
      }
    });
  }

  // ==================== MARKET DATA ====================

  Future<void> _refreshMarket() async {
    if (_isBusy || !mounted) return;

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      bool connected = false;
      MarketQuote? latestQuote;

      // بررسی اتصال ارائه‌دهنده قیمت
      try {
        final connectionResults =
    await _marketHub.checkConnections(
  market: MarketType.crypto,
);

        connected = connectionResults.any(
          (status) => status.connected,
        );

        final quotes = await _marketHub.collectQuotes(
  market: MarketType.crypto,
  symbol: _symbol,
);

          if (quotes.isNotEmpty) {
            latestQuote = quotes.first;
          }
        }
      } catch (_) {
        connected = false;
        latestQuote = null;
      }

      if (!mounted) return;

      // دریافت کندل‌ها
      final candles = await _market.fetchCandles(
        symbol: _symbol,
        resolution: _resolution,
        countback: 100,
        provider: 'binance',
      );

      if (!mounted) return;

      final now = DateTime.now().toUtc();

      // حذف کندل باز
      final closedCandles = candles.where((candle) {
        final closeTime = candle.time
            .toUtc()
            .add(_selectedTimeframeDuration);

        return !closeTime.isAfter(now);
      }).toList();

      if (closedCandles.length < 30) {
        throw Exception(
          'تعداد کندل‌های بسته‌شده برای تحلیل کافی نیست.',
        );
      }

      final latest = closedCandles.last;
      final price = latest.close;

      if (!price.isFinite || price <= 0) {
        throw Exception('قیمت دریافتی معتبر نیست.');
      }

      final signal = _signalEngine.analyze(closedCandles);

      setState(() {
        _lastPrice = price;
        _lastSignal = signal;
        _providerConnected = connected;
        _lastQuote = latestQuote;

        _marketSourceMessage = connected
            ? 'اتصال قیمت Binance برقرار است.'
            : 'کندل‌ها دریافت شدند؛ اتصال قیمت لحظه‌ای تأیید نشد.';
      });

      // پردازش هر کندل فقط یک بار
      if (_botEnabled &&
          (_lastCandleTime == null ||
              latest.time.isAfter(_lastCandleTime!))) {
        _lastCandleTime = latest.time;

        _executeSignal(signal, price);
      }

      if (mounted && !_botEnabled) {
        setState(() {
          if (_error == null) {
            _message = 'اطلاعات بازار با موفقیت دریافت شد.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _message = 'دریافت اطلاعات بازار ناموفق بود.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  // ==================== PAPER TRADING ====================

  void _executeSignal(
    SignalResult signal,
    double price,
  ) {
    final prices = <String, double>{
      _symbol: price,
    };

    final equity = _portfolio.equity(prices);

    if (!equity.isFinite || equity <= 0) {
      _stopBot(
        reason: 'ارزش سبد معتبر نیست؛ ربات برای محافظت متوقف شد.',
      );
      return;
    }

    // تشخیص تغییر روز
    final today = DateTime.now();

    if (today.year != _currentDay.year ||
        today.month != _currentDay.month ||
        today.day != _currentDay.day) {
      _currentDay = today;
      _dayStartEquity = equity;
    }

    // محدودیت زیان روزانه
    if (_riskManager.dailyLossLimitReached(
      startingEquity: _dayStartEquity,
      currentEquity: equity,
    )) {
      _riskLimitTriggered = true;

      _stopBot(
        reason: 'حد زیان روزانه ۱٪ فعال شد؛ ربات متوقف شد.',
      );

      return;
    }

    // محدودیت افت سرمایه از بالاترین ارزش ثبت‌شده
    if (_portfolio.maximumDrawdown >=
            _riskManager.maxDrawdown ||
        _riskManager.drawdownLimitReached(
          initialEquity: _portfolio.initialUsdt,
          currentEquity: equity,
        )) {
      _riskLimitTriggered = true;

      _stopBot(
        reason: 'حد افت سرمایه ۵٪ فعال شد؛ ربات متوقف شد.',
      );

      return;
    }

    final position = _portfolio.positions[_symbol];

    // ==================== BUY ====================

    if (signal.direction == SignalDirection.buy &&
        position == null) {
      final stopPrice = price * 0.98;

      final notional = _riskManager.positionNotional(
        equity: equity,
        entry: price,
        stop: stopPrice,
      );

      final quantity = (notional * 0.998) / price;

      if (!quantity.isFinite || quantity <= 0) {
        _message = 'حجم معامله معتبر نیست.';
        return;
      }

      final success = _portfolio.buy(
        symbol: _symbol,
        price: price,
        quantity: quantity,
      );

      _message = success
          ? 'خرید آزمایشی BTC ثبت شد.'
          : 'موجودی برای خرید کافی نیست.';

      return;
    }

    // ==================== SELL ====================

    if (signal.direction == SignalDirection.sell &&
        position != null) {
      final success = _portfolio.sell(
        symbol: _symbol,
        price: price,
        quantity: position.quantity,
      );

      _message = success
          ? 'فروش آزمایشی BTC ثبت شد.'
          : 'ثبت فروش آزمایشی ناموفق بود.';

      return;
    }

    _message = signal.direction == SignalDirection.hold
        ? 'سیگنال مشخصی وجود ندارد؛ منتظر می‌مانیم.'
        : 'شرایط جدید برای معامله وجود ندارد.';
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      _markets(),
      _signals(),
      _settings(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(
              Icons.auto_graph,
              color: Color(0xFF37D996),
            ),
            SizedBox(width: 9),
            Text(
              'AI Trade Pro',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Chip(
              avatar: Icon(Icons.science, size: 16),
              label: Text('Paper'),
              side: BorderSide.none,
              backgroundColor: Color(0xFF173B34),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: pages[_tab],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          setState(() => _tab = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'داشبورد',
          ),
          NavigationDestination(
            icon: Icon(Icons.candlestick_chart),
            label: 'بازارها',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_alt_outlined),
            label: 'تحلیل هوشمند',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune),
            label: 'تنظیمات',
          ),
        ],
      ),
    );
  }

  // ==================== DASHBOARD ====================

  Widget _dashboard() {
    final prices = <String, double>{};

    if (_lastPrice != null) {
      prices[_symbol] = _lastPrice!;
    }

    final equity = _portfolio.equity(prices);

    final pnl = equity.isFinite
        ? equity - _portfolio.initialUsdt
        : 0.0;

    final unrealized = _portfolio.unrealizedPnl(prices);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusCard(),

        const SizedBox(height: 14),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'موجودی نقدی آزمایشی',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$${_portfolio.cash.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ارزش کل سبد: ${equity.isFinite ? equity.toStringAsFixed(2) : 'نامشخص'} USDT',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 5),
                const Text(
                  '۵۰ USDT سرمایه اولیه مجازی',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: _metric(
                'تعداد معاملات',
                '${_portfolio.fills.length}',
                Icons.receipt_long,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metric(
                'سود و زیان کل',
                '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                Icons.show_chart,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        _metric(
          'سود و زیان تحقق‌نیافته',
          unrealized.isFinite
              ? unrealized.toStringAsFixed(2)
              : '—',
          Icons.account_balance_wallet,
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _metric(
                'بالاترین ارزش سبد',
                _portfolio.peakEquity.toStringAsFixed(2),
                Icons.trending_up,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metric(
                'حداکثر افت سرمایه',
                '${(_portfolio.maximumDrawdown * 100).toStringAsFixed(2)}٪',
                Icons.warning_amber,
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // انتخاب تایم‌فریم
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تایم‌فریم تحلیل',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _resolution,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'انتخاب بازه زمانی',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '1',
                      child: Text('۱ دقیقه'),
                    ),
                    DropdownMenuItem(
                      value: '5',
                      child: Text('۵ دقیقه'),
                    ),
                    DropdownMenuItem(
                      value: '15',
                      child: Text('۱۵ دقیقه'),
                    ),
                    DropdownMenuItem(
                      value: '30',
                      child: Text('۳۰ دقیقه'),
                    ),
                    DropdownMenuItem(
                      value: '60',
                      child: Text('۱ ساعت'),
                    ),
                    DropdownMenuItem(
                      value: '240',
                      child: Text('۴ ساعت'),
                    ),
                    DropdownMenuItem(
                      value: 'D',
                      child: Text('روزانه'),
                    ),
                  ],
                  onChanged: _isBusy ? null : _changeTimeframe,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // وضعیت بازار
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'وضعیت بازار BTC/USDT',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  _lastPrice == null
                      ? 'قیمت هنوز دریافت نشده است.'
                      : '\$${_lastPrice!.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('تایم‌فریم: $_timeframeLabel'),
                const SizedBox(height: 8),
                Text(
                  _marketSourceMessage,
                  style: TextStyle(
                    color: _providerConnected
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
                if (_lastQuote != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'قیمت خرید: ${_lastQuote!.ask}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'قیمت فروش: ${_lastQuote!.bid}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _isBusy
                      ? 'در حال دریافت اطلاعات...'
                      : _error ?? 'وضعیت دریافت اطلاعات آماده است.',
                  style: TextStyle(
                    color: _error == null
                        ? Colors.white60
                        : Colors.orangeAccent,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : _refreshMarket,
                    icon: const Icon(Icons.refresh),
                    label: const Text('دریافت اطلاعات بازار'),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // وضعیت ربات
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'وضعیت ربات',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(_message),
                if (_lastCandleTime != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'آخرین کندل پردازش‌شده: ${_formatTime(_lastCandleTime!)}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // تاریخچه معاملات
        _tradeHistory(),

        const SizedBox(height: 14),

        const Text(
          'میانبرها',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),

        const SizedBox(height: 8),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('تحلیل هوشمند'),
              onPressed: () => setState(() => _tab = 2),
            ),
            ActionChip(
              label: const Text('بازارها'),
              onPressed: () => setState(() => _tab = 1),
            ),
            ActionChip(
              label: const Text('تنظیمات ریسک'),
              onPressed: () => setState(() => _tab = 3),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== TRADE HISTORY ====================

  Widget _tradeHistory() {
    final fills = _portfolio.fills.reversed.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تاریخچه معاملات آزمایشی',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            if (fills.isEmpty)
              const Text(
                'هنوز معامله‌ای ثبت نشده است.',
                style: TextStyle(color: Colors.white60),
              )
            else
              ...fills.take(10).map((fill) {
                final isBuy = fill.side == 'BUY';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isBuy
                        ? const Color(0xFF174B38)
                        : const Color(0xFF512B32),
                    child: Icon(
                      isBuy ? Icons.south_west : Icons.north_east,
                      color: isBuy
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                  ),
                  title: Text(
                    '${isBuy ? 'خرید' : 'فروش'} ${fill.symbol}',
                  ),
                  subtitle: Text(
                    'قیمت: ${fill.price.toStringAsFixed(2)} | مقدار: ${fill.quantity.toStringAsFixed(6)}\n'
                    'کارمزد: ${fill.fee.toStringAsFixed(4)} USDT\n'
                    '${_formatTime(fill.time)}',
                  ),
                  trailing: Text(
                    isBuy
                        ? 'خرید'
                        : '${fill.realizedPnl >= 0 ? '+' : ''}${fill.realizedPnl.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: isBuy
                          ? Colors.greenAccent
                          : fill.realizedPnl >= 0
                              ? Colors.greenAccent
                              : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ==================== STATUS ====================

  Widget _statusCard() {
    return Card(
      color: _botEnabled
          ? const Color(0xFF123C32)
          : const Color(0xFF202B3B),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _botEnabled
                  ? Icons.play_circle
                  : Icons.pause_circle,
              size: 34,
              color: _botEnabled
                  ? Colors.greenAccent
                  : Colors.orangeAccent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _botEnabled
                        ? 'ربات آزمایشی فعال است'
                        : 'ربات متوقف است',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _riskLimitTriggered
                        ? 'محدودیت ریسک فعال شده است.'
                        : 'فقط معاملات مجازی؛ بدون سفارش واقعی',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _botEnabled,
              onChanged: _riskLimitTriggered
                  ? null
                  : (value) {
                      if (value) {
                        _startBot();
                      } else {
                        _stopBot();
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ==================== MARKETS ====================

  Widget _markets() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'بازارها و منابع اطلاعات',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'در این نسخه، دریافت کندل و قیمت عمومی فقط برای بازار رمزارز Binance پیاده‌سازی شده است. سایر بازارها هنوز به ارائه‌دهنده واقعی متصل نشده‌اند.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 14),
        _marketTile(
          'Binance',
          'BTC/USDT · داده عمومی بازار رمزارز',
          Icons.currency_bitcoin,
          _providerConnected ? 'متصل' : 'بررسی اتصال',
        ),
        _marketTile(
          'بازار فارکس',
          'نیازمند اتصال به کارگزار و منبع قیمت',
          Icons.currency_exchange,
          'در انتظار اتصال',
        ),
        _marketTile(
          'سهام و شاخص‌ها',
          'نیازمند ارائه‌دهنده اطلاعات و کارگزار',
          Icons.show_chart,
          'در انتظار اتصال',
        ),
        _marketTile(
          'کالاها',
          'نیازمند ارائه‌دهنده اطلاعات بازار',
          Icons.factory_outlined,
          'در انتظار اتصال',
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _lastPrice == null
                  ? 'قیمت BTC/USDT هنوز دریافت نشده است.'
                  : 'آخرین قیمت کندل BTC/USDT: ${_lastPrice!.toStringAsFixed(2)} USDT',
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isBusy ? null : _refreshMarket,
          icon: const Icon(Icons.sync),
          label: const Text('بررسی دوباره اتصال و قیمت'),
        ),
      ],
    );
  }

  // ==================== SIGNALS ====================

  Widget _signals() {
    final signal = _lastSignal;

    String direction = 'در انتظار داده';

    if (signal != null) {
      switch (signal.direction) {
        case SignalDirection.buy:
          direction = 'خرید';
          break;
        case SignalDirection.sell:
          direction = 'فروش';
          break;
        case SignalDirection.hold:
          direction = 'انتظار';
          break;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'موتور تحلیل هوشمند',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _feature(
          'تحلیل روند',
          'EMA 9 و EMA 21',
          Icons.trending_up,
        ),
        _feature(
          'مومنتوم',
          'RSI با دوره ۱۴',
          Icons.speed,
        ),
        _feature(
          'همگرایی و واگرایی',
          'MACD استاندارد',
          Icons.multiline_chart,
        ),
        _feature(
          'مدیریت ریسک',
          'ریسک ۰٫۵٪ برای هر معامله',
          Icons.shield_outlined,
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'آخرین نتیجه تحلیل',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  direction,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (signal != null) ...[
                  const SizedBox(height: 8),
                  Text('قدرت سیگنال: ${signal.confidence}٪'),
                  const SizedBox(height: 10),
                  ...signal.reasons.map(
                    (reason) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $reason'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'این موتور فعلاً تحلیل قانون‌محور EMA، RSI و MACD است؛ مدل یادگیری ماشین آموزش‌دیده نیست. نتیجه تحلیل تضمین‌کننده سود نیست.',
            ),
          ),
        ),
      ],
    );
  }

  // ==================== SETTINGS ====================

  Widget _settings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'تنظیمات',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _feature(
          'سرمایه آزمایشی',
          '۵۰ USDT',
          Icons.account_balance_wallet,
        ),
        _feature(
          'ریسک هر معامله',
          '۰٫۵٪ از ارزش سبد',
          Icons.shield_outlined,
        ),
        _feature(
          'حداکثر زیان روزانه',
          '۱٪ از سرمایه ابتدای روز',
          Icons.warning_amber,
        ),
        _feature(
          'حد افت سرمایه',
          '۵٪ از بالاترین ارزش ثبت‌شده سبد یا سرمایه اولیه',
          Icons.security,
        ),
        _feature(
          'اهرم',
          'غیرفعال؛ معاملات بدون اهرم',
          Icons.block,
        ),
        _feature(
          'حالت معامله',
          'فقط آزمایشی (Paper Trading)',
          Icons.science,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _riskLimitTriggered
                  ? 'محدودیت ریسک فعال شده است. برای جلوگیری از ادامه زیان، شروع مجدد ربات در این نشست غیرفعال است.'
                  : 'ربات در حالت آزمایشی کار می‌کند. اطلاعات سبد پس از بستن برنامه هنوز ذخیره نمی‌شود. اجرای دوره‌ای نیز فقط تا زمانی انجام می‌شود که برنامه در پیش‌زمینه فعال باشد.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'حد ضرر ۲٪ فعلاً برای محاسبه اندازه موقعیت استفاده می‌شود و هنوز به‌صورت سفارش مستقل یا کنترل لحظه‌ای اجرا نمی‌شود.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'اتصال به صرافی‌های دیگر، کارگزاران فارکس و بازارهای سهام و کالا در مراحل بعدی توسعه انجام می‌شود. انتخاب خودکار ارائه‌دهنده تا زمان اتصال و ارزیابی واقعی آن‌ها فعال نیست.',
            ),
          ),
        ),
      ],
    );
  }

  // ==================== COMPONENTS ====================

  Widget _metric(
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: const Color(0xFF37D996),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marketTile(
    String title,
    String subtitle,
    IconData icon,
    String status,
  ) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1B3542),
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Text(
          status,
          style: const TextStyle(
            color: Colors.orangeAccent,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _feature(
    String title,
    String subtitle,
    IconData icon,
  ) {
    return Card(
      child: ListTile(
        leading: Icon(
          icon,
          color: const Color(0xFF37D996),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();

    final year = local.year.toString();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$year/$month/$day - $hour:$minute';
  }
}
