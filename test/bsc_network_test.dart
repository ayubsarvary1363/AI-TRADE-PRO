import 'package:flutter_test/flutter_test.dart';
import 'package:rise_s_trade/src/bsc_network.dart';

void main() {
  group('BscNetwork', () {
    test('uses BNB Smart Chain mainnet chain id', () {
      expect(BscNetwork.chainId, 56);
      expect(BscNetwork.name, 'BNB Smart Chain');
      expect(BscNetwork.rpcUrl, startsWith('https://'));
    });

    test('contains a valid USDT BEP20 contract address', () {
      expect(BscNetwork.isValidAddress(BscNetwork.usdtContract), isTrue);
    });

    test('validates EVM addresses', () {
      expect(BscNetwork.isValidAddress('0x' + 'a' * 40), isTrue);
      expect(BscNetwork.isValidAddress('0x1234'), isFalse);
    });
  });
}
