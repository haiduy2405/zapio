import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapio/main.dart';

void main() {
  testWidgets('home shows empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZapioApp());
    await tester.pumpAndSettle();
    expect(find.text('Zapio'), findsOneWidget);
    expect(find.text('No devices yet'), findsOneWidget);
  });
}
