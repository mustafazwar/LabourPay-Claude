import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'labour_ledger_screen.dart';
import 'utils.dart';

Future<Uint8List> buildReportPdf(Report r, String from, String to, String who, String mill) async {
  final doc = pw.Document();
  pw.Widget cell(String t, {bool bold = false, bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text(t,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
  pw.Widget line(List<String> c, {bool bold = false}) => pw.Row(children: [
        pw.Expanded(flex: 3, child: cell(c[0], bold: bold)),
        pw.Expanded(flex: 1, child: cell(c[1], bold: bold, right: true)),
        pw.Expanded(flex: 2, child: cell(c[2], bold: bold, right: true)),
        pw.Expanded(flex: 2, child: cell(c[3], bold: bold, right: true)),
        pw.Expanded(flex: 2, child: cell(c[4], bold: bold, right: true)),
      ]);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => [
      pw.Text('Labour report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text(mill.isEmpty ? 'Mill' : mill, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
      pw.SizedBox(height: 4),
      pw.Text('${fmtDate(from)} to ${fmtDate(to)} - $who', style: const pw.TextStyle(fontSize: 11)),
      pw.Divider(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Work: ${money(r.work)}'),
        pw.Text('Tips: ${money(r.tips)}'),
        pw.Text('Advances: ${money(r.adv)}'),
        pw.Text('Net paid: ${money(r.net)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ]),
      pw.SizedBox(height: 4),
      pw.Text('Milling ${money(r.byType['milling'] ?? 0.0)}   Unload ${money(r.byType['unload'] ?? 0.0)}   Load ${money(r.byType['load'] ?? 0.0)}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 12),
      line(['Labour', 'Days', 'Earned', 'Advances', 'Net paid'], bold: true),
      pw.Divider(thickness: 0.6),
      for (final x in r.rows)
        line([x.labour.name, '${x.days}', money(x.earned), money(x.advance), money(x.net)]),
      pw.Divider(thickness: 0.6),
      line(['Total', '', money(r.work + r.tips), money(r.adv), money(r.net)], bold: true),
    ],
  ));
  return doc.save();
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int? labourId;
  String labourName = 'All labour';
  late String from;
  late String to;
  String type = 'all';
  late Future<Report> fut;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    from = ymd(DateTime(n.year, n.month, 1));
    to = ymd(n);
    fut = Db.report(from, to, labourId: labourId);
    dbTick.addListener(_reload);
  }

  @override
  void dispose() {
    dbTick.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => fut = Db.report(from, to, labourId: labourId));
  }

  Future<void> _pickDate(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: parseYmd(isFrom ? from : to),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    if (isFrom) {
      from = ymd(d);
      if (from.compareTo(to) > 0) to = from;
    } else {
      to = ymd(d);
      if (to.compareTo(from) < 0) from = to;
    }
    _reload();
  }

  Future<void> _pickLabour() async {
    final list = await Db.labours();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              title: const Text('All labour'),
              trailing: labourId == null ? const Icon(Icons.check) : null,
              onTap: () {
                Navigator.pop(ctx);
                labourId = null;
                labourName = 'All labour';
                _reload();
              },
            ),
            for (final l in list)
              ListTile(
                leading: Avatar(l.name, size: 30),
                title: Text(l.name),
                trailing: labourId == l.id ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  labourId = l.id;
                  labourName = l.name;
                  _reload();
                },
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _exportPdf(Report r) async {
    final mill = await Db.setting('mill_name');
    final bytes = await buildReportPdf(r, from, to, labourName, mill);
    await Printing.sharePdf(bytes: bytes, filename: 'report_${from}_$to.pdf');
  }

  Future<void> _exportCsv() async {
    final rows = await Db.csvRows(from: from, to: to, labourId: labourId);
    await shareTextFile('report_${from}_$to.csv', toCsv(rows));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_outlined),
            onSelected: (v) async {
              final r = await fut;
              if (v == 'pdf') await _exportPdf(r);
              if (v == 'csv') await _exportCsv();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Share as PDF')),
              PopupMenuItem(value: 'csv', child: Text('Share as CSV (Excel)')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<Report>(
        future: fut,
        builder: (context, snap) {
          final r = snap.data;
          return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InkWell(
                onTap: _pickLabour,
                child: InputDecorator(
                  decoration: dec('Labour'),
                  child: Row(children: [Expanded(child: Text(labourName)), const Icon(Icons.expand_more)]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: InputDecorator(decoration: dec('From'), child: Text(fmtDate(from))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: InputDecorator(decoration: dec('To'), child: Text(fmtDate(to))),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 0, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final t in const ['all', 'milling', 'unload', 'load', 'tips'])
                    filterChip(t == 'all' ? 'All' : workLabel(t), type == t, () => setState(() => type = t)),
                ]),
              ),
            ),
            if (r == null && snap.connectionState != ConnectionState.done)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (snap.hasError)
              Padding(padding: const EdgeInsets.all(20), child: Text('Something went wrong: ${snap.error}'))
            else if (r != null)
              ..._content(r),
          ]);
        },
      ),
    );
  }

  List<Widget> _content(Report r) {
    final maxType = [r.byType['milling'] ?? 0.0, r.byType['unload'] ?? 0.0, r.byType['load'] ?? 0.0, r.byType['tips'] ?? 0.0]
        .fold<double>(0, (a, b) => b > a ? b : a);
    Widget tile(String l, String v, {Color? color}) => Expanded(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l, style: const TextStyle(fontSize: 12, color: kInk2)),
              Text(v, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: color ?? kInk)),
            ]),
          ),
        );
    Widget bar(String label, double v) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(children: [
            kv(label, rs(v)),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: maxType > 0 ? v / maxType : 0,
                minHeight: 10,
                color: kJute,
                backgroundColor: kJuteBg,
              ),
            ),
          ]),
        );
    return [
      Container(
        margin: const EdgeInsets.only(top: 12),
        decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: kLine))),
        child: Column(children: [
          Row(children: [tile('Work', money(r.work)), const SizedBox(width: 1), tile('Tips', money(r.tips))]),
          const Divider(height: 1, color: kLine),
          Row(children: [
            tile('Advances', money(r.adv), color: kAdv),
            const SizedBox(width: 1),
            tile('Net paid', money(r.net), color: kEarn),
          ]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('${r.days} working day(s) in this range', style: const TextStyle(color: kInk2, fontSize: 12.5)),
      ),
      sectionLabel('By kind of work'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          bar('Milling', r.byType['milling'] ?? 0.0),
          bar('Unload', r.byType['unload'] ?? 0.0),
          bar('Load', r.byType['load'] ?? 0.0),
          bar('Tips', r.byType['tips'] ?? 0.0),
        ]),
      ),
      sectionLabel(type == 'all' ? 'By labour (earned)' : 'By labour (${workLabel(type)} only)'),
      if (r.rows.isEmpty) emptyState('Nothing in this range', 'Change the dates or labour above.'),
      for (final x in r.rows)
        listRow(
          leading: Avatar(x.labour.name, size: 34),
          title: x.labour.name,
          sub: '${x.days} days · advances ${money(x.advance)}',
          trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            amountText(money(x.earnedFor(type))),
            if (type == 'all') Text('net ${money(x.net)}', style: const TextStyle(fontSize: 11, color: kInk2)),
          ]),
          onTap: () => go(context, LabourLedgerScreen(labourId: x.labour.id)),
        ),
    ];
  }
}
