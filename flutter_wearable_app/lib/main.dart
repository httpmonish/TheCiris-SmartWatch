import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'core/constants.dart';
import 'screens/home_dashboard.dart';
import 'screens/shelter_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/contact_setup.dart';
import 'screens/history_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AegisGuardianApp());
}

class AegisGuardianApp extends StatelessWidget {
  const AegisGuardianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aegis Guardian IoT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeDashboard(),
    ShelterScreen(),
    ConnectScreen(),
    ContactSetup(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          border: Border(top: BorderSide(color: AppColors.surfaceBorder, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Vitals',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.home_work_rounded),
              label: 'Shelters',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bluetooth_rounded),
              label: 'Connect',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contact_phone_rounded),
              label: 'Contacts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              label: 'Logs',
            ),
          ],
        ),
      ),
    );
  }
}
