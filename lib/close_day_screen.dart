import 'package:flutter/material.dart';

import 'slip_screen.dart';
import 'utils.dart';

class CloseDayScreen extends StatefulWidget {
  final int dayId;
  const CloseDayScreen({super.key, required this.dayId});
  @override
  State<CloseDayScreen> createState() => _CloseDayScreenState();
}

class _CloseDayScreenState extends State<CloseDayScreen> {
  bool markPaid = true;
  bool busy = false;

  Future<void> _close() async {
    setState(() => busy = true);
    try {
      await Db.closeDay(widget.dayId, markPaid: markPaid);
      if ((await Db.setting('auto_backup')) == '1') {
        try {
          await Db.backupNow();
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SlipScreen(dayId: widget.dayId)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, 'Could not close the day: $e');
      }
    }
  }

  Future<void> _reopen() async {
    if (!await askPinIfLocked(context)) return;
    await Db.reopenDay(widget.dayId);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kBg,
      child: AsyncData<DayCalc>(
      load: () => Db.calc(widget.dayId),
      builder: (context, c) => Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Close day', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('${fmtDay(c.day.date)} · pool ${rs(c.pool)}',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        ),
        body: Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(children: [
              Expanded(child: Text('Labour', style: _h)),
              SizedBox(width: 62, child: Text('Earned', textAlign: TextAlign.right, style: _h)),
              SizedBox(width: 60, child: Text('Advance', textAlign: TextAlign.right, style: _h)),
              SizedBox(width: 66, child: Text('To pay', textAlign: TextAlign.right, style: _h)),
            ]),
          ),
          const Divider(height: 1, color: kLine),
          Expanded(
            child: ListView(children: [
              if (c.crew.isEmpty) emptyState('Nobody on this day', 'Add labour before closing the day.'),
              for (final l in c.crew) _row(l),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(children: [
                  kv('Work ${rs(c.workTotal)} + tips ${rs(c.tipTotal)}', rs(c.pool)),
                  kv('Advances given', '-${rs(c.advTotal)}', color: kAdv),
                  const Divider(color: kInk),
                  kv('Total cash to pay', rs(c.totalPayable), bold: true, size: 17),
                ]),
              ),
              if (!c.locked)
                SwitchListTile(
                  title: const Text('Mark all as paid', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Turn off if some cash is still to be given'),
                  value: markPaid,
                  onChanged: (v) => setState(() => markPaid = v),
                ),
              if (!c.locked)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kJuteBg, borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                      'Closing locks the day. If a labour took more advance than he earned, the extra is carried to his next day (see Settings).',
                      style: TextStyle(color: kJuteDk, fontSize: 12.5)),
                ),
            ]),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: SafeArea(
              top: false,
              child: c.locked
                  ? Row(children: [
                      Expanded(child: OutlinedButton(onPressed: _reopen, child: const Text('Reopen day'))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => SlipScreen(dayId: widget.dayId))),
                          child: const Text('View slips'),
                        ),
                      ),
                    ])
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
                        onPressed: (busy || c.crew.isEmpty) ? null : _close,
                        child: Text(busy ? 'Closing...' : 'Close day and make ${c.crew.length} slips'),
                      ),
                    ),
            ),
          ),
        ]),
      ),
    ));
  }

  static const _h = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kInk2);

  Widget _row(LabourDay l) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: kLine))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.weight == 1 ? l.labour.name : '${l.labour.name} (half)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (l.prevBal > 0)
              Text('Owed earlier: ${money(l.prevBal)}', style: const TextStyle(fontSize: 11, color: kAdv)),
            if (l.newBal > 0)
              Text('Carries ${money(l.newBal)} forward', style: const TextStyle(fontSize: 11, color: kAdv)),
          ]),
        ),
        SizedBox(width: 62, child: Text(money(l.earned), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        SizedBox(
          width: 60,
          child: Text(l.advance > 0 ? '-${money(l.advance)}' : '0',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w600, color: l.advance > 0 ? kAdv : kInk2)),
        ),
        SizedBox(width: 66, child: Text(money(l.payable), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
      ]),
    );
  }
}
