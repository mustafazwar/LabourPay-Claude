import 'package:flutter/material.dart';

import 'backup_screen.dart';
import 'utils.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, String> s = {};
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    s = await Db.allSettings();
    if (mounted) setState(() => loaded = true);
  }

  Future<void> _set(String k, String v) async {
    await Db.setSetting(k, v);
    await _load();
    notifyData();
  }

  Future<void> _pickRound() async {
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Round each share to'),
        children: [
          for (final n in [1, 5, 10, 50])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, n),
              child: Text(n == 1 ? 'Nearest rupee' : 'Nearest Rs $n'),
            ),
        ],
      ),
    );
    if (v != null) await _set('round', '$v');
  }

  Future<void> _pin() async {
    final has = (s['pin'] ?? '').isNotEmpty;
    if (!has) {
      final v = await askText(context, 'Set a PIN (4 to 8 digits)', hint: 'PIN', number: true, obscure: true);
      if (v == null || v.isEmpty) return;
      if (v.length < 4 || v.length > 8 || int.tryParse(v) == null) {
        if (mounted) toast(context, 'Use 4 to 8 digits');
        return;
      }
      await _set('pin', v);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('App PIN'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'change'), child: const Text('Change PIN')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Remove PIN')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (!await askPin(context, title: 'Enter current PIN')) return;
    if (choice == 'remove') {
      await _set('pin', '');
      return;
    }
    if (!mounted) return;
    final v = await askText(context, 'New PIN (4 to 8 digits)', hint: 'PIN', number: true, obscure: true);
    if (v == null || v.isEmpty) return;
    if (v.length < 4 || v.length > 8 || int.tryParse(v) == null) {
      if (mounted) toast(context, 'Use 4 to 8 digits');
      return;
    }
    await _set('pin', v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700))),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 30), children: [
              sectionLabel('Calculation'),
              listRow(
                title: '1 munn equals',
                sub: 'Used to turn bags and kg into munn',
                trailing: amountText('${s['munn_kg']} kg'),
                onTap: () async {
                  final v = await askText(context, '1 munn equals (kg)', initial: s['munn_kg'] ?? '40', number: true, hint: 'kg');
                  if (v != null && numOf(v) > 0) await _set('munn_kg', fmtNum(numOf(v)));
                },
              ),
              listRow(
                title: 'Round each share to',
                sub: 'Keeps cash easy to hand out',
                trailing: amountText(s['round'] == '1' ? 'Rs 1' : 'Rs ${s['round']}'),
                onTap: _pickRound,
              ),
              listRow(
                title: 'Default tip sharing',
                sub: s['tip_default'] == 'selected' ? 'Only chosen labour' : 'Split equally among everyone',
                trailing: const Icon(Icons.swap_horiz),
                onTap: () => _set('tip_default', s['tip_default'] == 'selected' ? 'all' : 'selected'),
              ),
              Container(
                color: Colors.white,
                child: SwitchListTile(
                  title: const Text('Carry advance above earnings', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('If someone took more than he earned, the extra is taken off his next day'),
                  value: s['carry'] == '1',
                  onChanged: (v) => _set('carry', v ? '1' : '0'),
                ),
              ),
              sectionLabel('Slips and reports'),
              listRow(
                title: 'Mill name',
                sub: (s['mill_name'] ?? '').isEmpty ? 'Shown at the top of slips. Tap to set.' : s['mill_name'],
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () async {
                  final v = await askText(context, 'Mill name', initial: s['mill_name'] ?? '', hint: 'Name on slips');
                  if (v != null) await _set('mill_name', v);
                },
              ),
              sectionLabel('Security'),
              listRow(
                leading: const Icon(Icons.lock_outline),
                title: 'App PIN',
                sub: (s['pin'] ?? '').isEmpty ? 'Off' : 'On. Asked when the app opens.',
                trailing: const Icon(Icons.chevron_right),
                onTap: _pin,
              ),
              Container(
                color: Colors.white,
                child: SwitchListTile(
                  title: const Text('Ask PIN to change a closed day', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Reopen or delete a closed day (needs a PIN to be set)'),
                  value: s['lock_closed'] == '1',
                  onChanged: (v) => _set('lock_closed', v ? '1' : '0'),
                ),
              ),
              sectionLabel('Data'),
              listRow(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: 'Backup, export and import',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => go(context, const BackupScreen()),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Labour Pay 1.0', style: TextStyle(color: kInk2, fontSize: 12)),
              ),
            ]),
    );
  }
}
