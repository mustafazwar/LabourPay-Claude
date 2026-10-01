import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'slip_screen.dart' show slipLines; // <- change to your slip file name
import 'utils.dart';

class PrintViaApnaBluetooh extends StatefulWidget {
  final DayCalc calc;
  final LabourDay labourDay;
  final String mill;

  const PrintViaApnaBluetooh({
    super.key,
    required this.calc,
    required this.labourDay,
    required this.mill,
  });

  @override
  State<PrintViaApnaBluetooh> createState() => _PrintViaBluetoohState();
}

class _PrintViaBluetoohState extends State<PrintViaApnaBluetooh> {
  static const int _w = 32; // characters per line on 58mm (font A)

  List<BluetoothInfo> devices = [];
  String? connectedMac;
  bool loading = false;
  bool busy = false;
  String? message;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  // ------------------------------------------------------------
  // DEVICES
  // ------------------------------------------------------------

  Future<void> _loadDevices() async {
    setState(() {
      loading = true;
      message = null;
    });

    try {
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;

      if (!enabled) {
        if (!mounted) return;
        setState(() {
          loading = false;
          message = 'Bluetooth is off. Turn it on, then tap refresh.';
        });
        return;
      }

      final list = await PrintBluetoothThermal.pairedBluetooths;
      final isConnected = await PrintBluetoothThermal.connectionStatus;

      if (!mounted) return;
      setState(() {
        devices = list;
        if (!isConnected) connectedMac = null;
        loading = false;
        if (list.isEmpty) {
          message =
          'No paired printer found. Pair it in phone Bluetooth settings first.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        message = 'Bluetooth error: $e';
      });
    }
  }

  Future<void> _connect(BluetoothInfo d) async {
    if (busy) return;
    setState(() => busy = true);

    try {
      if (await PrintBluetoothThermal.connectionStatus) {
        await PrintBluetoothThermal.disconnect;
      }

      final ok = await PrintBluetoothThermal.connect(
        macPrinterAddress: d.macAdress,
      );

      if (!mounted) return;
      setState(() => connectedMac = ok ? d.macAdress : null);
      _toast(ok ? 'Connected to ${d.name}' : 'Could not connect to ${d.name}');
    } catch (e) {
      _toast('Connect failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ------------------------------------------------------------
  // TEXT HELPERS
  // ------------------------------------------------------------

  // Thermal printers cannot print most non-ASCII characters.
  String _clean(String s) => s
      .replaceAll('×', 'x')
      .replaceAll('–', '-')
      .replaceAll('·', '-')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

  List<String> _wrap(String s, int w) {
    final out = <String>[];
    var cur = '';

    for (final word in _clean(s).split(' ')) {
      var wd = word;

      while (wd.length > w) {
        if (cur.isNotEmpty) {
          out.add(cur);
          cur = '';
        }
        out.add(wd.substring(0, w));
        wd = wd.substring(w);
      }

      if (cur.isEmpty) {
        cur = wd;
      } else if (cur.length + 1 + wd.length <= w) {
        cur = '$cur $wd';
      } else {
        out.add(cur);
        cur = wd;
      }
    }

    if (cur.isNotEmpty) out.add(cur);
    return out.isEmpty ? [''] : out;
  }

  /// "Label ........ value" with the label wrapped if it is long.
  List<String> _row(String label, String value) {
    value = _clean(value);

    if (value.length > 18) {
      return [..._wrap(label, _w), value.padLeft(_w)];
    }

    final labW = _w - value.length - 1;
    final lines = _wrap(label, labW);

    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      out.add(i == 0 ? lines[i].padRight(_w - value.length) + value : lines[i]);
    }
    return out;
  }

  List<int> _t(
      Generator g,
      String s, {
        bool bold = false,
        PosAlign align = PosAlign.left,
        PosTextSize size = PosTextSize.size1,
      }) {
    return g.text(
      _clean(s),
      styles: PosStyles(
        bold: bold,
        align: align,
        height: size,
        width: size,
      ),
    );
  }

  // ------------------------------------------------------------
  // ONE SLIP -> ESC/POS BYTES
  // ------------------------------------------------------------

  List<int> _slipBytes(Generator g, LabourDay ld) {
    final c = widget.calc;
    final mill = widget.mill;
    List<int> b = [];

    // HEADER
    if (mill.isNotEmpty) {
      for (final l in _wrap(mill, _w)) {
        b += _t(g, l, bold: true, align: PosAlign.center);
      }
    }
    b += _t(g, 'Daily labour slip', align: PosAlign.center);
    b += _t(g, fmtDay(c.day.date), align: PosAlign.center);
    b += g.hr(ch: '-');

    // LABOUR + CREW
    for (final l in _wrap(ld.labour.name, _w)) {
      b += _t(g, l, bold: true);
    }

    final crewNames = c.crew.map((x) => x.labour.name).join(', ');
    for (final l in _wrap('Crew (${c.crew.length}): $crewNames', _w)) {
      b += _t(g, l);
    }
    b += g.hr(ch: '-');

    // LINES
    for (final line in slipLines(c, ld)) {
      if (line.topLine) b += g.hr(ch: '-');

      for (final r in _row(line.label, line.value)) {
        b += _t(g, r, bold: line.bold);
      }

      if (line.sub != null) {
        for (final s in _wrap(line.sub!, _w - 2)) {
          b += _t(g, '  $s');
        }
      }
    }

    // NET PAY
    b += g.hr(ch: '=');
    b += _t(g, 'NET PAY', bold: true);
    b += _t(
      g,
      'Rs ${money(ld.payable)}',
      bold: true,
      align: PosAlign.right,
      size: PosTextSize.size2,
    );

    if (ld.newBal > 0) {
      b += g.hr(ch: '-');
      for (final l in _wrap(
          'Balance carried forward: Rs ${money(ld.newBal)}', _w)) {
        b += _t(g, l, bold: true);
      }
    }

    b += g.feed(4);
    return b;
  }

  // ------------------------------------------------------------
  // PRINT
  // ------------------------------------------------------------

  Future<void> _print(List<LabourDay> list) async {
    if (busy || list.isEmpty) return;

    setState(() => busy = true);

    try {
      if (!await PrintBluetoothThermal.connectionStatus) {
        setState(() => connectedMac = null);
        _toast('Printer not connected. Tap a printer below to connect.');
        return;
      }

      final profile = await CapabilityProfile.load();
      final g = Generator(PaperSize.mm58, profile);

      for (final ld in list) {
        final bytes = <int>[...g.reset(), ..._slipBytes(g, ld)];
        final ok = await PrintBluetoothThermal.writeBytes(bytes);

        if (!ok) {
          _toast('Printing failed for ${ld.labour.name}');
          return;
        }

        await Future.delayed(const Duration(milliseconds: 600));
      }

      _toast('Sent to printer');
    } catch (e) {
      _toast('Print failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final connected = connectedMac != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Print via Bluetooth'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: (loading || busy) ? null : _loadDevices,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: connected
                  ? const Color(0xFFE8F5EE)
                  : const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  connected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_disabled_rounded,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    connected
                        ? 'Printer connected'
                        : 'Select your 58mm printer below',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message!),
            ),
          const SizedBox(height: 10),
          for (final d in devices)
            Card(
              child: ListTile(
                leading: const Icon(Icons.print_rounded),
                title: Text(d.name),
                subtitle: Text(d.macAdress),
                trailing: connectedMac == d.macAdress
                    ? const Icon(Icons.check_circle,
                    color: Color(0xFF1A6B3C))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: busy ? null : () => _connect(d),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('This slip'),
                  onPressed: (busy || !connected)
                      ? null
                      : () => _print([widget.labourDay]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.print_rounded),
                  label: Text('All (${widget.calc.crew.length})'),
                  onPressed: (busy || !connected)
                      ? null
                      : () => _print(widget.calc.crew),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}