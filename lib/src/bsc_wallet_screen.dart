import 'package:flutter/material.dart';
import 'bsc_wallet_vault.dart';

class BscWalletScreen extends StatefulWidget {
  const BscWalletScreen({super.key});
  @override
  State<BscWalletScreen> createState() => _BscWalletScreenState();
}

class _BscWalletScreenState extends State<BscWalletScreen> {
  final BscWalletVault _vault = BscWalletVault();
  final TextEditingController _password = TextEditingController();
  bool _checking = true, _hasWallet = false, _busy = false;
  String? _address, _message;
  double? _bnbBalance;

  @override
  void initState() { super.initState(); _refreshWalletState(); }

  @override
  void dispose() { _password.dispose(); _vault.lock(); super.dispose(); }

  Future<void> _refreshWalletState() async {
    try {
      final exists = await _vault.hasWallet;
      if (!mounted) return;
      setState(() { _hasWallet = exists; _checking = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _checking = false; _message = 'بررسی کیف پول ناموفق بود: $error'; });
    }
  }

  Future<void> _createOrUnlock() async {
    if (_busy) return;
    final password = _password.text;
    if (password.length < 12) {
      setState(() => _message = 'رمز باید حداقل ۱۲ نویسه داشته باشد.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      final address = _hasWallet
          ? await _vault.unlock(password: password)
          : await _vault.create(password: password);
      if (!mounted) return;
      setState(() {
        _address = address;
        _bnbBalance = null;
        _message = _hasWallet ? 'کیف پول باز شد.' : 'کیف پول ساخته شد؛ عبارت بازیابی هنوز پشتیبانی نمی‌شود.';
        _hasWallet = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'عملیات انجام نشد: $error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _readBalance() async {
    if (!_vault.isUnlocked || _busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      final balance = await _vault.readBnbBalance();
      if (!mounted) return;
      setState(() { _bnbBalance = balance; _message = 'موجودی BNB از شبکه خوانده شد.'; });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'خواندن موجودی ناموفق بود: $error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  void _lock() {
    _vault.lock();
    setState(() { _address = null; _bnbBalance = null; _password.clear(); _message = 'کیف پول قفل شد.'; });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.account_balance_wallet, size: 28), SizedBox(width: 10),
              Text('کیف پول داخلی', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            const Text('شبکه: BNB Smart Chain (BEP20)'),
            const Text('Chain ID: 56'),
            const SizedBox(height: 12),
            const Text('هشدار: عبارت بازیابی و پشتیبان‌گیری هنوز آماده نیست. فعلاً هیچ دارایی واقعی به این کیف پول واریز نکنید.',
              style: TextStyle(color: Colors.orangeAccent)),
          ]),
        )),
        const SizedBox(height: 12),
        if (_checking) const Center(child: CircularProgressIndicator())
        else if (_address == null) ...[
          Text(_hasWallet ? 'باز کردن کیف پول' : 'ساخت کیف پول جدید',
            style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _password, obscureText: true,
            decoration: const InputDecoration(labelText: 'رمز کیف پول (حداقل ۱۲ نویسه)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy ? null : _createOrUnlock,
            icon: Icon(_hasWallet ? Icons.lock_open : Icons.add),
            label: Text(_busy ? 'لطفاً صبر کنید...' : (_hasWallet ? 'باز کردن کیف پول' : 'ساخت کیف پول'))),
        ] else ...[
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('آدرس عمومی کیف پول'),
              const SizedBox(height: 6),
              SelectableText(_address!, style: const TextStyle(fontSize: 13)),
              const Divider(height: 24),
              const Text('موجودی BNB'),
              Text(_bnbBalance == null ? 'برای دریافت موجودی دکمه زیر را بزنید' : '${_bnbBalance!.toStringAsFixed(8)} BNB',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _busy ? null : _readBalance,
                icon: const Icon(Icons.refresh), label: const Text('به‌روزرسانی موجودی BNB')),
              TextButton.icon(onPressed: _lock, icon: const Icon(Icons.lock), label: const Text('قفل کردن کیف پول')),
            ]),
          )),
        ],
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, style: const TextStyle(color: Colors.orangeAccent)),
        ],
        const SizedBox(height: 12),
        const Text('در این نسخه فقط ساخت/بازکردن کیف پول و مشاهده آدرس و موجودی BNB فعال است. موجودی USDT، عبارت بازیابی، ارسال و دریافت و اتصال DEX هنوز فعال نیست.',
          style: TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }
}
