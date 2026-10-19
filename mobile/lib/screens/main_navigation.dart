import 'package:flutter/material.dart';
import '../services/translations.dart';
import 'home_screen.dart';
import 'sensors_screen.dart';
import 'alerts_screen.dart';
import 'history_screen.dart';
import 'device_screen.dart';
import 'scan_screen.dart';
import '../utils/app_routes.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _tab = 0;
  static const _tabs = [
    HomeScreen(),
    SensorsScreen(),
    AlertsScreen(),
    HistoryScreen(),
    DeviceScreen(),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: _tabs),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
              context, fadeSlideTo(const ScanScreen())),
          icon: const Icon(Icons.document_scanner_outlined),
          label: Text(tr('Scan crop')),
          tooltip: tr('Scan crop'),
        ),
        bottomNavigationBar: ValueListenableBuilder<AppLanguage>(
          valueListenable: LanguageService.instance.language,
          builder: (context, _, __) => NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: tr('Home')),
            NavigationDestination(
                icon: const Icon(Icons.thermostat_outlined),
                selectedIcon: const Icon(Icons.thermostat),
                label: tr('Environment')),
            NavigationDestination(
                icon: const Icon(Icons.notifications_outlined),
                selectedIcon: const Icon(Icons.notifications),
                label: tr('Alerts')),
            NavigationDestination(
                icon: const Icon(Icons.history),
                selectedIcon: const Icon(Icons.history),
                label: tr('History')),
            NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: tr('Device')),
          ],
          ),
        ),
      );
}
