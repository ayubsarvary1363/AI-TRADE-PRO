import 'package:flutter_test/flutter_test.dart';
import 'package:ai_trade_pro/src/app.dart';

void main() {
  testWidgets('shows app title and paper balance', (tester) async {
    await tester.pumpWidget(const AiTradeProApp());
    expect(find.text('AI Trade Pro'), findsOneWidget);
    expect(find.textContaining('50.00'), findsOneWidget);
  });
}
