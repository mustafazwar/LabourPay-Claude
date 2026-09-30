import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'utils.dart';

class SlipLine {
  final String label;
  final String? sub;
  final String value;
  final bool bold;
  final bool neg;
  final bool topLine;
  SlipLine(this.label, this.value, {this.sub, this.bold = false, this.neg = false, this.topLine = false});
}

List<SlipLine> slipLines(DayCalc c, LabourDay ld) {
  final out = <SlipLine>[];
  for (final w in c.work) {
    out.add(SlipLine('${workLabel(w.type)} - ${w.material}', money(w.amount),
        sub: '${fmtQty(w.munn)} munn x ${money(w.rate)}'));
  }
  if (c.work.isNotEmpty) {
    out.add(SlipLine('Day work total', money(c.workTotal), bold: true, topLine: true));
  }
  final shareLabel = c.allFull
      ? 'Your share of work (1/${c.crew.length})'
      : 'Your share of work (${fmtNum(ld.weight)} of ${fmtNum(c.totalWeight)} shares)';
  out.add(SlipLine(shareLabel, money(ld.workShare)));
  if (c.tipTotal > 0) {
    out.add(SlipLine('Driver tips (day total)', money(c.tipTotal)));
    out.add(SlipLine('Your share of tips', money(ld.tipShare)));
  }
  out.add(SlipLine('Earned', money(ld.earned), bold: true, topLine: true));
  for (final a in c.advances) {
    if (a.labourId == ld.labour.id) {
      out.add(SlipLine('Advance${a.note.isEmpty ? '' : ' - ${a.note}'}', '-${money(a.amount)}', neg: true));
    }
  }
  if (ld.prevBal > 0) {
    out.add(SlipLine('Balance from earlier days', '-${money(ld.prevBal)}', neg: true));
  }
  return out;
}

Future<Uint8List> buildSlipPdf(DayCalc c, List<LabourDay> list, String mill) async {
  final doc = pw.Document();
  pw.Widget row(SlipLine l) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Column(children: [
          if (l.topLine) pw.Divider(thickness: 0.6),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(l.label,
                    style: pw.TextStyle(fontSize: 10.5, fontWeight: l.bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
                if (l.sub != null) pw.Text(l.sub!, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              ]),
            ),
            pw.Text(l.value,
                style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: l.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: l.neg ? PdfColors.red800 : PdfColors.black)),
          ]),
        ]),
      );

  for (final ld in list) {
    final crewNames = c.crew.map((x) => x.labour.name).join(', ');
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [

         pw.Row(children: [
           pw.Text(ld.labour.name, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
           pw.Text(fmtDay(c.day.date), style: const pw.TextStyle(fontSize: 10)),


         ]),

        pw.SizedBox(height: 2),
        pw.Text('Crew today (${c.crew.length}): $crewNames',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        pw.Divider(),
        ...slipLines(c, ld).map(row),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Net pay', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text('Rs ${money(ld.payable)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        if (ld.newBal > 0)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text('Balance carried forward: Rs ${money(ld.newBal)}',
                style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.red800)),
          ),

      ]),
    ));
  }
  return doc.save();
}

class SlipScreen extends StatefulWidget {
  final int dayId;
  final int? initialLabourId;
  const SlipScreen({super.key, required this.dayId, this.initialLabourId});
  @override
  State<SlipScreen> createState() => _SlipScreenState();
}

class _SlipScreenState extends State<SlipScreen> {
  DayCalc? calc;
  String mill = '';
  PageController? pc;
  int page = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    pc?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await Db.calc(widget.dayId);
      mill = await Db.setting('mill_name');
      var idx = 0;
      if (widget.initialLabourId != null) {
        final i = c.crew.indexWhere((x) => x.labour.id == widget.initialLabourId);
        if (i >= 0) idx = i;
      }
      pc = PageController(initialPage: idx);
      page = idx;
      if (!mounted) return;
      setState(() => calc = c);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  String _file(LabourDay ld) => 'slip_${ld.labour.name.replaceAll(' ', '_')}_${calc!.day.date}.pdf';

