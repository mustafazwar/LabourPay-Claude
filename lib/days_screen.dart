import 'package:flutter/material.dart';

import 'day_ledger_screen.dart';
import 'start_day_screen.dart';
import 'utils.dart';

class DaysScreen extends StatefulWidget {
  const DaysScreen({super.key});
  @override
  State<DaysScreen> createState() => _DaysScreenState();
}

class _DaysScreenState extends State<DaysScreen> {
  String filter = 'month';
  String? cFrom;
  String? cTo;

  (String, String) get _range {
    final n = DateTime.now();
    if (filter == 'month') return (ymd(DateTime(n.year, n.month, 1)), ymd(DateTime(n.year, n.month + 1, 0)));
    if (filter == 'last') return (ymd(DateTime(n.year, n.month - 1, 1)), ymd(DateTime(n.year, n.month, 0)));
    if (filter == 'custom' && cFrom != null && cTo != null) return (cFrom!, cTo!);
    return ('0000-01-01', '9999-12-31');
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (r == null) return;
    setState(() {
      filter = 'custom';
      cFrom = ymd(r.start);
      cTo = ymd(r.end);
    });
  }

  Future<void> _addPast() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Which day?',
    );
    if (d == null) return;
    final date = ymd(d);
    final ex = await Db.dayByDate(date);
    if (!mounted) return;
    if (ex != null) {
      toast(context, 'That day already has a ledger. Opening it.');
      go(context, DayLedgerScreen(dayId: ex.id, date: ex.date));
    } else {
      go(context, StartDayScreen(date: date));
    }
  }

  void _actions(DaySummary s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(fmtDay(s.date), style: const TextStyle(fontWeight: FontWeight.w800))),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open'),
            onTap: () {
              Navigator.pop(ctx);
              go(context, DayLedgerScreen(dayId: s.id, date: s.date));
            },
          ),
          if (s.status != 'open')
            ListTile(
              leading: const Icon(Icons.lock_open),
              title: const Text('Reopen day'),
              onTap: () async {
                Navigator.pop(ctx);
                if (!await askPinIfLocked(context)) return;
                await Db.reopenDay(s.id);
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: kAdv),
            title: const Text('Delete day', style: TextStyle(color: kAdv)),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await confirm(context, 'Delete ${fmtDay(s.date)}?', 'All its work, tips and advances will be deleted.');
              if (!ok) return;
              if (s.status != 'open' && !await askPinIfLocked(context)) return;
              await Db.deleteDay(s.id);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range;
    return Scaffold(
      appBar: AppBar(title: const Text('Days', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPast,
        icon: const Icon(Icons.add),
        label: const Text('Add past day'),
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              filterChip('This month', filter == 'month', () => setState(() => filter = 'month')),
              filterChip('Last month', filter == 'last', () => setState(() => filter = 'last')),
              filterChip('All', filter == 'all', () => setState(() => filter = 'all')),
              filterChip(filter == 'custom' && cFrom != null ? '${fmtDate(cFrom!)} - ${fmtDate(cTo!)}' : 'Custom range',
                  filter == 'custom', _pickRange),
            ]),
          ),
        ),
        const Divider(height: 1, color: kLine),
        Expanded(
          child: AsyncData<List<DaySummary>>(
            key: ValueKey('$from|$to'),
            load: () => Db.summaries(from: from, to: to),
            builder: (context, list) {
              if (list.isEmpty) return emptyState('No days here', 'Days you start will appear in this list.');
              final children = <Widget>[];
              String? month;
              for (final s in list) {
                final m = fmtMonthYear(s.date);
                if (m != month) {
                  month = m;
                  children.add(sectionLabel(m));
                }
                children.add(listRow(
                  title: fmtShort(s.date),
                  sub: '${s.crew} labour · work ${money(s.work)}${s.tips > 0 ? ' · tips ${money(s.tips)}' : ''}',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    amountText(money(s.pool)),
                    const SizedBox(width: 8),
                    StatusPill(s.status),
                  ]),
                  onTap: () => go(context, DayLedgerScreen(dayId: s.id, date: s.date)),
                  onLongPress: () => _actions(s),
                ));
              }
              children.add(const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 90),
                child: Text('Press and hold a day to reopen or delete it.', style: TextStyle(color: kInk2, fontSize: 12.5)),
              ));
              return ListView(children: children);
            },
          ),
        ),
      ]),
    );
  }
}
