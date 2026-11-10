
import 'package:flutter/material.dart';
import 'dart:math';
import 'engine.dart';
import 'exchange_router.dart';
import 'market_hub.dart';
import 'provider_setup.dart';
import 'trading_controller.dart';

// =====================================================
// AI TRADE PRO
// Connected Trading Dashboard - Version 0.8.0
// =====================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TradingController _controller;

  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();

    final registry = ProviderSetup.createRegistry();

    final hub = MarketHub(registry: registry);

    _controller = TradingController(marketHub: hub);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'AI Trade Pro',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Chip(
                    avatar: const Icon(Icons.science, size: 17),
                    label: const Text('DEMO'),
                  ),
                ),
              ),
            ],
          ),
          body: IndexedStack(
            index: _selectedTab,
            children: [
              _dashboard(),
              _markets(),
              _trades(),
              _settings(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedTab,
            onDestinationSelected: (index) {
              setState(() => _selectedTab = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'داشبورد',
              ),
              NavigationDestination(
                icon: Icon(Icons.public),
                label: 'بازارها',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart),
                label: 'معاملات',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: 'تنظیمات',
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------- DASHBOARD --------------------

  Widget _dashboard() {
    final price = _controller.currentPrice;
    final equity = _controller.equity;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusCard(),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: _metricCard(
                'موجودی نقدی',
                '${_controller.portfolio.cashUsdt.toStringAsFixed(2)} USDT',
                Icons.account_balance_wallet,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                'ارزش کل حساب',
                '${equity.toStringAsFixed(2)} USDT',
                Icons.account_balance,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _metricCard(
                'سود و زیان کل',
                '${_controller.totalPnl.toStringAsFixed(3)} USDT',
                Icons.trending_up,
                valueColor: _controller.totalPnl >= 0
                    ? Colors.greenAccent
                    : Colors.redAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                'تعداد معاملات',
                '${_controller.tradeCount}',
                Icons.receipt_long,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        _sectionTitle('قیمت بازار'),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _controller.symbol,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      price > 0
                          ? price.toStringAsFixed(4)
                          : 'در انتظار دریافت قیمت',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _controller.refreshMarket,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'به‌روزرسانی',
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        _sectionTitle('نمودار و معاملات اجراشده'),

        _chartCard(),

        const SizedBox(height: 16),

        _sectionTitle('آخرین وضعیت تحلیل'),

        _signalCard(),

        const SizedBox(height: 16),

        _sectionTitle('آخرین معاملات'),

        _tradeHistory(limit: 5),
      ],
    );
  }

  Widget _statusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _controller.isRunning
                      ? Icons.play_circle
                      : Icons.pause_circle,
                  color: _controller.isRunning
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _controller.isRunning
                        ? 'ربات آزمایشی فعال است'
                        : 'ربات متوقف است',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Switch(
                  value: _controller.isRunning,
                  onChanged: (value) {
                    if (value) {
                      _controller.start();
                    } else {
                      _controller.stop();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              _controller.status,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_controller.activeStopPrice != null) ...[
              const SizedBox(height: 6),
              Text(
                'حد ضرر فعال: ${_controller.activeStopPrice!.toStringAsFixed(6)}',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_controller.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                _controller.lastError!,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricCard(
    String title,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 21),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // -------------------- CHART --------------------

  Widget _chartCard() {
    final candles = _controller.candles;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_controller.symbol),
                Text(_controller.interval),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 230,
              width: double.infinity,
              child: candles.length < 2
                  ? const Center(
                      child: Text('در انتظار دریافت کندل‌های نمودار'),
                    )
                  : CustomPaint(
                      painter: TradingChartPainter(
                        candles: candles,
                        fills: _controller.portfolio.fills,
                      ),
                      child: const SizedBox.expand(),
                    ),
            ),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 18,
              children: [
                _Legend(color: Colors.greenAccent, label: 'خرید'),
                _Legend(color: Colors.redAccent, label: 'فروش'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- SIGNAL --------------------

  Widget _signalCard() {
    final signal = _controller.latestSignal;

    if (signal == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('هنوز تحلیل معتبری دریافت نشده است'),
        ),
      );
    }

    final color = switch (signal.direction) {
      SignalDirection.buy => Colors.greenAccent,
      SignalDirection.sell => Colors.redAccent,
      SignalDirection.hold => Colors.orangeAccent,
    };

    final label = switch (signal.direction) {
      SignalDirection.buy => 'خرید',
      SignalDirection.sell => 'فروش',
      SignalDirection.hold => 'انتظار',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'اطمینان: ${(signal.confidence * 100).toStringAsFixed(0)}٪',
                ),
              ],
            ),
            const Divider(height: 24),
            ...signal.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle, size: 7),
                    const SizedBox(width: 8),
                    Expanded(child: Text(reason)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- MARKETS --------------------

  Widget _markets() {
    final isForex = _controller.selectedMarket == MarketType.forex;
    final symbols = isForex
        ? ['EURUSD=X', 'GBPUSD=X', 'USDJPY=X', 'AUDUSD=X', 'USDCAD=X', 'USDCHF=X']
        : ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT', 'ADAUSDT', 'DOGEUSDT'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('انتخاب بازار'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: DropdownButtonFormField<MarketType>(
              value: _controller.selectedMarket,
              decoration: const InputDecoration(
                labelText: 'بازار معاملاتی',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: MarketType.crypto, child: Text('رمزارز')),
                DropdownMenuItem(value: MarketType.forex, child: Text('فارکس')),
              ],
              onChanged: (value) {
                if (value != null) _controller.changeMarket(value);
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _sectionTitle(isForex ? 'انتخاب جفت‌ارز فارکس' : 'انتخاب نماد رمزارز'),
        Card(
          child: Column(
            children: symbols.map((symbol) {
              return ListTile(
                title: Text(symbol.replaceAll('=X', '')),
                trailing: _controller.symbol == symbol
                    ? const Icon(
                        Icons.check_circle,
                        color: Colors.greenAccent,
                      )
                    : null,
                onTap: () => _controller.changeSymbol(symbol),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('وضعیت بازارها'),
        _marketStatusCard(
          'رمزارز',
          MarketType.crypto,
        ),
        _marketStatusCard(
          'فارکس',
          MarketType.forex,
        ),
        _marketStatusCard(
          'سهام',
          MarketType.stocks,
        ),
        _marketStatusCard(
          'کالاها',
          MarketType.commodities,
        ),
        _marketStatusCard(
          'شاخص‌ها',
          MarketType.indices,
        ),
      ],
    );
  }

  Widget _marketStatusCard(String title, MarketType market) {
    final supported = ProviderSetup.isMarketSupported(market);

    return Card(
      child: ListTile(
        leading: Icon(
          supported ? Icons.check_circle : Icons.lock_outline,
          color: supported ? Colors.greenAccent : Colors.orangeAccent,
        ),
        title: Text(title),
        subtitle: Text(ProviderSetup.marketStatus(market)),
      ),
    );
  }

  // -------------------- TRADES --------------------

  Widget _trades() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('تاریخچه معاملات آزمایشی'),
        _tradeHistory(),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'خلاصه عملکرد',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _summaryRow(
                  'سود و زیان تحقق‌یافته',
                  '${_controller.realizedPnl.toStringAsFixed(3)} USDT',
                ),
                _summaryRow(
                  'سود و زیان تحقق‌نیافته',
                  '${_controller.unrealizedPnl.toStringAsFixed(3)} USDT',
                ),
                _summaryRow(
                  'کارمزد پرداخت‌شده',
                  '${_controller.portfolio.totalFees.toStringAsFixed(3)} USDT',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tradeHistory({int? limit}) {
    final allFills = _controller.portfolio.fills.reversed.toList();
    final fills = limit == null ? allFills : allFills.take(limit).toList();

    if (fills.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Center(child: Text('هنوز معامله‌ای ثبت نشده است')),
        ),
      );
    }

    return Column(
      children: fills.map((fill) {
        final isBuy = fill.side == SignalDirection.buy;
        final position = _controller.portfolio.positions[fill.symbol];
        final isOpen = isBuy && position != null;
        final isCurrentSymbol = _controller.symbol == fill.symbol;
        final digits = fill.symbol.contains('=X') ? 5 : 6;
        final current = isCurrentSymbol && _controller.hasValidPrice
            ? _controller.currentPrice
            : null;
        final openPnl = isOpen && current != null
            ? (current - position.averageEntryPrice) * position.quantity
            : null;
        final pnl = isBuy ? openPnl : fill.realizedPnl;
        final pnlColor = pnl == null
            ? Colors.grey
            : pnl >= 0 ? Colors.greenAccent : Colors.redAccent;
        final notional = fill.price * fill.quantity;

        String priceText(double? value) => value == null
            ? '—'
            : value.toStringAsFixed(digits);

        Widget detail(String label, String value, {Color? color}) {
          return Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isBuy ? Icons.north_east : Icons.south_west,
                      color: isBuy ? Colors.greenAccent : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${isBuy ? 'خرید' : 'فروش'} ${fill.symbol.replaceAll('=X', '')}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: isOpen ? Colors.green.withOpacity(0.15) : Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isOpen ? 'باز' : 'بسته',
                        style: TextStyle(
                          fontSize: 11,
                          color: isOpen ? Colors.greenAccent : Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  fill.time.toLocal().toString().substring(0, 16),
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    detail('نقطه ورود', isBuy ? priceText(fill.price) : '—'),
                    detail('حد ضرر (SL)', isBuy ? priceText(fill.stopLoss) : '—'),
                    detail('TP / حد سود', isBuy ? priceText(fill.takeProfit) : '—'),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    detail('تارگت پوینت', isBuy ? priceText(fill.targetPoints) : '—'),
                    detail('حجم معامله', '${fill.quantity.toStringAsFixed(6)}'),
                    detail('ارزش معامله', '${notional.toStringAsFixed(3)} USDT'),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('سود و زیان', style: TextStyle(fontSize: 12)),
                    Text(
                      pnl == null
                          ? (isOpen ? 'قیمت فعلی در دسترس نیست' : '—')
                          : '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(4)} USDT',
                      style: TextStyle(fontWeight: FontWeight.bold, color: pnlColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _summaryRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Text(value),
        ],
      ),
    );
  }

  // -------------------- SETTINGS --------------------

  Widget _settings() {
    const intervals = [
      '1m',
      '5m',
      '15m',
      '30m',
      '1h',
      '1d',
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('سبک معاملاتی'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: DropdownButtonFormField<TradingStyle>(
              value: _controller.style,
              decoration: const InputDecoration(
                labelText: 'انتخاب سبک',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: TradingStyle.fast,
                  child: Text('سریع'),
                ),
                DropdownMenuItem(
                  value: TradingStyle.mediumTerm,
                  child: Text('میان‌مدت'),
                ),
                DropdownMenuItem(
                  value: TradingStyle.longTerm,
                  child: Text('بلندمدت'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _controller.changeStyle(value);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('تایم‌فریم'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: DropdownButtonFormField<String>(
              value: _controller.interval,
              decoration: const InputDecoration(
                labelText: 'انتخاب تایم‌فریم',
                border: OutlineInputBorder(),
              ),
              items: intervals.map((interval) {
                return DropdownMenuItem(
                  value: interval,
                  child: Text(interval),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  _controller.changeInterval(value);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('مدیریت ریسک'),
        Card(
          child: Column(
            children: const [
              ListTile(
                title: Text('ریسک پایه هر معامله'),
                trailing: Text('۰٫۵٪'),
              ),
              ListTile(
                title: Text('حد ضرر روزانه'),
                trailing: Text('۱٪'),
              ),
              ListTile(
                title: Text('حداکثر افت سرمایه'),
                trailing: Text('۵٪'),
              ),
              ListTile(
                title: Text('اهرم'),
                trailing: Text('غیرفعال'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('امنیت'),
        const Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.lock),
                title: Text('معاملات واقعی'),
                subtitle: Text('در این نسخه غیرفعال است'),
              ),
              ListTile(
                leading: Icon(Icons.security),
                title: Text('کلیدهای API'),
                subtitle: Text('هنوز هیچ کلید حسابی ثبت نشده است'),
              ),
              ListTile(
                leading: Icon(Icons.warning_amber),
                title: Text('توقف اضطراری'),
                subtitle: Text('خاموش کردن ربات آزمایشی'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _controller.resetDemo,
          icon: const Icon(Icons.restart_alt),
          label: const Text('بازنشانی حساب آزمایشی'),
        ),
      ],
    );
  }
}

// =====================================================
// CHART LEGEND
// =====================================================

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 9, color: color),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

// =====================================================
// CUSTOM CANDLESTICK CHART WITH TRADE MARKERS
// =====================================================

class TradingChartPainter extends CustomPainter {
  final List<Candle> candles;
  final List<PaperFill> fills;

  TradingChartPainter({
    required this.candles,
    required this.fills,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.length < 2 || size.width <= 0 || size.height <= 0) {
      return;
    }

    const left = 8.0;
    const right = 8.0;
    const top = 12.0;
    const bottom = 12.0;

    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;

    final visible = candles.length > 80
        ? candles.sublist(candles.length - 80)
        : candles;

    final minimum = visible.map((c) => c.low).reduce(min);
    final maximum = visible.map((c) => c.high).reduce(max);

    final range = maximum - minimum;

    if (range <= 0) return;

    double y(double price) {
      return top + ((maximum - price) / range) * chartHeight;
    }

    double x(int index) {
      if (visible.length == 1) return left;
      return left + (index / (visible.length - 1)) * chartWidth;
    }

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 0.7;

    for (int i = 0; i <= 4; i++) {
      final gridY = top + chartHeight * i / 4;

      canvas.drawLine(
        Offset(left, gridY),
        Offset(size.width - right, gridY),
        gridPaint,
      );
    }

    final candleWidth = (chartWidth / visible.length * 0.65)
        .clamp(2.0, 10.0).toDouble();

    for (int i = 0; i < visible.length; i++) {
      final candle = visible[i];

      final isBullish = candle.close >= candle.open;

      final color = isBullish
          ? Colors.greenAccent
          : Colors.redAccent;

      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.2;

      final centerX = x(i);

      canvas.drawLine(
        Offset(centerX, y(candle.high)),
        Offset(centerX, y(candle.low)),
        paint,
      );

      final openY = y(candle.open);
      final closeY = y(candle.close);

      final rect = Rect.fromLTRB(
        centerX - candleWidth / 2,
        min(openY, closeY),
        centerX + candleWidth / 2,
        max(openY, closeY) + 1,
      );

      canvas.drawRect(rect, paint);
    }

    final firstTime = visible.first.time;
    final lastTime = visible.last.time;

    for (final fill in fills) {
      if (fill.time.isBefore(firstTime) ||
          fill.time.isAfter(lastTime)) {
        continue;
      }

      int closestIndex = 0;
      int smallestDifference = 1 << 62;

      for (int i = 0; i < visible.length; i++) {
        final difference = visible[i]
            .time
            .difference(fill.time)
            .inMilliseconds
            .abs();

        if (difference < smallestDifference) {
          smallestDifference = difference;
          closestIndex = i;
        }
      }

      final isBuy = fill.side == SignalDirection.buy;
      final markerColor = isBuy
          ? Colors.greenAccent
          : Colors.redAccent;

      final point = Offset(
        x(closestIndex),
        y(fill.price),
      );

      final markerPaint = Paint()..color = markerColor;

      canvas.drawCircle(point, 5, markerPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: isBuy ? 'B' : 'S',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(point.dx + 6, point.dy - 12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TradingChartPainter oldDelegate) {
    return true;
  }
}
