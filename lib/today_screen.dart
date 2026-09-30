import 'package:flutter/material.dart';

import 'add_advance_screen.dart';
import 'add_tip_screen.dart';
import 'add_work_screen.dart';
import 'close_day_screen.dart';
import 'day_ledger_screen.dart';
import 'settings_screen.dart';
import 'slip_screen.dart';
import 'start_day_screen.dart';
import 'utils.dart';

class _TodayData {
  final String today;
  final DayCalc? calc;
  final List<DaySummary> recent;
  final List<DayRow> stale;
  _TodayData(this.today, this.calc, this.recent, this.stale);
}

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  Future<_TodayData> _load() async {
    final today = ymd(DateTime.now());
    final day = await Db.dayByDate(today);
    DayCalc? c;
    if (day != null) c = await Db.calc(day.id);
    final all = await Db.summaries(limit: 6);
    final recent = all.where((s) => s.date != today).take(5).toList();
    final stale = await Db.openDaysBefore(today);
    return _TodayData(today, c, recent, stale);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Labour Pay', style: TextStyle(fontWeight: FontWeight.w800)),
          Text(fmtLong(DateTime.now()), style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Settings',
            onPressed: () => go(context, const SettingsScreen()),
          ),
        ],
      ),
      body: AsyncData<_TodayData>(
        load: _load,
        builder: (context, d) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _hero(context, d),
            if (d.stale.isNotEmpty) _staleBanner(context, d.stale.first),
            _quick(context, d),
            if (d.recent.isNotEmpty) sectionLabel('Recent days'),
            for (final s in d.recent)
              listRow(
                title: fmtShort(s.date),
                sub: '${s.crew} labour',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  amountText(rs(s.pool)),
                  const SizedBox(width: 8),
                  StatusPill(s.status),
                ]),
                onTap: () => go(context, DayLedgerScreen(dayId: s.id, date: s.date)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, _TodayData d) {
    final c = d.calc;
    return Container(
      color: kInk,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      width: double.infinity,
      child: c == null
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('No ledger for today yet',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Start the day by choosing who came to work.', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kJute),
                icon: const Icon(Icons.play_arrow),
                label: const Text("Start today's ledger"),
                onPressed: () => go(context, StartDayScreen(date: d.today)),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(c.locked ? 'Day closed' : "Today's pool",
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(width: 8),
                StatusPill(c.day.status),
              ]),
              const SizedBox(height: 6),
              Text(rs(c.pool),
                  style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800)),
              Text('${c.crew.length} labour · ${rs(c.perHead)} each',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(color: const Color(0x17FFFFFF), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  _trio('Work', money(c.workTotal)),
                  _trio('Tips', money(c.tipTotal)),
                  _trio('Advances', money(c.advTotal)),
                ]),
              ),
            ]),
    );
  }

  Widget _trio(String l, String v) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(v, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _staleBanner(BuildContext context, DayRow day) => InkWell(
        onTap: () => go(context, DayLedgerScreen(dayId: day.id, date: day.date)),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kJuteBg, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: kJuteDk),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${fmtShort(day.date)} is still open. Tap to finish and close it.',
                  style: const TextStyle(color: kJuteDk, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );

  Widget _quick(BuildContext context, _TodayData d) {
    void need(void Function(DayCalc c) fn) {
      final c = d.calc;
      if (c == null) {
        go(context, StartDayScreen(date: d.today));
        return;
      }
      if (c.locked) {
        toast(context, 'Today is closed. Reopen it from the day ledger to make changes.');
        return;
      }
      fn(c);
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: _tile(Icons.inventory_2_outlined, 'Add work',
                () => need((c) => go(context, AddWorkScreen(dayId: c.day.id, date: c.day.date)))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _tile(Icons.payments_outlined, 'Add advance',
                () => need((c) => go(context, AddAdvanceScreen(dayId: c.day.id)))),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _tile(Icons.add_circle_outline, 'Add driver tip',
                () => need((c) => go(context, AddTipScreen(dayId: c.day.id)))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _tile(Icons.check_circle_outline, d.calc != null && d.calc!.locked ? 'View slips' : 'Close day', () {
              final c = d.calc;
              if (c == null) {
                go(context, StartDayScreen(date: d.today));
              } else if (c.locked) {
                go(context, SlipScreen(dayId: c.day.id));
              } else {
                go(context, CloseDayScreen(dayId: c.day.id));
              }
            }, dark: true),
          ),
        ]),
        if (d.calc != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton(
              onPressed: () => go(context, DayLedgerScreen(dayId: d.calc!.day.id, date: d.calc!.day.date)),
              child: const Text("Open today's full ledger"),
            ),
          ),
      ]),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap, {bool dark = false}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dark ? kInk : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: dark ? kInk : kLine),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: dark ? const Color(0x24FFFFFF) : kJuteBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: dark ? Colors.white : kJuteDk, size: 20),
            ),
            const SizedBox(height: 10),
            Text(label,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: dark ? Colors.white : kInk)),
          ]),
        ),
      );
}
