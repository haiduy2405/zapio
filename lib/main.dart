import 'package:flutter/material.dart';

import 'ui/ir_screens.dart';
import 'ui/wifi_screens.dart';

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
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [IrHomeScreen(), WifiHomeScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.settings_remote), label: 'Hồng ngoại'),
          NavigationDestination(icon: Icon(Icons.wifi), label: 'Wi-Fi'),
        ],
      ),
    );
  }
}
