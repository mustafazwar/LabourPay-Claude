import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'utils.dart';


// ============================================================
// PAPER SIZE
// ============================================================

enum SlipPaperSize {
  a4,
  a5,
  mm58,
  mm80,
}

extension SlipPaperSizeExtension on SlipPaperSize {
  String get title {
    switch (this) {
      case SlipPaperSize.a4:
        return 'A4';

      case SlipPaperSize.a5:
        return 'A5';

      case SlipPaperSize.mm58:
        return '58 mm';

      case SlipPaperSize.mm80:
        return '80 mm';
    }
  }

  String get subtitle {
    switch (this) {
      case SlipPaperSize.a4:
        return 'Standard office paper';

      case SlipPaperSize.a5:
        return 'Half-size office paper';

      case SlipPaperSize.mm58:
        return '58 mm thermal printer';

      case SlipPaperSize.mm80:
        return '80 mm thermal printer';
    }
  }

  bool get isThermal {
    return this == SlipPaperSize.mm58 ||
        this == SlipPaperSize.mm80;
  }

  PdfPageFormat get format {
    switch (this) {
      case SlipPaperSize.a4:
        return PdfPageFormat.a4;

      case SlipPaperSize.a5:
        return PdfPageFormat.a5;

      case SlipPaperSize.mm58:
        return PdfPageFormat(
          58 * PdfPageFormat.mm,
          180 * PdfPageFormat.mm,
        );

      case SlipPaperSize.mm80:
        return PdfPageFormat(
          80 * PdfPageFormat.mm,
          180 * PdfPageFormat.mm,
        );
    }
  }
}


// ============================================================
// SLIP LINE
// ============================================================

class SlipLine {
  final String label;
  final String? sub;
  final String value;
  final bool bold;
  final bool neg;
  final bool topLine;

  SlipLine(
      this.label,
      this.value, {
        this.sub,
        this.bold = false,
        this.neg = false,
        this.topLine = false,
      });
}


// ============================================================
// SLIP DATA
// ============================================================

List<SlipLine> slipLines(
    DayCalc c,
    LabourDay ld,
    ) {
  final out = <SlipLine>[];

  // ----------------------------------------------------------
  // WORK
  // ----------------------------------------------------------

  for (final w in c.work) {
    out.add(
      SlipLine(
        '${workLabel(w.type)} - ${w.material}',
        money(w.amount),
        sub: '${fmtQty(w.munn)} munn × ${money(w.rate)}',
      ),
    );
  }

  // ----------------------------------------------------------
  // TOTAL WORK
  // ----------------------------------------------------------

  if (c.work.isNotEmpty) {
    out.add(
      SlipLine(
        'Day work total',
        money(c.workTotal),
        bold: true,
        topLine: true,
      ),
    );
  }

  // ----------------------------------------------------------
  // WORK SHARE
  // ----------------------------------------------------------

  final shareLabel = c.allFull
      ? 'Your share of work (1/${c.crew.length})'
      : 'Your share of work '
      '(${fmtNum(ld.weight)} of ${fmtNum(c.totalWeight)} shares)';

  out.add(
    SlipLine(
      shareLabel,
      money(ld.workShare),
    ),
  );

  // ----------------------------------------------------------
  // TIPS
  // ----------------------------------------------------------

  if (c.tipTotal > 0) {
    out.add(
      SlipLine(
        'Driver tips (day total)',
        money(c.tipTotal),
      ),
    );

    out.add(
      SlipLine(
        'Your share of tips',
        money(ld.tipShare),
      ),
    );
  }

  // ----------------------------------------------------------
  // EARNED
  // ----------------------------------------------------------

  out.add(
    SlipLine(
      'Earned',
      money(ld.earned),
      bold: true,
      topLine: true,
    ),
  );

  // ----------------------------------------------------------
  // ADVANCES
  // ----------------------------------------------------------

  for (final a in c.advances) {
    if (a.labourId == ld.labour.id) {
      out.add(
        SlipLine(
          'Advance${a.note.isEmpty ? '' : ' - ${a.note}'}',
          '-${money(a.amount)}',
          neg: true,
        ),
      );
    }
  }

  // ----------------------------------------------------------
  // PREVIOUS BALANCE
  // ----------------------------------------------------------

  if (ld.prevBal > 0) {
    out.add(
      SlipLine(
        'Balance from earlier days',
        '-${money(ld.prevBal)}',
        neg: true,
      ),
    );
  }

  return out;
}


