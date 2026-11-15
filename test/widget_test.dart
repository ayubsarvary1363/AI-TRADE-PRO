import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_s_trade/src/app.dart';

void main() {
  testWidgets('application starts and renders its MaterialApp', (tester) async {
    await tester.pumpWidget(const AiTradeProApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('RISE S TRADE'), findsWidgets);
  });
}
