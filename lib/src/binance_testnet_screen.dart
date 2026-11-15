import 'dart:async';

import 'package:flutter/material.dart';

import 'binance_spot_testnet_provider.dart';
import 'exchange_credential_store.dart';
import 'trading_execution.dart';

/// Account connection and balance inspection for Binance Spot TESTNET only.
/// No production host, live-order mode, futures, margin or withdrawals.
class BinanceTestnetScreen extends StatefulWidget {
  const BinanceTestnetScreen({super.key});

  @override
  State<BinanceTestnetScreen> createState() => _BinanceTestnetScreenState();
}

class _BinanceTestnetScreenState extends State<BinanceTestnetScreen> {
  static const String _exchangeId = 'binance_spot_testnet';

  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();
  final _credentialStore = ExchangeCredentialStore();

  BinanceSpotTestnetProvider? _provider;
  List<ExchangeBalance> _balances = const [];
  bool _busy = false;
  bool _connected = false;
  String _status = 'کلیدهای مخصوص Spot Testnet بایننس را وارد کنید.';

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    final provider = _provider;
    if (provider != null) {
      unawaited(provider.close());
    }
    super.dispose();
  }

  Future<void> _saveAndCheck() async {
    if (_busy) return;
    final key = _apiKeyController.text.trim();
    final secret = _apiSecretController.text;
    if (key.isEmpty || secret.isEmpty) {
      setState(() => _status = 'هر دو فیلد API Key و Secret لازم هستند.');
      return;
    }

    setState(() {
      _busy = true;
      _connected = false;
      _balances = const [];
      _status = 'در حال ذخیره امن کلیدها و بررسی اتصال...';
    });

    try {
      await _credentialStore.save(
        exchangeId: _exchangeId,
        apiKey: key,
        apiSecret: secret,
      );

      final oldProvider = _provider;
      if (oldProvider != null) await oldProvider.close();

      final provider = BinanceSpotTestnetProvider(
        credentials: _credentialStore,
      );
      _provider = provider;

      final connected = await provider.checkTradingConnection();
      if (!connected) {
        if (mounted) {
          setState(() {
            _connected = false;
            _status = 'اتصال ناموفق بود. کلیدها باید مخصوص Binance Spot Testnet باشند و مجوز خواندن حساب داشته باشند.';
          });
        }
        return;
      }

      final balances = await provider.fetchBalances();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _balances = balances;
        _status = 'اتصال به Binance Spot Testnet موفق بود. این موجودی آزمایشی است و پول واقعی نیست.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _connected = false;
          _status = 'خطا در اتصال: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshBalances() async {
    final provider = _provider;
    if (!_connected || provider == null || _busy) return;
    setState(() {
      _busy = true;
      _status = 'در حال دریافت دوباره موجودی آزمایشی...';
    });
    try {
      final balances = await provider.fetchBalances();
      if (!mounted) return;
      setState(() {
        _balances = balances;
        _status = 'موجودی Binance Spot Testnet به‌روز شد.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'دریافت موجودی ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final provider = _provider;
      _provider = null;
      if (provider != null) await provider.close();
      await _credentialStore.delete(_exchangeId);
      _apiKeyController.clear();
      _apiSecretController.clear();
      if (!mounted) return;
      setState(() {
        _connected = false;
        _balances = const [];
        _status = 'کلیدهای ذخیره‌شده از حافظه امن برنامه پاک شدند.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'پاک‌کردن کلیدها ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleBalances = _balances
        .where((balance) => balance.free > 0 || balance.locked > 0)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('اتصال Binance آزمایشی')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.science, color: Colors.orangeAccent),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'فقط Binance Spot Testnet',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'این صفحه فقط به محیط آزمایشی بایننس وصل می‌شود. کلید حساب اصلی یا کلید دارای مجوز برداشت را اینجا وارد نکنید.',
                  ),
                  const SizedBox(height: 10),
                  const SelectableText('https://testnet.binance.vision/'),
                  const SizedBox(height: 6),
                  const Text(
                    'در سایت بالا کلید API آزمایشی بسازید. کلیدها در حافظه امن گوشی ذخیره می‌شوند و به مخزن GitHub ارسال نمی‌شوند.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKeyController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Binance Testnet API Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiSecretController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Binance Testnet Secret',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _saveAndCheck,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: const Text('ذخیره امن و بررسی اتصال'),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: Icon(
                _connected ? Icons.check_circle : Icons.info_outline,
                color: _connected ? Colors.greenAccent : Colors.orangeAccent,
              ),
              title: Text(_connected ? 'متصل به Binance Testnet' : 'وضعیت اتصال'),
              subtitle: Text(_status),
            ),
          ),
          if (_connected) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'موجودی آزمایشی حساب',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                IconButton(
                  onPressed: _busy ? null : _refreshBalances,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'به‌روزرسانی موجودی',
                ),
              ],
            ),
            Card(
              child: visibleBalances.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('در حساب آزمایشی موجودی غیرصفر پیدا نشد.'),
                    )
                  : Column(
                      children: visibleBalances.map((balance) {
                        return ListTile(
                          title: Text(balance.asset),
                          subtitle: Text(
                            'آزاد: ${balance.free.toStringAsFixed(8)}',
                          ),
                          trailing: Text(
                            'قفل‌شده: ${balance.locked.toStringAsFixed(8)}',
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 8),
            const Text(
              'در این مرحله فقط اتصال و خواندن موجودی فعال است؛ ارسال سفارش خودکار هنوز به موتور معاملات وصل نشده است.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy ? null : _disconnect,
            icon: const Icon(Icons.delete_outline),
            label: const Text('قطع اتصال و پاک‌کردن کلیدها از گوشی'),
          ),
        ],
      ),
    );
  }
}
