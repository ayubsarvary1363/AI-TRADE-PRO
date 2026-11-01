import 'package:flutter/material.dart';
import 'engine.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _botEnabled = false;
  final PaperPortfolio _portfolio = PaperPortfolio(initialUsdt: 50);

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
            Icon(Icons.auto_graph, color: Color(0xFF37D996)),
            SizedBox(width: 9),
            Text('AI Trade Pro', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Chip(
              avatar: const Icon(Icons.science, size: 16),
              label: const Text('Paper'),
              side: BorderSide.none,
              backgroundColor: const Color(0xFF173B34),
            ),
          ),
        ],
      ),
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'داشبورد'),
          NavigationDestination(icon: Icon(Icons.candlestick_chart), label: 'بازارها'),
          NavigationDestination(icon: Icon(Icons.psychology_alt_outlined), label: 'تحلیل هوشمند'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'تنظیمات'),
        ],
      ),
    );
  }

  Widget _dashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusCard(),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('موجودی آزمایشی', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text('\$${_portfolio.cash.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              const Text('USDT مجازی · بدون اتصال به حساب واقعی',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _metric('معاملات ثبت‌شده', '${_portfolio.fills.length}', Icons.receipt_long)),
          const SizedBox(width: 10),
          Expanded(child: _metric('سود و زیان تحقق‌یافته', '—', Icons.show_chart)),
        ]),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('وضعیت اتصال بازار', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Row(children: [
                Icon(Icons.cloud_off, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Expanded(child: Text('هنوز به منبع قیمت زنده متصل نشده است.')),
              ]),
              SizedBox(height: 8),
              Text('قیمت یا سیگنال ساختگی نمایش داده نمی‌شود.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        const Text('میانبرها', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(label: const Text('تحلیل هوشمند'), onPressed: () => setState(() => _tab = 2)),
          ActionChip(label: const Text('بازارها'), onPressed: () => setState(() => _tab = 1)),
          ActionChip(label: const Text('تنظیمات ریسک'), onPressed: () => setState(() => _tab = 3)),
        ]),
      ],
    );
  }

  Widget _statusCard() {
    return Card(
      color: _botEnabled ? const Color(0xFF123C32) : const Color(0xFF202B3B),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(_botEnabled ? Icons.play_circle : Icons.pause_circle,
              size: 34, color: _botEnabled ? Colors.greenAccent : Colors.orangeAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_botEnabled ? 'ربات آماده اجرا' : 'ربات متوقف است',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              const Text('نسخه آزمایشی؛ اجرای خودکار هنوز قفل است.',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Switch(
            value: _botEnabled,
            onChanged: (value) => setState(() => _botEnabled = value),
          ),
        ]),
      ),
    );
  }

  Widget _markets() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('بازارهای تحت پشتیبانی', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('دو منبع در طراحی در نظر گرفته شده‌اند؛ قیمت‌ها تا اتصال API خالی می‌مانند.',
          style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 14),
      _marketTile('نوبیتکس', 'بازار داخلی · USDT', Icons.account_balance),
      _marketTile('بازار جهانی', 'صرافی‌های بین‌المللی · USDT', Icons.public),
      const SizedBox(height: 12),
      const Card(child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('اتصال زنده هنوز پیکربندی نشده است. در مرحله بعد، API عمومی قیمت و کندل اضافه می‌شود.'),
      )),
    ]);
  }

  Widget _signals() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('موتور تحلیل هوشمند', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      _feature('تحلیل روند', 'EMA 9 و EMA 21', Icons.trending_up),
      _feature('مومنتوم', 'RSI با دوره ۱۴', Icons.speed),
      _feature('همگرایی و واگرایی', 'MACD با تنظیمات استاندارد', Icons.multiline_chart),
      _feature('امتیازدهی چندعاملی', 'ترکیب شاخص‌ها و دلایل قابل مشاهده', Icons.psychology),
      const SizedBox(height: 12),
      const Card(child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('تا دریافت داده واقعی و آزمون تاریخی کافی، هیچ سیگنال خرید یا فروش صادر نمی‌شود. این موتور فعلاً هسته اولیه قانون‌محور است، نه مدل یادگیری ماشین آموزش‌دیده.'),
      )),
    ]);
  }

  Widget _settings() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('تنظیمات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      _feature('سرمایه آزمایشی', '۵۰ USDT', Icons.account_balance_wallet),
      _feature('ریسک هر معامله', '۰٫۵٪ از سرمایه', Icons.shield_outlined),
      _feature('حداکثر زیان روزانه', '۱٪ از سرمایه ابتدای روز', Icons.warning_amber),
      _feature('حالت معامله', 'آزمایشی فعال · معامله واقعی غیرفعال', Icons.science),
      const SizedBox(height: 12),
      const Card(child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('کلید API یا رمز صرافی را در این نسخه وارد نکنید. ابتدا اتصال عمومی و معاملات کاغذی را کامل و آزمایش می‌کنیم.'),
      )),
    ]);
  }

  Widget _metric(String title, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: const Color(0xFF37D996)),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(title, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ]),
    ),
  );

  Widget _marketTile(String title, String subtitle, IconData icon) => Card(
    child: ListTile(
      leading: CircleAvatar(backgroundColor: const Color(0xFF1B3542), child: Icon(icon)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Text('در انتظار اتصال', style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
    ),
  );

  Widget _feature(String title, String subtitle, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon, color: const Color(0xFF37D996)),
      title: Text(title),
      subtitle: Text(subtitle),
    ),
  );
}
