import 'package:flutter/material.dart';

import 'utils.dart';

class AddTipScreen extends StatefulWidget {
  final int dayId;
  final TipRow? entry;
  const AddTipScreen({super.key, required this.dayId, this.entry});
  @override
  State<AddTipScreen> createState() => _AddTipScreenState();
}

class _AddTipScreenState extends State<AddTipScreen> {
  List<Labour> crew = [];
  final amountC = TextEditingController();
  final fromC = TextEditingController();
  bool everyone = true;
  final Set<int> chosen = {};
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    amountC.dispose();
    fromC.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    crew = await Db.crewLabours(widget.dayId);
    final e = widget.entry;
    if (e != null) {
      amountC.text = fmtNum(e.amount);
      fromC.text = e.from;
      everyone = e.labourIds.isEmpty;
      chosen.addAll(e.labourIds);
    } else {
      everyone = (await Db.setting('tip_default')) != 'selected';
    }
    if (!mounted) return;
    setState(() => ready = true);
  }

  double get amount => numOf(amountC.text);

  Future<void> _save() async {
    if (amount <= 0) {
      toast(context, 'Enter the tip amount');
      return;
    }
    if (!everyone && chosen.isEmpty) {
      toast(context, 'Choose who gets the tip');
      return;
    }
    await Db.saveTip(TipRow(
      id: widget.entry?.id,
      dayId: widget.dayId,
      amount: amount,
      from: fromC.text.trim(),
      labourIds: everyone ? <int>[] : chosen.toList(),
    ));
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = everyone ? crew.length : chosen.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry == null ? 'Add driver tip' : 'Edit tip', style: const TextStyle(fontWeight: FontWeight.w700))),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                controller: amountC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                decoration: dec('Amount', prefix: 'Rs '),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(children: [
                for (final v in [500, 1000, 2000, 3000])
                  filterChip(money(v.toDouble()), amount == v, () {
                    setState(() => amountC.text = '$v');
                  }),
              ]),
              const SizedBox(height: 10),
              TextField(controller: fromC, decoration: dec('Given by (driver or truck)')),
              sectionLabel('Who gets it'),
              _option(
                title: 'Split equally among everyone present',
                sub: n > 0 && amount > 0 ? '${rs(amount / n)} each' : 'Everyone on the day',
                on: everyone,
                onTap: () => setState(() => everyone = true),
              ),
              _option(
                title: 'Only chosen labour',
                sub: 'Choose one or more names',
                on: !everyone,
                onTap: () => setState(() => everyone = false),
              ),
              if (!everyone)
                Container(
                  color: Colors.white,
                  child: Column(children: [
                    for (final l in crew)
                      CheckboxListTile(
                        value: chosen.contains(l.id),
                        activeColor: kInk,
                        title: Text(l.name),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            chosen.add(l.id);
                          } else {
                            chosen.remove(l.id);
                          }
                        }),
                      ),
                  ]),
                ),
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: kJuteBg, borderRadius: BorderRadius.circular(10)),
                child: const Text('Tips are kept apart from work rates, so slips show them on their own line.',
                    style: TextStyle(color: kJuteDk, fontSize: 12.5)),
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
                onPressed: _save,
                child: const Text('Save tip'),
              ),
            ]),
    );
  }

  Widget _option({required String title, required String sub, required bool on, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: kLine))),
        child: Row(children: [
          Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: on ? kInk : kInk2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text(sub, style: const TextStyle(fontSize: 12, color: kInk2)),
            ]),
          ),
        ]),
      ),
    );
  }
}
