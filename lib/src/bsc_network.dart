/// BNB Smart Chain network parameters used by the self-custody wallet.
/// Public RPC is read-only from the app's perspective; transaction execution
/// must be added only after quote simulation and explicit user consent.
class BscNetwork {
  static const int chainId = 56;
  static const String name = 'BNB Smart Chain';
  static const String symbol = 'BNB';
  static const int nativeCurrencyDecimals = 18;
  static const String rpcUrl = 'https://bsc-dataseed.binance.org/';
  static const String explorerUrl = 'https://bscscan.com';
  static const String usdtContract =
      '0x55d398326f99059fF775485246999027B3197955';

  const BscNetwork._();

  static bool isValidAddress(String address) {
    final value = address.startsWith('0x') ? address.substring(2) : address;
    return RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(value);
  }
}
