import 'package:flutter/material.dart';

import 'utils.dart';

class RatesScreen extends StatelessWidget {
  const RatesScreen({super.key});

  Future<void> _addMaterial(BuildContext context) async {
    final nameC = TextEditingController();
    final mC = TextEditingController();
    final uC = TextEditingController(text: '5');
    final lC = TextEditingController(text: '5');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add material'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameC, autofocus: true, decoration: dec('Material name')),
            const SizedBox(height: 10),
            TextField(
                controller: mC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: dec('Milling rate per munn', prefix: 'Rs ')),
            const SizedBox(height: 10),
            TextField(
                controller: uC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: dec('Unload rate per munn', prefix: 'Rs ')),
            const SizedBox(height: 10),
            TextField(
                controller: lC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: dec('Load rate per munn', prefix: 'Rs ')),
          ]),
        ),
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
    );
    if (ok != true) return;
    await Db.addMaterial(nameC.text, rates: {
      'milling': numOf(mC.text),
      'unload': numOf(uC.text),
      'load': numOf(lC.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rates', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Rupees per munn (40 kg)', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
          bottom: darkTabBar(null, const ['Milling', 'Unload', 'Load']),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _addMaterial(context),
          icon: const Icon(Icons.add),
          label: const Text('Add material'),
        ),
        body: const TabBarView(children: [
          _RateList(type: 'milling'),
          _RateList(type: 'unload'),
          _RateList(type: 'load'),
        ]),
      ),
    );
  }
}

class _RateList extends StatelessWidget {
  final String type;
  const _RateList({required this.type});

  @override
  Widget build(BuildContext context) {
    return AsyncData<List<MaterialRate>>(
      load: () => Db.rateTable(type),
      builder: (context, list) => ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        if (list.isEmpty) emptyState('No materials yet', 'Tap Add material to create one.'),
        for (final m in list)
          listRow(
            title: m.name,
            sub: m.rate == null ? 'No rate set. Tap to set one.' : (m.since == '2000-01-01' ? 'Original rate' : 'Since ${fmtDate(m.since!)}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              amountText(m.rate == null ? '-' : 'Rs ${fmtNum(m.rate!)}', size: 17),
              const SizedBox(width: 8),
              const Icon(Icons.edit_outlined, size: 19, color: kInk2),
            ]),
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              builder: (ctx) => Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: _RateSheet(material: m, type: type),
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kJuteBg, borderRadius: BorderRadius.circular(10)),
          child: const Text(
              'Changing a rate affects new entries only. Old days keep the rate they were saved with.',
              style: TextStyle(color: kJuteDk, fontSize: 12.5)),
        ),
      ]),
    );
  }
}

class _RateSheet extends StatefulWidget {
  final MaterialRate material;
  final String type;
  const _RateSheet({required this.material, required this.type});
  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  late final TextEditingController rateC;
  String from = ymd(DateTime.now());
  bool applyToday = false;
  DayRow? openToday;
  List<Map<String, Object?>> history = [];

  @override
  void initState() {
    super.initState();
    rateC = TextEditingController(text: widget.material.rate == null ? '' : fmtNum(widget.material.rate!));
    _load();
  }

  @override
  void dispose() {
    rateC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final day = await Db.dayByDate(ymd(DateTime.now()));
    history = await Db.rateHistory(widget.material.id, widget.type);
    if (!mounted) return;
    setState(() => openToday = (day != null && day.status == 'open') ? day : null);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: parseYmd(from),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => from = ymd(d));
  }

  Future<void> _save() async {
    final r = numOf(rateC.text);
    if (r <= 0) {
      toast(context, 'Enter a rate');
      return;
    }
    await Db.setRate(widget.material.id, widget.type, r, from);
    if (applyToday && openToday != null) {
      await Db.applyRateToDay(openToday!.id, widget.material.name, widget.type, r);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.material.rate;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${widget.material.name} · ${workLabel(widget.type)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(cur == null ? 'No rate set yet' : 'Current rate Rs ${fmtNum(cur)} per munn',
            style: const TextStyle(color: kInk2)),
        const SizedBox(height: 14),
        TextField(
          controller: rateC,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          decoration: dec('New rate per munn', prefix: 'Rs '),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: _pickDate,
          child: InputDecorator(
            decoration: dec('Effective from'),
            child: Row(children: [
              Expanded(child: Text(from == ymd(DateTime.now()) ? 'Today, ${fmtDate(from)}' : fmtDate(from))),
              const Icon(Icons.calendar_today_outlined, size: 18),
            ]),
          ),
        ),
        if (openToday != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Also update today's open entries", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text('Recalculates today\'s entries for this material'),
            value: applyToday,
            onChanged: (v) => setState(() => applyToday = v),
          ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('History', style: TextStyle(fontWeight: FontWeight.w700, color: kInk2, fontSize: 13)),
          for (final h in history)
            kv(fmtDate('${h['effective_from']}') == '1 Jan 2000' ? 'Original' : fmtDate('${h['effective_from']}'),
                'Rs ${fmtNum(dd(h['per_munn']))}'),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: _save, child: const Text('Save rate'))),
        ]),
      ]),
    );
  }
}
