import 'package:flutter/material.dart';

import 'labour_list_screen.dart';
import 'slip_screen.dart';
import 'utils.dart';

class _LedgerData {
  final Labour labour;
  final List<LedgerRow> days;
  final List<AdvanceRow> advances;
  _LedgerData(this.labour, this.days, this.advances);
}

class LabourLedgerScreen extends StatefulWidget {
  final int labourId;
  const LabourLedgerScreen({super.key, required this.labourId});
  @override
  State<LabourLedgerScreen> createState() => _LabourLedgerScreenState();
}

class _LabourLedgerScreenState extends State<LabourLedgerScreen> {
  String preset = 'month';
  late String from;
  late String to;

  @override
  void initState() {
    super.initState();
    _applyPreset('month');
  }

  void _applyPreset(String p) {
    final n = DateTime.now();
    preset = p;
    to = ymd(n);
    if (p == 'month') {
      from = ymd(DateTime(n.year, n.month, 1));
    } else if (p == 'week') {
      from = ymd(n.subtract(Duration(days: n.weekday - 1)));
    } else if (p == 'all') {
      from = '2000-01-01';
    }
  }

  Future<void> _custom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: parseYmd(from == '2000-01-01' ? ymd(DateTime.now()) : from), end: parseYmd(to)),
    );
    if (r == null) return;
    setState(() {
      preset = 'custom';
      from = ymd(r.start);
      to = ymd(r.end);
    });
  }

  Future<_LedgerData> _load() async {
    final l = await Db.labourById(widget.labourId);
    if (l == null) throw Exception('Labour not found');
    final days = await Db.ledger(widget.labourId, from, to);
    final adv = await Db.advancesFor(widget.labourId, from, to);
    return _LedgerData(l, days, adv);
  }

  Future<void> _export(String name) async {
    final rows = await Db.csvRows(from: from, to: to, labourId: widget.labourId);
    await shareTextFile('ledger_${name.replaceAll(' ', '_')}_${from}_$to.csv', toCsv(rows));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kBg,
      child: AsyncData<_LedgerData>(
      key: ValueKey('$from|$to'),
      load: _load,
      builder: (context, d) {
        double earned = 0, adv = 0, net = 0;
        for (final r in d.days) {
          earned += r.ld.earned;
          adv += r.ld.advance;
          net += r.ld.payable;
        }
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.labour.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Text('Labour ledger', style: TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => showLabourDialog(context, labour: d.labour),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'delete') {
                      final ok = await confirm(context, 'Delete ${d.labour.name}?',
                          'Only possible if he has never worked. Otherwise mark him inactive.');
                      if (!ok) return;
                      final done = await Db.deleteLabour(d.labour.id);
                      if (!context.mounted) return;
                      if (done) {
                        Navigator.pop(context);
                      } else {
                        toast(context, 'He has work history, so he cannot be deleted. Use Edit and turn off Active.');
                      }
                    }
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete labour'))],
                ),
              ],
            ),
            body: Column(children: [
              Container(
                color: Colors.white,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    filterChip('This month', preset == 'month', () => setState(() => _applyPreset('month'))),
                    filterChip('This week', preset == 'week', () => setState(() => _applyPreset('week'))),
                    filterChip('All time', preset == 'all', () => setState(() => _applyPreset('all'))),
                    filterChip(preset == 'custom' ? '${fmtDate(from)} - ${fmtDate(to)}' : 'Custom', preset == 'custom', _custom),
                  ]),
                ),
              ),
              Container(
                color: Colors.white,
                child: Row(children: [
                  _stat('Days worked', '${d.days.length}'),
                  _stat('Earned', money(earned), color: kEarn),
                  _stat('Advances', money(adv), color: kAdv),
                  _stat('Net paid', money(net)),
                ]),
              ),
              if (d.labour.balance > 0)
                Container(
                  width: double.infinity,
                  color: kAdvBg,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Owes the mill ${rs(d.labour.balance)} (taken off his next day)',
                      style: const TextStyle(color: kAdv, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              Container(
                color: Colors.white,
                child: const TabBar(
                  labelColor: kInk,
                  unselectedLabelColor: kInk2,
                  indicatorColor: kJute,
                  tabs: [Tab(text: 'Days'), Tab(text: 'Advances')],
                ),
              ),
              Expanded(
                child: TabBarView(children: [
                  d.days.isEmpty
                      ? emptyState('No days in this range', 'Try a longer date range.')
                      : ListView(children: [
                          for (final r in d.days)
                            listRow(
                              title: fmtShort(r.day.date),
                              sub: '${money(r.ld.earned)} earned - ${money(r.ld.advance)} advance',
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                amountText(money(r.ld.payable)),
                                const SizedBox(width: 6),
                                const Icon(Icons.receipt_long_outlined, size: 20, color: kInk2),
                              ]),
                              onTap: () => go(context, SlipScreen(dayId: r.day.id, initialLabourId: d.labour.id)),
                            ),
                        ]),
                  d.advances.isEmpty
                      ? emptyState('No advances', 'Nothing was taken in this range.')
                      : ListView(children: [
                          for (final a in d.advances)
                            listRow(
                              title: a.note.isEmpty ? 'Advance' : a.note,
                              sub: fmtDay(a.date),
                              trailing: amountText('-${money(a.amount)}', color: kAdv),
                            ),
                        ]),
                ]),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.download_outlined),
                      label: Text("Export ${d.labour.name}'s ledger (CSV)"),
                      onPressed: () => _export(d.labour.name),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    ));
  }

  Widget _stat(String l, String v, {Color? color}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: const TextStyle(fontSize: 11, color: kInk2)),
            const SizedBox(height: 2),
            Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color ?? kInk)),
          ]),
        ),
      );
}
