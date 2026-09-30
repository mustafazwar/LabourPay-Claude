import 'package:flutter/material.dart';

import 'labour_ledger_screen.dart';
import 'utils.dart';

/// Add or edit a labour. Returns true when something was saved.
Future<bool> showLabourDialog(BuildContext context, {Labour? labour}) async {
  final nameC = TextEditingController(text: labour?.name ?? '');
  final phoneC = TextEditingController(text: labour?.phone ?? '');
  bool active = labour?.active ?? true;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(labour == null ? 'Add labour' : 'Edit labour'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, autofocus: true, decoration: dec('Name')),
          const SizedBox(height: 10),
          TextField(controller: phoneC, keyboardType: TextInputType.phone, decoration: dec('Phone (optional)')),
          if (labour != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive labour are hidden when starting a day'),
              value: active,
              onChanged: (v) => setD(() => active = v),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameC.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return false;
  if (labour == null) {
    await Db.addLabour(nameC.text, phone: phoneC.text);
  } else {
    await Db.updateLabour(labour.id, name: nameC.text, phone: phoneC.text, active: active);
  }
  return true;
}

class LabourListScreen extends StatefulWidget {
  const LabourListScreen({super.key});
  @override
  State<LabourListScreen> createState() => _LabourListScreenState();
}

class _LabourListScreenState extends State<LabourListScreen> {
  String filter = 'active';
  String q = '';
  bool searching = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                    hintText: 'Search name', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none),
                onChanged: (v) => setState(() => q = v),
              )
            : const Text('Labour', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: Icon(searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              searching = !searching;
              q = '';
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showLabourDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add labour'),
      ),
      body: AsyncData<List<Labour>>(
        load: () => Db.labours(),
        builder: (context, all) {
          final active = all.where((l) => l.active).length;
          final inactive = all.length - active;
          final owes = all.where((l) => l.balance > 0).length;
          final shown = all.where((l) {
            if (q.isNotEmpty && !l.name.toLowerCase().contains(q.toLowerCase())) return false;
            if (filter == 'active') return l.active;
            if (filter == 'inactive') return !l.active;
            return l.balance > 0;
          }).toList();
          return Column(children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  filterChip('Active $active', filter == 'active', () => setState(() => filter = 'active')),
                  filterChip('Inactive $inactive', filter == 'inactive', () => setState(() => filter = 'inactive')),
                  filterChip('Owes money $owes', filter == 'owes', () => setState(() => filter = 'owes')),
                ]),
              ),
            ),
            const Divider(height: 1, color: kLine),
            Expanded(
              child: shown.isEmpty
                  ? emptyState('No labour here', 'Tap Add labour to create a name.')
                  : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                      for (final l in shown)
                        listRow(
                          leading: Avatar(l.name),
                          title: l.name,
                          sub: l.last == null ? 'Not worked yet' : 'Last worked ${fmtShort(l.last!)}',
                          trailing: l.balance > 0
                              ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text('Owes ${rs(l.balance)}',
                                      style: const TextStyle(color: kAdv, fontWeight: FontWeight.w800, fontSize: 13)),
                                  const Text('carried forward', style: TextStyle(fontSize: 11, color: kInk2)),
                                ])
                              : const Pill('Clear', bg: kEarnBg, fg: kEarn),
                          onTap: () => go(context, LabourLedgerScreen(labourId: l.id)),
                          onLongPress: () => showLabourDialog(context, labour: l),
                        ),
                    ]),
            ),
          ]);
        },
      ),
    );
  }
}
