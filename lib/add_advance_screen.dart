import 'package:flutter/material.dart';

import 'utils.dart';

class AddAdvanceScreen extends StatefulWidget {
  final int dayId;
  final AdvanceRow? entry;
  const AddAdvanceScreen({super.key, required this.dayId, this.entry});
  @override
  State<AddAdvanceScreen> createState() => _AddAdvanceScreenState();
}

class _AddAdvanceScreenState extends State<AddAdvanceScreen> {
  List<Labour> crew = [];
  int? selected;
  bool everyone = false;
  String amount = '';
  final noteC = TextEditingController();
  bool ready = false;

  static const quick = <String, int>{'Tea': 50, 'Cigarettes': 200, 'Lunch': 150};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    noteC.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    crew = await Db.crewLabours(widget.dayId);
    final e = widget.entry;
    if (e != null) {
      selected = e.labourId;
      amount = fmtNum(e.amount);
      noteC.text = e.note;
    }
    if (!mounted) return;
    setState(() => ready = true);
  }

  void _key(String k) {
    setState(() {
      if (k == '<') {
        if (amount.isNotEmpty) amount = amount.substring(0, amount.length - 1);
      } else if (amount.length < 7) {
        if (amount.isEmpty && (k == '0' || k == '00')) return;
        amount += k;
      }
    });
  }

  Future<void> _save() async {
    final amt = numOf(amount);
    if (amt <= 0) {
      toast(context, 'Enter an amount');
      return;
    }
    final note = noteC.text.trim();
    if (widget.entry != null) {
      if (selected == null) return;
      await Db.saveAdvance(
          AdvanceRow(id: widget.entry!.id, dayId: widget.dayId, labourId: selected!, amount: amt, note: note));
    } else if (everyone) {
      for (final l in crew) {
        await Db.saveAdvance(AdvanceRow(dayId: widget.dayId, labourId: l.id, amount: amt, note: note));
      }
    } else {
      if (selected == null) {
        toast(context, 'Choose who took the cash');
        return;
      }
      await Db.saveAdvance(AdvanceRow(dayId: widget.dayId, labourId: selected!, amount: amt, note: note));
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.entry != null;
    final amt = numOf(amount);
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit advance' : 'Add advance', style: const TextStyle(fontWeight: FontWeight.w700))),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: ListView(children: [
                  sectionLabel('Who took it'),
                  SizedBox(
                    height: 76,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final l in crew)
                          GestureDetector(
                            onTap: editing
                                ? null
                                : () => setState(() {
                                      selected = l.id;
                                      everyone = false;
                                    }),
                            child: Container(
                              width: 68,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(children: [
                                Avatar(l.name, dark: selected == l.id && !everyone),
                                const SizedBox(height: 4),
                                Text(l.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: selected == l.id ? FontWeight.w800 : FontWeight.w500)),
                              ]),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!editing)
                    SwitchListTile(
                      title: const Text('Give the same to everyone present', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('${crew.length} × ${rs(amt)}'),
                      value: everyone,
                      onChanged: (v) => setState(() => everyone = v),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Wrap(children: [
                      for (final e in quick.entries)
                        filterChip('${e.key} · ${e.value}', noteC.text == e.key && amt == e.value, () {
                          setState(() {
                            noteC.text = e.key;
                            amount = '${e.value}';
                          });
                        }),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFC9D0DB), width: 1.5),
                      ),
                      child: Row(children: [
                        Text(amount.isEmpty ? 'Rs 0' : 'Rs ${fmtQty(amt)}',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: amount.isEmpty ? kInk2 : kInk)),
                        const Spacer(),
                        IconButton(onPressed: () => setState(() => amount = ''), icon: const Icon(Icons.close)),
                      ]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: TextField(
                      controller: noteC,
                      decoration: dec('Note (tea, cigarettes...)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _pad(),
                ]),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
                      onPressed: _save,
                      child: const Text('Save advance'),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }

  Widget _pad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['00', '0', '<'],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              for (final k in r)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _key(k),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          alignment: Alignment.center,
                          child: k == '<'
                              ? const Icon(Icons.backspace_outlined)
                              : Text(k, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}
