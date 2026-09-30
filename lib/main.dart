import 'package:flutter/material.dart';

import 'days_screen.dart';
import 'labour_list_screen.dart';
import 'rates_screen.dart';
import 'reports_screen.dart';
import 'today_screen.dart';
import 'utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LabourPayApp());
}

class LabourPayApp extends StatelessWidget {
  const LabourPayApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Labour Pay',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const PinGate(child: HomeShell()),
    );
  }
}

/// Shows a PIN screen at start when a PIN has been set in Settings.
class PinGate extends StatefulWidget {
  final Widget child;
  const PinGate({super.key, required this.child});
  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  bool loading = true;
  bool unlocked = false;
  String pin = '';
  final c = TextEditingController();
  String error = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    pin = await Db.setting('pin');
    if (!mounted) return;
    setState(() {
      loading = false;
      unlocked = pin.isEmpty;
    });
  }

  void _try() {
    if (c.text == pin) {
      setState(() => unlocked = true);
    } else {
      setState(() {
        error = 'Wrong PIN';
        c.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (unlocked) return widget.child;
    return Scaffold(
      backgroundColor: kInk,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, color: Colors.white, size: 44),
              const SizedBox(height: 12),
              const Text('Labour Pay',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),
              TextField(
                controller: c,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, letterSpacing: 8),
                decoration: dec('Enter PIN'),
                onSubmitted: (_) => _try(),
              ),
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error, style: const TextStyle(color: Color(0xFFFFB4A8))),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kJute),
                  onPressed: _try,
                  child: const Text('Unlock'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int idx = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: idx,
        children: const [
          TodayScreen(),
          DaysScreen(),
          LabourListScreen(),
          RatesScreen(),
          ReportsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Today'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Days'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Labour'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Rates'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
  }
}