  Future<void> _print(List<LabourDay> list, String name) async {
    final bytes = await buildSlipPdf(calc!, list, mill);
    await Printing.layoutPdf(onLayout: (format) async => bytes, name: name);
  }

  Future<void> _share(List<LabourDay> list, String filename) async {
    final bytes = await buildSlipPdf(calc!, list, mill);
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  @override
  Widget build(BuildContext context) {
    final c = calc;
    if (error != null) {
      return Scaffold(appBar: AppBar(title: const Text('Slips')), body: Center(child: Text(error!)));
    }
    if (c == null) {
      return Scaffold(appBar: AppBar(title: const Text('Slips')), body: const Center(child: CircularProgressIndicator()));
    }
    if (c.crew.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('Slips')), body: emptyState('No labour on this day', 'There are no slips to show.'));
    }
    final ld = c.crew[page.clamp(0, c.crew.length - 1).toInt()];
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Slip · ${ld.labour.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${page + 1} of ${c.crew.length}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'shareAll') _share(c.crew, 'slips_${c.day.date}.pdf');
              if (v == 'printAll') _print(c.crew, 'slips_${c.day.date}');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'shareAll', child: Text('Share all slips (PDF)')),
              PopupMenuItem(value: 'printAll', child: Text('Print all slips')),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: pc,
        itemCount: c.crew.length,
        onPageChanged: (i) => setState(() => page = i),
        itemBuilder: (context, i) => _slipPage(c, c.crew[i]),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print'),
                onPressed: () => _print([ld], _file(ld)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share PDF'),
                onPressed: () => _share([ld], _file(ld)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _slipPage(DayCalc c, LabourDay ld) {
    final lines = slipLines(c, ld);
    return ListView(padding: const EdgeInsets.all(14), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Color(0x1F1B2740), blurRadius: 10, offset: Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Daily labour slip', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(mill.isEmpty ? 'Set your mill name in Settings' : mill,
                    style: const TextStyle(fontSize: 12, color: kInk2)),
              ]),
            ),
            Text(fmtDay(c.day.date), style: const TextStyle(fontSize: 12, color: kInk2)),
          ]),
          _dash(),
          Text(ld.labour.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Crew today (${c.crew.length}): ${c.crew.map((x) => x.labour.name).join(', ')}',
              style: const TextStyle(fontSize: 12, color: kInk2)),
          _dash(),
          for (final l in lines) ...[
            if (l.topLine) const Divider(height: 14, color: kLine),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.label, style: TextStyle(fontSize: 13.5, fontWeight: l.bold ? FontWeight.w800 : FontWeight.w500)),
                    if (l.sub != null) Text(l.sub!, style: const TextStyle(fontSize: 11.5, color: kInk2)),
                  ]),
                ),
                Text(l.value,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: l.bold ? FontWeight.w800 : FontWeight.w700,
                        color: l.neg ? kAdv : kInk)),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: kEarnBg, borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const Expanded(child: Text('Net pay', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Text(rs(ld.payable), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kEarn)),
            ]),
          ),
          if (ld.newBal > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Balance carried forward: ${rs(ld.newBal)}',
                  style: const TextStyle(color: kAdv, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ),
          const SizedBox(height: 26),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _sign('Labour'),
            _sign('Munshi'),
          ]),
        ]),
      ),
      const SizedBox(height: 8),
      const Center(child: Text('Swipe left or right for the next labour', style: TextStyle(fontSize: 12, color: kInk2))),
    ]);
  }

  Widget _dash() => const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: kLine));

  Widget _sign(String t) => Column(children: [
        Container(width: 120, height: 1, color: const Color(0xFF9AA3B4)),
        const SizedBox(height: 4),
        Text(t, style: const TextStyle(fontSize: 11, color: kInk2)),
      ]);
}
