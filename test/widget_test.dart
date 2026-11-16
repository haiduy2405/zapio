import 'package:flutter_test/flutter_test.dart';
import 'package:zapio/main.dart';

void main() {
  testWidgets('app shell builds', (tester) async {
    await tester.pumpWidget(const ZapioApp());
    expect(find.text('Hồng ngoại'), findsWidgets);
  });
}
