import 'package:flutter/material.dart';

import 'add_advance_screen.dart';
import 'add_tip_screen.dart';
import 'add_work_screen.dart';
import 'close_day_screen.dart';
import 'slip_screen.dart';
import 'start_day_screen.dart';
import 'utils.dart';

class DayLedgerScreen extends StatefulWidget {
  final int dayId;
  final String date;
  const DayLedgerScreen({super.key, required this.dayId, required this.date});
  @override
  State<DayLedgerScreen> createState() => _DayLedgerScreenState();
}

class _DayLedgerScreenState extends State<DayLedgerScreen> with SingleTickerProviderStateMixin {
  late final TabController tc;

  @override
  void initState() {
    super.initState();
    tc = TabController(length: 4, vsync: this);
    tc.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  Future<void> _reopen() async {
    final day = await Db.dayById(widget.dayId);
    if (day == null || day.status == 'open') return;
    if (!mounted) return;
    if (!await askPinIfLocked(context)) return;
    await Db.reopenDay(widget.dayId);
  }

  Future<void> _menu(String v) async {
    final day = await Db.dayById(widget.dayId);
    if (day == null || !mounted) return;
    switch (v) {
      case 'close':
        if (day.status != 'open') {
          toast(context, 'This day is already closed');
          return;
        }
        await go(context, CloseDayScreen(dayId: widget.dayId));
        break;
      case 'slips':
        await go(context, SlipScreen(dayId: widget.dayId));
        break;
      case 'reopen':
        await _reopen();
        break;
      case 'paid':
        if (day.status == 'open') {
          toast(context, 'Close the day first');
        } else {
          await Db.setPaid(widget.dayId, day.status != 'paid');
        }
        break;
      case 'delete':
        final ok = await confirm(context, 'Delete this day?',
            'All work, tips and advances of ${fmtDay(widget.date)} will be deleted. This cannot be undone.');
        if (!ok || !mounted) return;
        if (day.status != 'open' && !await askPinIfLocked(context)) return;
        if (!mounted) return;
        final nav = Navigator.of(context);
        nav.pop();
        await Db.deleteDay(widget.dayId);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fmtDay(widget.date), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'close', child: Text('Close day')),
              PopupMenuItem(value: 'slips', child: Text('View slips')),
              PopupMenuItem(value: 'paid', child: Text('Mark paid / unpaid')),
              PopupMenuItem(value: 'reopen', child: Text('Reopen day')),
              PopupMenuItem(value: 'delete', child: Text('Delete day')),
            ],
          ),
        ],
        bottom: darkTabBar(tc, const ['Work', 'Tips', 'Advances', 'Labour']),
      ),
      body: AsyncData<DayCalc>(
        load: () => Db.calc(widget.dayId),
        builder: (context, c) => Stack(children: [
          Column(children: [
            _summary(c),
            Expanded(
              child: TabBarView(
                controller: tc,
                children: [_workTab(c), _tipTab(c), _advTab(c), _labourTab(c)],
              ),
            ),
            _bottomBar(c),
          ]),
          if (!c.locked)
            Positioned(
              right: 16,
              bottom: 84,
              child: FloatingActionButton.extended(
                onPressed: () => _add(c),
                icon: const Icon(Icons.add),
                label: Text(['Add work', 'Add tip', 'Add advance', 'Edit crew'][tc.index]),
              ),
            ),
        ]),
      ),
    );
  }

  void _add(DayCalc c) {
    switch (tc.index) {
      case 0:
        go(context, AddWorkScreen(dayId: c.day.id, date: c.day.date));
        break;
      case 1:
        go(context, AddTipScreen(dayId: c.day.id));
        break;
      case 2:
        if (c.crew.isEmpty) {
          toast(context, 'Add labour to this day first');
        } else {
          go(context, AddAdvanceScreen(dayId: c.day.id));
        }
        break;
      default:
        go(context, StartDayScreen(date: c.day.date, dayId: c.day.id));
    }
  }

  Widget _summary(DayCalc c) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Pool', style: TextStyle(fontSize: 12, color: kInk2)),
              amountText(rs(c.pool), size: 20),
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Each labour (${c.crew.length})', style: const TextStyle(fontSize: 12, color: kInk2)),
              amountText(rs(c.perHead), size: 20, color: kEarn),
            ]),
          ),
          StatusPill(c.day.status),
        ]),
      );

  Widget _bottomBar(DayCalc c) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: SafeArea(
          top: false,
          child: c.locked
              ? Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _reopen, child: const Text('Reopen'))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => go(context, SlipScreen(dayId: c.day.id)),
                      child: const Text('View slips'),
                    ),
                  ),
                ])
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
                    onPressed: () => go(context, CloseDayScreen(dayId: c.day.id)),
                    child: const Text('Close day'),
                  ),
                ),
        ),
      );

  Widget _lockedNote(DayCalc c) => c.locked
      ? Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kJuteBg, borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.lock_outline, size: 18, color: kJuteDk),
            SizedBox(width: 8),
            Expanded(child: Text('This day is closed. Reopen it to make changes.', style: TextStyle(color: kJuteDk, fontSize: 12.5))),
          ]),
        )
      : const SizedBox.shrink();

  IconData _typeIcon(String t) => t == 'milling' ? Icons.grain : (t == 'unload' ? Icons.south : Icons.north);

  Widget _workTab(DayCalc c) {
    return ListView(padding: const EdgeInsets.only(bottom: 150), children: [
      _lockedNote(c),
      if (c.work.isEmpty) emptyState('No work added yet', 'Tap Add work to record milling, unloading or loading.'),
      for (final w in c.work)
        listRow(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: w.type == 'milling' ? kAdvBg : kEarnBg,
            child: Icon(_typeIcon(w.type), size: 17, color: w.type == 'milling' ? kAdv : kEarn),
          ),
          title: '${workLabel(w.type)} · ${w.material}',
          sub:
              '${fmtQty(w.bags)} bags × ${fmtQty(w.kgPerBag)} kg = ${fmtQty(w.munn)} munn × ${money(w.rate)}${w.party.isEmpty ? '' : '\n${w.party}'}',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            amountText(money(w.amount)),
            if (!c.locked)
              editDeleteButtons(
                onEdit: () => go(context, AddWorkScreen(dayId: c.day.id, date: c.day.date, entry: w)),
                onDelete: () async {
                  if (await confirm(context, 'Delete this entry?', '${workLabel(w.type)} · ${w.material}')) {
                    await Db.deleteWork(w.id!);
                  }
                },
              ),
          ]),
        ),
      if (c.work.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: kv('Work total', rs(c.workTotal), bold: true, size: 16),
        ),
    ]);
  }

  Widget _tipTab(DayCalc c) {
    final names = {for (final l in c.crew) l.labour.id: l.labour.name};
    return ListView(padding: const EdgeInsets.only(bottom: 150), children: [
      _lockedNote(c),
      if (c.tips.isEmpty) emptyState('No tips today', 'Tips given by truck drivers can be added here.'),
      for (final t in c.tips)
        listRow(
          leading: const CircleAvatar(radius: 16, backgroundColor: kJuteBg, child: Icon(Icons.add_circle_outline, size: 18, color: kJuteDk)),
          title: 'Tip · ${t.from.isEmpty ? 'Driver' : t.from}',
          sub: t.labourIds.isEmpty
              ? 'Split equally among everyone'
              : 'Only: ${t.labourIds.map((i) => names[i] ?? '?').join(', ')}',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            amountText(money(t.amount)),
            if (!c.locked)
              editDeleteButtons(
                onEdit: () => go(context, AddTipScreen(dayId: c.day.id, entry: t)),
                onDelete: () async {
                  if (await confirm(context, 'Delete this tip?', rs(t.amount))) await Db.deleteTip(t.id!);
                },
              ),
          ]),
        ),
      if (c.tips.isNotEmpty)
        Padding(padding: const EdgeInsets.all(16), child: kv('Tips total', rs(c.tipTotal), bold: true, size: 16)),
    ]);
  }

  Widget _advTab(DayCalc c) {
    return ListView(padding: const EdgeInsets.only(bottom: 150), children: [
      _lockedNote(c),
      if (c.advances.isEmpty) emptyState('No advances', 'Cash for tea, cigarettes and so on is added here.'),
      for (final a in c.advances)
        listRow(
          leading: Avatar(a.labourName, size: 32),
          title: a.labourName,
          sub: a.note.isEmpty ? 'Advance' : a.note,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            amountText('-${money(a.amount)}', color: kAdv),
            if (!c.locked)
              editDeleteButtons(
                onEdit: () => go(context, AddAdvanceScreen(dayId: c.day.id, entry: a)),
                onDelete: () async {
                  if (await confirm(context, 'Delete this advance?', '${a.labourName} · ${rs(a.amount)}')) {
                    await Db.deleteAdvance(a.id!);
                  }
                },
              ),
          ]),
        ),
      if (c.advances.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: kv('Advances total', rs(c.advTotal), bold: true, size: 16, color: kAdv),
        ),
    ]);
  }

  Widget _labourTab(DayCalc c) {
    return ListView(padding: const EdgeInsets.only(bottom: 150), children: [
      _lockedNote(c),
      if (c.crew.isEmpty) emptyState('Nobody on this day', 'Use Edit crew to choose who worked.'),
      for (final l in c.crew)
        listRow(
          leading: Avatar(l.labour.name),
          title: l.weight == 1 ? l.labour.name : '${l.labour.name} (half day)',
          sub: 'Earned ${money(l.earned)} · Advance ${money(l.advance)}${l.prevBal > 0 ? ' · Owed ${money(l.prevBal)}' : ''}',
          trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            amountText(money(l.payable), color: kEarn),
            const Text('to pay', style: TextStyle(fontSize: 11, color: kInk2)),
          ]),
          onTap: () => go(context, SlipScreen(dayId: c.day.id, initialLabourId: l.labour.id)),
        ),
    ]);
  }
}
