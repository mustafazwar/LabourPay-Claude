import 'package:flutter/material.dart';

import 'day_ledger_screen.dart';
import 'utils.dart';

/// Pick who worked. Used to start a new day, or to edit the crew of an existing day (dayId set).
class StartDayScreen extends StatefulWidget {
  final String date;
  final int? dayId;
  const StartDayScreen({super.key, required this.date, this.dayId});
  @override
  State<StartDayScreen> createState() => _StartDayScreenState();
}

class _StartDayScreenState extends State<StartDayScreen> {
  List<Labour> all = [];
  final Map<int, double> crew = {};
  Map<int, double> original = {};
  String q = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    all = await Db.labours();
    if (widget.dayId != null) {
      original = await Db.crewOf(widget.dayId!);
      crew
        ..clear()
        ..addAll(original);
    }
    if (!mounted) return;
    setState(() => loading = false);
  }

  Future<void> _addNew() async {
    final name = await askText(context, 'New labour name', hint: 'Name');
    if (name == null || name.isEmpty) return;
    final id = await Db.addLabour(name);
    all = await Db.labours();
    crew[id] = 1;
    if (mounted) setState(() {});
  }

  Future<void> _copyLast() async {
    final last = await Db.lastCrewBefore(widget.date);
    if (last.isEmpty) {
      if (mounted) toast(context, 'No earlier day found');
      return;
    }
    setState(() {
      crew
        ..clear()
        ..addAll(last);
    });
  }

  Future<void> _save() async {
    if (crew.isEmpty) return;
    if (widget.dayId == null) {
      final existing = await Db.dayByDate(widget.date);
      if (existing != null) {
        if (!mounted) return;
        toast(context, 'A ledger for this date already exists');
        return;
      }
      final id = await Db.createDay(widget.date, crew);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DayLedgerScreen(dayId: id, date: widget.date)),
      );
    } else {
      final removed = original.keys.where((k) => !crew.containsKey(k)).toList();
      if (removed.isNotEmpty) {
        final ok = await confirm(context, 'Remove ${removed.length} labour from this day?',
            'Any advances given to them on this day will also be deleted.',
            ok: 'Remove');
        if (!ok) return;
      }
      await Db.setCrew(widget.dayId!, crew);
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.dayId != null;
    final shown = all
        .where((l) => (l.active || crew.containsKey(l.id)) && l.name.toLowerCase().contains(q.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(editing ? 'Edit crew' : "Start day's ledger", style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(fmtDay(widget.date), style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: dec('Search labour').copyWith(prefixIcon: const Icon(Icons.search)),
                  onChanged: (v) => setState(() => q = v),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(children: [
                  if (!editing) filterChip("Copy last day's crew", false, _copyLast),
                  filterChip('All active', false, () {
                    setState(() {
                      for (final l in all.where((x) => x.active)) {
                        crew.putIfAbsent(l.id, () => 1);
                      }
                    });
                  }),
                  filterChip('Clear', false, () => setState(() => crew.clear())),
                ]),
              ),
              Expanded(
                child: ListView(children: [
                  for (final l in shown) _row(l),
                  InkWell(
                    onTap: _addNew,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: const Row(children: [
                        Icon(Icons.add, color: kJuteDk),
                        SizedBox(width: 10),
                        Text('Add a new labour name', style: TextStyle(color: kJuteDk, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
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
                      onPressed: crew.isEmpty ? null : _save,
                      child: Text(editing ? 'Save crew (${crew.length})' : 'Start day with ${crew.length} labour'),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }

  Widget _row(Labour l) {
    final on = crew.containsKey(l.id);
    final w = crew[l.id] ?? 1;
    return InkWell(
      onTap: () => setState(() {
        if (on) {
          crew.remove(l.id);
        } else {
          crew[l.id] = 1;
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: kLine))),
        child: Row(children: [
          Checkbox(
            value: on,
            activeColor: kInk,
            onChanged: (v) => setState(() {
              if (v == true) {
                crew[l.id] = 1;
              } else {
                crew.remove(l.id);
              }
            }),
          ),
          Avatar(l.name, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ),
          if (on) ...[
            _seg('Full', w == 1, () => setState(() => crew[l.id] = 1)),
            const SizedBox(width: 6),
            _seg('Half', w == 0.5, () => setState(() => crew[l.id] = 0.5)),
            const SizedBox(width: 8),
          ] else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(l.last == null ? 'New' : 'Last ${fmtShort(l.last!)}',
                  style: const TextStyle(fontSize: 12, color: kInk2)),
            ),
        ]),
      ),
    );
  }

  Widget _seg(String t, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: on ? kInk : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? kInk : kLine, width: 1.5),
          ),
          child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : kInk)),
        ),
      );
}
