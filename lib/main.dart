import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ui/home_screen.dart';

void main() => runApp(const ZapioApp());

class ZapioApp extends StatelessWidget {
  const ZapioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00BFA6),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Zapio',
      debugShowCheckedModeBanner: false,
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
        cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
