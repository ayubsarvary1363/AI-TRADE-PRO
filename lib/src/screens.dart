
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  bool _paperBotEnabled = false;

  static const Color green = Color(0xFF16A36A);
  static const Color background = Color(0xFF0B1220);
  static const Color panel = Color(0xFF121D2E);

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      _markets(),
      _trading(),
      _settings(),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          title: const Text(
            'AI Trade Pro',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none),
            ),
          ],
        ),
        body: SafeArea(
          child: pages[_selectedTab],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: panel,
          selectedIndex: _selectedTab,
          onDestinationSelected: (value) {
            setState(() => _selectedTab = value);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'داشبورد',
            ),
            NavigationDestination(
              icon: Icon(Icons.candlestick_chart_outlined),
              label: 'بازارها',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'معاملات',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              label: 'تنظیمات',
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusCard(),
        const SizedBox(height: 16),
        const Text(
          'وضعیت سرمایه',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _statCard('سرمایه اولیه', '50.00 USDT')),
            const SizedBox(width: 10),
            Expanded(child: _statCard('سود و زیان', '0.00 USDT')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _statCard('معاملات', '0')),
            const SizedBox(width: 10),
            Expanded(child: _statCard('موجودی آزاد', '50.00 USDT')),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'کنترل ربات',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Card(
          color: panel,
          child: SwitchListTile(
            activeThumbColor: green,
            title: const Text('ربات آزمایشی'),
            subtitle: Text(
              _paperBotEnabled
                  ? 'درخواست فعال‌سازی ثبت شده؛ موتور هنوز متصل نیست.'
                  : 'ربات آزمایشی متوقف است.',
            ),
            value: _paperBotEnabled,
            onChanged: (value) {
              setState(() => _paperBotEnabled = value);
            },
          ),
        ),
        const SizedBox(height: 12),
        _infoCard(
          Icons.security,
          'معاملات واقعی',
          'تا تکمیل اتصال امن، آزمون سفارش‌ها و تأیید کاربر غیرفعال است.',
        ),
        const SizedBox(height: 12),
        _infoCard(
          Icons.warning_amber_outlined,
          'وضعیت اتصال',
          'هنوز منبع قیمت زنده به این صفحه متصل نشده است.',
        ),
      ],
    );
  }

  Widget _statusCard() {
    return Card(
      color: panel,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.smart_toy_outlined,
                color: green, size: 38),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Trade Pro',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'نسخه توسعه و آزمایش',
                    style: TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            const Icon(Icons.circle, color: Colors.orange, size: 12),
          ],
        ),
      ),
    );
  }

  Widget _markets() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'بازارهای قابل پشتیبانی',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        _marketTile('رمزارزها', 'Crypto', Icons.currency_bitcoin),
        _marketTile('فارکس', 'Forex', Icons.currency_exchange),
        _marketTile('سهام', 'Stocks', Icons.show_chart),
        _marketTile('کالاها و شاخص‌ها', 'Commodities & Indices',
            Icons.analytics_outlined),
        const SizedBox(height: 14),
        _infoCard(
          Icons.info_outline,
          'اتصال بازار',
          'نمایش این بازارها به معنی فعال‌بودن اتصال معاملاتی آن‌ها نیست. '
              'اتصال هر ارائه‌دهنده باید جداگانه آزمایش شود.',
        ),
      ],
    );
  }

  Widget _trading() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'معاملات و سوابق',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        _infoCard(
          Icons.show_chart,
          'نمودار معاملات',
          'پس از اتصال داده‌های بازار، نمودار قیمت و علامت‌های دقیق خرید و فروش نمایش داده می‌شوند.',
        ),
        const SizedBox(height: 12),
        _infoCard(
          Icons.receipt_long,
          'تاریخچه سفارش‌ها',
          'هنوز معامله‌ای ثبت نشده است.',
        ),
        const SizedBox(height: 12),
        _infoCard(
          Icons.account_balance_wallet_outlined,
          'مدیریت دارایی',
          'خرید و فروش فقط در محدوده موجودی واقعی یا مجازی مجاز خواهد بود.',
        ),
      ],
    );
  }

  Widget _settings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'تنظیمات و مدیریت ریسک',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        _infoCard(Icons.speed, 'سبک معاملاتی',
            'سریع، میان‌مدت و بلندمدت'),
        _infoCard(Icons.timer_outlined, 'تایم‌فریم',
            'انتخاب متناسب با بازار و منبع داده'),
        _infoCard(Icons.shield_outlined, 'ریسک هر معامله',
            'حداکثر ۰٫۵ درصد سرمایه'),
        _infoCard(Icons.trending_down, 'حد ضرر روزانه',
            'حداکثر ۱ درصد سرمایه'),
        _infoCard(Icons.warning_amber, 'حداکثر افت سرمایه',
            '۵ درصد؛ سپس توقف معاملات'),
        _infoCard(Icons.lock_outline, 'امنیت API',
            'کلیدها باید در فضای امن و رمزگذاری‌شده نگهداری شوند.'),
        _infoCard(Icons.emergency, 'توقف اضطراری',
            'در نسخه عملیاتی امکان توقف فوری سفارش‌گذاری فراهم می‌شود.'),
      ],
    );
  }

  Widget _statCard(String title, String value) {
    return Card(
      color: panel,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(IconData icon, String title, String description) {
    return Card(
      color: panel,
      child: ListTile(
        leading: Icon(icon, color: green),
        title: Text(title),
        subtitle: Text(description),
      ),
    );
  }

  Widget _marketTile(String title, String subtitle, IconData icon) {
    return Card(
      color: panel,
      child: ListTile(
        leading: Icon(icon, color: green),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.lock_outline, color: Colors.white38),
      ),
    );
  }
}
