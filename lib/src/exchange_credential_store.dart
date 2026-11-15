import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores exchange API credentials only in the platform secure keystore.
/// Never write credentials to logs, SharedPreferences, source control or UI state.
class ExchangeCredentialStore {
  final FlutterSecureStorage _storage;

  ExchangeCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  String _key(String exchangeId, String suffix) {
    final id = exchangeId.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_-]{2,32}$').hasMatch(id)) {
      throw ArgumentError('Invalid exchange identifier');
    }
    return 'exchange_${id}_${suffix}';
  }

  Future<void> save({
    required String exchangeId,
    required String apiKey,
    required String apiSecret,
  }) async {
    if (apiKey.trim().isEmpty || apiSecret.isEmpty) {
      throw ArgumentError('API credentials cannot be empty');
    }
    await _storage.write(key: _key(exchangeId, 'api_key'), value: apiKey.trim());
    await _storage.write(key: _key(exchangeId, 'api_secret'), value: apiSecret);
  }

  Future<String?> readApiKey(String exchangeId) =>
      _storage.read(key: _key(exchangeId, 'api_key'));

  Future<String?> readApiSecret(String exchangeId) =>
      _storage.read(key: _key(exchangeId, 'api_secret'));

  Future<void> delete(String exchangeId) async {
    await _storage.delete(key: _key(exchangeId, 'api_key'));
    await _storage.delete(key: _key(exchangeId, 'api_secret'));
  }

  Future<bool> hasCredentials(String exchangeId) async {
    final key = await readApiKey(exchangeId);
    final secret = await readApiSecret(exchangeId);
    return key != null && key.isNotEmpty && secret != null && secret.isNotEmpty;
  }
}
