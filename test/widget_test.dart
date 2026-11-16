import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapio/main.dart';
import 'package:zapio/ui/home_screen.dart';

void main() {
  testWidgets('home shows empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZapioApp());
    await tester.pumpAndSettle();
    expect(find.text('Zapio'), findsOneWidget);
    expect(find.text('No devices yet'), findsOneWidget);
    expect(find.text('Made by duyluma'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not check for updates'), findsOneWidget);
  });

  testWidgets('home shows the installed app version', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('zapio/update');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'versionCode');
      return {'code': 42, 'name': '0.2.42'};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('v0.2.42'), findsOneWidget);
  });
}
