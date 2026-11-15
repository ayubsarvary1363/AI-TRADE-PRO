import 'dart:math';

import 'package:http/http.dart' as http;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';

import 'bsc_network.dart';

/// Stores an encrypted Ethereum V3 keystore in Android secure storage.
/// The user's password is never persisted by this class.
class BscWalletVault {
  static const String _storageKey = 'ai_trade_pro_bsc_keystore_v1';

  final FlutterSecureStorage _storage;
  Wallet? _unlockedWallet;

  BscWalletVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  bool get isUnlocked => _unlockedWallet != null;
  String? get address => _unlockedWallet?.privateKey.address.hexEip55;

  Future<bool> get hasWallet async =>
      (await _storage.read(key: _storageKey))?.isNotEmpty ?? false;

  /// Creates a new random BSC-compatible EVM wallet and stores only its
  /// password-encrypted V3 keystore. This is not a seed phrase backup.
  Future<String> create({required String password}) async {
    if (password.length < 12) {
      throw ArgumentError('رمز کیف پول باید حداقل ۱۲ نویسه داشته باشد');
    }
    if (await hasWallet) {
      throw StateError('کیف پول از قبل ساخته شده است');
    }

    final random = Random.secure();
    final credentials = EthPrivateKey.createRandom(random);
    final wallet = Wallet.createNew(credentials, password, random);
    final encoded = wallet.toJson();
    await _storage.write(key: _storageKey, value: encoded);
    _unlockedWallet = wallet;
    return wallet.privateKey.address.hexEip55;
  }

  Future<String> unlock({required String password}) async {
    final encoded = await _storage.read(key: _storageKey);
    if (encoded == null || encoded.isEmpty) {
      throw StateError('کیف پولی روی این دستگاه ساخته نشده است');
    }
    final wallet = Wallet.fromJson(encoded, password);
    _unlockedWallet = wallet;
    return wallet.privateKey.address.hexEip55;
  }

  void lock() {
    _unlockedWallet = null;
  }

  /// Reads native BNB balance only. It never signs or sends a transaction.
  Future<double> readBnbBalance({Web3Client? client}) async {
    final current = _unlockedWallet;
    if (current == null) throw StateError('ابتدا کیف پول را باز کنید');
    final rpc = client ?? Web3Client(BscNetwork.rpcUrl, http.Client());
    try {
      final amount = await rpc.getBalance(current.privateKey.address);
      return amount.getValueInUnit(EtherUnit.ether);
    } finally {
      if (client == null) await rpc.dispose();
    }
  }

  /// Deletes the encrypted keystore from this device. This cannot recover
  /// funds or erase copies/backups elsewhere; caller must confirm explicitly.
  Future<void> deleteWallet() async {
    _unlockedWallet = null;
    await _storage.delete(key: _storageKey);
  }
}