// ============================================================
// PDF
// ============================================================

Future<Uint8List> buildSlipPdf(
    DayCalc c,
    List<LabourDay> list,
    String mill, {
      SlipPaperSize paperSize = SlipPaperSize.a5,
    }) async {
  final doc = pw.Document();

  final bool is58 = paperSize == SlipPaperSize.mm58;
  final bool is80 = paperSize == SlipPaperSize.mm80;
  final bool thermal = paperSize.isThermal;

  // ----------------------------------------------------------
  // RESPONSIVE TYPOGRAPHY
  // ----------------------------------------------------------

  double bodyFont;
  double subFont;
  double nameFont;
  double dateFont;
  double netLabelFont;
  double netValueFont;
  double margin;
  double rowVerticalPadding;

  switch (paperSize) {
    case SlipPaperSize.mm58:
      bodyFont = 7.8;
      subFont = 6.1;
      nameFont = 10.5;
      dateFont = 7.2;
      netLabelFont = 8;
      netValueFont = 13;
      margin = 5.5;
      rowVerticalPadding = 1.4;
      break;

    case SlipPaperSize.mm80:
      bodyFont = 9;
      subFont = 7;
      nameFont = 12;
      dateFont = 8;
      netLabelFont = 9.5;
      netValueFont = 15;
      margin = 7;
      rowVerticalPadding = 1.8;
      break;

    case SlipPaperSize.a4:
      bodyFont = 11;
      subFont = 8.5;
      nameFont = 17;
      dateFont = 10;
      netLabelFont = 13;
      netValueFont = 20;
      margin = 30;
      rowVerticalPadding = 3.5;
      break;

    case SlipPaperSize.a5:
      bodyFont = 10.5;
      subFont = 8.5;
      nameFont = 15;
      dateFont = 10;
      netLabelFont = 13;
      netValueFont = 18;
      margin = 28;
      rowVerticalPadding = 2.5;
      break;
  }

  // ----------------------------------------------------------
  // PDF ROW
  // ----------------------------------------------------------

  pw.Widget pdfRow(SlipLine line) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(
        vertical: rowVerticalPadding,
      ),
      decoration: line.topLine
          ? pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            width: thermal ? 0.45 : 0.7,
            color: PdfColors.grey500,
          ),
        ),
      )
          : null,
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [

          // LABEL + SUB
          pw.Expanded(
            flex: 7,
            child: pw.Column(
              crossAxisAlignment:
              pw.CrossAxisAlignment.start,
              children: [

                pw.Text(
                  line.label,
                  maxLines: 3,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    fontSize: bodyFont,
                    fontWeight: line.bold
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),

                if (line.sub != null)
                  pw.Text(
                    line.sub!,
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      fontSize: subFont,
                      color: PdfColors.grey700,
                    ),
                  ),
              ],
            ),
          ),

          pw.SizedBox(
            width: thermal ? 3 : 8,
          ),

          // VALUE
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              line.value,
              textAlign: pw.TextAlign.right,
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                fontSize: bodyFont,
                fontWeight: line.bold
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                color: line.neg
                    ? PdfColors.red800
                    : PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // ONE SLIP PER PAGE
  // ----------------------------------------------------------

  for (final ld in list) {
    final crewNames = c.crew
        .map((x) => x.labour.name)
        .join(', ');

    doc.addPage(
      pw.Page(
        pageFormat: paperSize.format,
        margin: pw.EdgeInsets.all(margin),

        build: (ctx) {
          return pw.Column(
            crossAxisAlignment:
            pw.CrossAxisAlignment.start,
            children: [

              // =================================================
              // HEADER
              // =================================================

              pw.Row(
                crossAxisAlignment:
                pw.CrossAxisAlignment.start,
                children: [

                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment:
                      pw.CrossAxisAlignment.start,
                      children: [

                        if (mill.isNotEmpty)
                          pw.Text(
                            mill,
                            maxLines: 2,
                            overflow:
                            pw.TextOverflow.clip,
                            style: pw.TextStyle(
                              fontSize:
                              thermal ? 9 : 14,
                              fontWeight:
                              pw.FontWeight.bold,
                            ),
                          ),

                        pw.Text(
                          'Daily labour slip',
                          style: pw.TextStyle(
                            fontSize:
                            thermal ? 7 : 10,
                            fontWeight:
                            pw.FontWeight.bold,
                            color:
                            PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(
                    width: 4,
                  ),

                  pw.Text(
                    fmtDay(c.day.date),
                    style: pw.TextStyle(
                      fontSize: dateFont,
                      color:
                      PdfColors.grey700,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(
                height: thermal ? 3 : 6,
              ),

              // =================================================
              // LABOUR NAME
              // =================================================

              pw.Text(
                ld.labour.name,
                maxLines: 2,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(
                  fontSize: nameFont,
                  fontWeight:
                  pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(
                height: thermal ? 1.5 : 3,
              ),

              // =================================================
              // CREW
              // =================================================

              pw.Text(
                'Crew (${c.crew.length}): $crewNames',
                maxLines: is58 ? 5 : 8,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(
                  fontSize: subFont,
                  color: PdfColors.grey700,
                ),
              ),

              pw.Divider(
                thickness:
                thermal ? 0.5 : 0.8,
                height:
                thermal ? 5 : 9,
              ),

              // =================================================
              // LINES
              // =================================================

              ...slipLines(c, ld).map(pdfRow),

              pw.SizedBox(
                height: thermal ? 4 : 9,
              ),

              // =================================================
              // NET PAY
              // =================================================

              pw.Container(
                width: double.infinity,
                padding: pw.EdgeInsets.symmetric(
                  horizontal: thermal ? 6 : 10,
                  vertical: thermal ? 5 : 9,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius:
                  pw.BorderRadius.circular(
                    thermal ? 3 : 6,
                  ),
                  border: pw.Border.all(
                    color: PdfColors.green700,
                    width:
                    thermal ? 0.5 : 0.8,
                  ),
                ),
                child: pw.Row(
                  crossAxisAlignment:
                  pw.CrossAxisAlignment.center,
                  children: [

                    pw.Expanded(
                      child: pw.Text(
                        'NET PAY',
                        style: pw.TextStyle(
                          fontSize: netLabelFont,
                          fontWeight:
                          pw.FontWeight.bold,
                        ),
                      ),
                    ),

                    pw.Text(
                      'Rs ${money(ld.payable)}',
                      textAlign:
                      pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: netValueFont,
                        fontWeight:
                        pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // =================================================
              // NEW BALANCE
              // =================================================

              if (ld.newBal > 0)
                pw.Padding(
                  padding:
                  pw.EdgeInsets.only(
                    top: thermal ? 3 : 6,
                  ),
                  child: pw.Text(
                    'Balance carried forward: '
                        'Rs ${money(ld.newBal)}',
                    maxLines: 2,
                    overflow:
                    pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      fontSize: subFont,
                      color:
                      PdfColors.red800,
                      fontWeight:
                      pw.FontWeight.bold,
                    ),
                  ),
                ),

              // =================================================
              // SIGNATURES
              // =================================================

              pw.Spacer(),

              pw.SizedBox(
                height: thermal ? 8 : 20,
              ),

              pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
                children: [

                  pw.Column(
                    children: [

                      pw.Container(
                        width: thermal ? 42 : 70,
                        height:
                        thermal ? 8 : 16,
                        decoration:
                        pw.BoxDecoration(
                          border: pw.Border(
                            bottom:
                            pw.BorderSide(
                              width:
                              thermal
                                  ? 0.5
                                  : 0.8,
                              color:
                              PdfColors.grey600,
                            ),
                          ),
                        ),
                      ),

                      pw.SizedBox(
                        height: 2,
                      ),

                      pw.Text(
                        'Labour',
                        style: pw.TextStyle(
                          fontSize: subFont,
                          color:
                          PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),

                  pw.Column(
                    children: [

                      pw.Container(
                        width: thermal ? 42 : 70,
                        height:
                        thermal ? 8 : 16,
                        decoration:
                        pw.BoxDecoration(
                          border: pw.Border(
                            bottom:
                            pw.BorderSide(
                              width:
                              thermal
                                  ? 0.5
                                  : 0.8,
                              color:
                              PdfColors.grey600,
                            ),
                          ),
                        ),
                      ),

                      pw.SizedBox(
                        height: 2,
                      ),

                      pw.Text(
                        'Munshi',
                        style: pw.TextStyle(
                          fontSize: subFont,
                          color:
                          PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(
                height: thermal ? 4 : 8,
              ),

              // PAGE NUMBER
              pw.Center(
                child: pw.Text(
                  '${list.indexOf(ld) + 1} / ${list.length}',
                  style: pw.TextStyle(
                    fontSize: subFont,
                    color:
                    PdfColors.grey600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  return doc.save();
}


// ============================================================
// SLIP SCREEN
// ============================================================

class SlipScreen extends StatefulWidget {
  final int dayId;
  final int? initialLabourId;

  const SlipScreen({
    super.key,
    required this.dayId,
    this.initialLabourId,
  });

  @override
  State<SlipScreen> createState() =>
      _SlipScreenState();
}


class _SlipScreenState extends State<SlipScreen> {
  DayCalc? calc;

  String mill = '';

  PageController? pc;

  int page = 0;

  String? error;

  bool busy = false;


  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _load();
  }


  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    pc?.dispose();

    super.dispose();
  }


  // ==========================================================
  // LOAD
  // ==========================================================

  Future<void> _load() async {
    try {
      final c = await Db.calc(
        widget.dayId,
      );

      final millName =
      await Db.setting('mill_name');

      var idx = 0;

      if (widget.initialLabourId != null) {
        final i = c.crew.indexWhere(
              (x) =>
          x.labour.id ==
              widget.initialLabourId,
        );

        if (i >= 0) {
          idx = i;
        }
      }

      final controller =
      PageController(
        initialPage: idx,
      );

      page = idx;

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        calc = c;
        mill = millName;
        pc = controller;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = '$e';
      });
    }
  }


  // ==========================================================
  // FILE NAME
  // ==========================================================

  String _file(
      LabourDay ld,
      ) {
    final safeName = ld.labour.name
        .replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');

    return 'slip_${safeName}_${calc!.day.date}.pdf';
  }


  // ==========================================================
  // PAPER SIZE PICKER
  // ==========================================================

  Future<SlipPaperSize?> _choosePaperSize({
    required String title,
  }) {
    return showModalBottomSheet<SlipPaperSize>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            padding:
            const EdgeInsets.fromLTRB(
              18,
              10,
              18,
              18,
            ),
            decoration:
            const BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [

                // HANDLE
                Container(
                  width: 42,
                  height: 4,
                  decoration:
                  BoxDecoration(
                    color: Colors.black12,
                    borderRadius:
                    BorderRadius.circular(20),
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                Row(
                  children: [

                    Container(
                      width: 46,
                      height: 46,
                      decoration:
                      BoxDecoration(
                        color:
                        const Color(
                          0xFFE8F5EE,
                        ),
                        borderRadius:
                        BorderRadius.circular(
                          14,
                        ),
                      ),
                      child: const Icon(
                        Icons
                            .print_rounded,
                        color:
                        Color(0xFF1A6B3C),
                      ),
                    ),

                    const SizedBox(
                      width: 12,
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                        children: [

                          Text(
                            title,
                            style:
                            const TextStyle(
                              fontSize: 18,
                              fontWeight:
                              FontWeight.w800,
                            ),
                          ),

                          const SizedBox(
                            height: 3,
                          ),

                          const Text(
                            'Choose the paper used by your printer',
                            style:
                            TextStyle(
                              fontSize: 12,
                              color:
                              Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 18,
                ),

                ...SlipPaperSize.values
                    .map(
                      (size) {
                    final thermal =
                        size.isThermal;

                    return Padding(
                      padding:
                      const EdgeInsets
                          .only(
                        bottom: 9,
                      ),
                      child: InkWell(
                        borderRadius:
                        BorderRadius
                            .circular(
                          17,
                        ),
                        onTap: () {
                          Navigator.pop(
                            context,
                            size,
                          );
                        },
                        child: Container(
                          padding:
                          const EdgeInsets
                              .all(
                            13,
                          ),
                          decoration:
                          BoxDecoration(
                            color: thermal
                                ? const Color(
                              0xFFF5FBF7,
                            )
                                : const Color(
                              0xFFF8F8F8,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              17,
                            ),
                            border:
                            Border.all(
                              color: thermal
                                  ? const Color(
                                0xFFB9DCC8,
                              )
                                  : Colors
                                  .black12,
                            ),
                          ),
                          child: Row(
                            children: [

                              Container(
                                width: 46,
                                height: 46,
                                decoration:
                                BoxDecoration(
                                  color: thermal
                                      ? const Color(
                                    0xFFE8F5EE,
                                  )
                                      : Colors
                                      .white,
                                  borderRadius:
                                  BorderRadius
                                      .circular(
                                    13,
                                  ),
                                ),
                                child: Icon(
                                  thermal
                                      ? Icons
                                      .receipt_long_rounded
                                      : Icons
                                      .description_rounded,
                                  color:
                                  const Color(
                                    0xFF1A6B3C,
                                  ),
                                ),
                              ),

                              const SizedBox(
                                width: 12,
                              ),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                                  children: [

                                    Text(
                                      size.title,
                                      style:
                                      const TextStyle(
                                        fontSize: 15,
                                        fontWeight:
                                        FontWeight.w800,
                                      ),
                                    ),

                                    const SizedBox(
                                      height: 3,
                                    ),

                                    Text(
                                      size.subtitle,
                                      style:
                                      const TextStyle(
                                        fontSize: 11.5,
                                        color:
                                        Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const Icon(
                                Icons
                                    .chevron_right_rounded,
                                color:
                                Colors.black38,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  // ==========================================================
  // PRINT
  // ==========================================================

  Future<void> _print(
      List<LabourDay> list,
      String name,
      ) async {
    if (calc == null || list.isEmpty) {
      return;
    }

    final paper =
    await _choosePaperSize(
      title: 'Print Slip',
    );

    if (paper == null) {
      return;
    }

    try {
      setState(() {
        busy = true;
      });

      final bytes =
      await buildSlipPdf(
        calc!,
        list,
        mill,
        paperSize: paper,
      );

      await Printing.layoutPdf(
        name: name,
        format: paper.format,
        onLayout: (format) async {
          return bytes;
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Print failed: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }


  // ==========================================================
  // SHARE
  // ==========================================================

  Future<void> _share(
      List<LabourDay> list,
      String filename,
      ) async {
    if (calc == null || list.isEmpty) {
      return;
    }

    final paper =
    await _choosePaperSize(
      title: 'Share Slip PDF',
    );

    if (paper == null) {
      return;
    }

    try {
      setState(() {
        busy = true;
      });

      final bytes =
      await buildSlipPdf(
        calc!,
        list,
        mill,
        paperSize: paper,
      );

      await Printing.sharePdf(
        bytes: bytes,
        filename: filename,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Could not share PDF: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }


  // ==========================================================
  // MAIN BUILD
  // ==========================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    final c = calc;

    // --------------------------------------------------------
    // ERROR
    // --------------------------------------------------------

    if (error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Slips',
          ),
        ),
        body: Center(
          child: Padding(
            padding:
            const EdgeInsets.all(24),
            child: Text(
              error!,
              textAlign:
              TextAlign.center,
            ),
          ),
        ),
      );
    }

    // --------------------------------------------------------
    // LOADING
    // --------------------------------------------------------

    if (c == null || pc == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Slips',
          ),
        ),
        body: const Center(
          child:
          CircularProgressIndicator(),
        ),
      );
    }

    // --------------------------------------------------------
    // EMPTY
    // --------------------------------------------------------

    if (c.crew.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Slips',
          ),
        ),
        body: emptyState(
          'No labour on this day',
          'There are no slips to show.',
        ),
      );
    }

    // --------------------------------------------------------
    // CURRENT LABOUR
    // --------------------------------------------------------

    final safePage =
    page.clamp(
      0,
      c.crew.length - 1,
    );

    final ld =
    c.crew[safePage];

    // --------------------------------------------------------
    // SCREEN
    // --------------------------------------------------------

    return Scaffold(
      backgroundColor:
      const Color(0xFFF4F7F5),

      appBar: AppBar(
        title: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [

            Text(
              'Slip · ${ld.labour.name}',
              style:
              const TextStyle(
                fontWeight:
                FontWeight.w700,
              ),
            ),

            Text(
              '${page + 1} of ${c.crew.length}',
              style:
              const TextStyle(
                fontSize: 12,
                color:
                Colors.white70,
              ),
            ),
          ],
        ),

        actions: [

          // ==================================================
          // MENU
          // ==================================================

          PopupMenuButton<String>(
            enabled: !busy,

            onSelected: (v) async {
              if (v == 'shareAll') {
                await _share(
                  c.crew,
                  'slips_${c.day.date}.pdf',
                );
              }

              if (v == 'printAll') {
                await _print(
                  c.crew,
                  'slips_${c.day.date}',
                );
              }

              if (v == 'bluetooth') {
                /*
                 * Add your PrintViaBluetooh screen here
                 * once its constructor is finalized.
                 *
                 * Example:
                 *
                 * Navigator.push(
                 *   context,
                 *   MaterialPageRoute(
                 *     builder: (_) =>
                 *         PrintViaBluetooh(
                 *       calc: c,
                 *       labourDay: ld,
                 *       mill: mill,
                 *     ),
                 *   ),
                 * );
                 */
              }
            },

            itemBuilder: (_) => const [

              PopupMenuItem(
                value: 'shareAll',
                child: ListTile(
                  contentPadding:
                  EdgeInsets.zero,
                  leading: Icon(
                    Icons
                        .picture_as_pdf_rounded,
                  ),
                  title: Text(
                    'Share all slips',
                  ),
                  subtitle: Text(
                    'Create one PDF',
                  ),
                ),
              ),

              PopupMenuItem(
                value: 'printAll',
                child: ListTile(
                  contentPadding:
                  EdgeInsets.zero,
                  leading: Icon(
                    Icons.print_rounded,
                  ),
                  title: Text(
                    'Print all slips',
                  ),
                  subtitle: Text(
                    'Choose paper size',
                  ),
                ),
              ),

              PopupMenuDivider(),

              PopupMenuItem(
                value: 'bluetooth',
                child: ListTile(
                  contentPadding:
                  EdgeInsets.zero,
                  leading: Icon(
                    Icons.bluetooth_rounded,
                  ),
                  title: Text(
                    'Print via Bluetooth',
                  ),
                  subtitle: Text(
                    'Thermal printer',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),

      // ======================================================
      // PAGES
      // ======================================================

      body: PageView.builder(
        controller: pc,
        itemCount:
        c.crew.length,

        onPageChanged: (i) {
          setState(() {
            page = i;
          });
        },

        itemBuilder:
            (context, i) {
          return _slipPage(
            c,
            c.crew[i],
          );
        },
      ),

      // ======================================================
      // BOTTOM BUTTONS
      // ======================================================

      bottomNavigationBar:
      Container(
        color: Colors.white,
        padding:
        const EdgeInsets.fromLTRB(
          16,
          10,
          16,
          14,
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [

              // PRINT
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(
                    Icons.print_outlined,
                  ),
                  label: const Text(
                    'Print',
                  ),
                  onPressed: busy
                      ? null
                      : () {
                    _print(
                      [ld],
                      _file(ld),
                    );
                  },
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              // SHARE
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(
                    Icons.share_outlined,
                  ),
                  label: const Text(
                    'Share PDF',
                  ),
                  onPressed: busy
                      ? null
                      : () {
                    _share(
                      [ld],
                      _file(ld),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ==========================================================
  // MOBILE SLIP PREVIEW
  // ==========================================================

  Widget _slipPage(
      DayCalc c,
      LabourDay ld,
      ) {
    final lines =
    slipLines(c, ld);

    return ListView(
      padding:
      const EdgeInsets.all(14),

      children: [

        Container(
          padding:
          const EdgeInsets.all(18),

          decoration:
          BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                color:
                Color(0x1F1B2740),
                blurRadius: 10,
                offset:
                Offset(0, 2),
              ),
            ],
          ),

          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [

              // =================================================
              // HEADER
              // =================================================

              Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,

                children: [

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      children: [

                        const Text(
                          'Daily labour slip',
                          style:
                          TextStyle(
                            fontSize: 17,
                            fontWeight:
                            FontWeight.w800,
                          ),
                        ),

                        Text(
                          mill.isEmpty
                              ? 'Set your mill name in Settings'
                              : mill,
                          style:
                          const TextStyle(
                            fontSize: 12,
                            color: kInk2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Text(
                    fmtDay(
                      c.day.date,
                    ),
                    style:
                    const TextStyle(
                      fontSize: 12,
                      color: kInk2,
                    ),
                  ),
                ],
              ),

              _dash(),

              // =================================================
              // LABOUR
              // =================================================

              Text(
                ld.labour.name,
                style:
                const TextStyle(
                  fontSize: 18,
                  fontWeight:
                  FontWeight.w800,
                ),
              ),

              const SizedBox(
                height: 3,
              ),

              Text(
                'Crew today (${c.crew.length}): '
                    '${c.crew.map((x) => x.labour.name).join(', ')}',
                style:
                const TextStyle(
                  fontSize: 12,
                  color: kInk2,
                ),
              ),

              _dash(),

              // =================================================
              // DETAILS
              // =================================================

              for (final l in lines) ...[
                if (l.topLine)
                  const Divider(
                    height: 14,
                    color: kLine,
                  ),

                Padding(
                  padding:
                  const EdgeInsets.symmetric(
                    vertical: 4,
                  ),

                  child: Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,

                    children: [

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,

                          children: [

                            Text(
                              l.label,
                              style:
                              TextStyle(
                                fontSize: 13.5,
                                fontWeight:
                                l.bold
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),

                            if (l.sub != null)
                              Text(
                                l.sub!,
                                style:
                                const TextStyle(
                                  fontSize: 11.5,
                                  color: kInk2,
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Text(
                        l.value,
                        textAlign:
                        TextAlign.right,
                        style:
                        TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                          l.bold
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color:
                          l.neg
                              ? kAdv
                              : kInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(
                height: 10,
              ),

              // =================================================
              // NET PAY
              // =================================================

              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),

                decoration:
                BoxDecoration(
                  color: kEarnBg,
                  borderRadius:
                  BorderRadius.circular(
                    10,
                  ),
                ),

                child: Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.center,

                  children: [

                    const Expanded(
                      child: Text(
                        'Net pay',
                        style:
                        TextStyle(
                          fontWeight:
                          FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),

                    Text(
                      rs(ld.payable),
                      style:
                      const TextStyle(
                        fontSize: 26,
                        fontWeight:
                        FontWeight.w800,
                        color: kEarn,
                      ),
                    ),
                  ],
                ),
              ),

              // =================================================
              // NEW BALANCE
              // =================================================

              if (ld.newBal > 0)
                Padding(
                  padding:
                  const EdgeInsets.only(
                    top: 8,
                  ),
                  child: Text(
                    'Balance carried forward: '
                        '${rs(ld.newBal)}',
                    style:
                    const TextStyle(
                      color: kAdv,
                      fontWeight:
                      FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),

              const SizedBox(
                height: 26,
              ),

              // =================================================
              // SIGNATURES
              // =================================================

              Row(
                mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,

                children: [
                  _sign(
                    'Labour',
                  ),

                  _sign(
                    'Munshi',
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(
          height: 8,
        ),

        const Center(
          child: Text(
            'Swipe left or right for the next labour',
            style: TextStyle(
              fontSize: 12,
              color: kInk2,
            ),
          ),
        ),
      ],
    );
  }


  // ==========================================================
  // DIVIDER
  // ==========================================================

  Widget _dash() {
    return const Padding(
      padding:
      EdgeInsets.symmetric(
        vertical: 10,
      ),
      child: Divider(
        height: 1,
        color: kLine,
      ),
    );
  }


  // ==========================================================
  // SIGNATURE
  // ==========================================================

  Widget _sign(
      String title,
      ) {
    return Column(
      children: [

        Container(
          width: 120,
          height: 1,
          color:
          const Color(
            0xFF9AA3B4,
          ),
        ),

        const SizedBox(
          height: 4,
        ),

        Text(
          title,
          style:
          const TextStyle(
            fontSize: 11,
            color: kInk2,
          ),
        ),
      ],
    );
  }
}