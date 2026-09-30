import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'utils.dart';

// Import the file where these classes/functions exist.
import 'slip_screen.dart';

class PrintViaBluetooh extends StatefulWidget {
  final DayCalc calc;
  final LabourDay labourDay;
  final String mill;

  const PrintViaBluetooh({
    super.key,
    required this.calc,
    required this.labourDay,
    required this.mill,
  });

  @override
  State<PrintViaBluetooh> createState() =>
      _PrintViaBluetoohState();
}

class _PrintViaBluetoohState
    extends State<PrintViaBluetooh> {
  final List<BluetoothInfo> devices = [];

  BluetoothInfo? selectedPrinter;

  bool scanning = false;
  bool connecting = false;
  bool printing = false;
  bool connected = false;

  bool showCrew = false;
  bool showSignatures = true;
  bool showBalance = true;
  bool boldValues = true;

  double fontSize = 1.0;
  double lineSpacing = 1.0;

  @override
  void initState() {
    super.initState();
    _scan();
    _refreshConnectionStatus();
  }

  Future<void> _refreshConnectionStatus() async {
    try {
      final status = await PrintBluetoothThermal.connectionStatus;
      if (!mounted) return;
      setState(() {
        connected = status;
      });
    } catch (_) {
      // Connection status will be checked again when connecting/printing.
    }
  }

  @override
  void dispose() {
    // Do not disconnect here: the package uses a shared Bluetooth
    // connection, and disconnecting during route disposal can interrupt
    // another operation that is still using it.
    super.dispose();
  }

  // ----------------------------------------------------------
  // BLUETOOTH SCAN
  // ----------------------------------------------------------

  Future<void> _scan() async {
    if (scanning) return;

    setState(() {
      scanning = true;
      devices.clear();
    });

    try {
      final bluetoothEnabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!bluetoothEnabled) {
        if (!mounted) return;
        setState(() => scanning = false);
        _error('Turn on Bluetooth, then scan again.');
        return;
      }

      // print_bluetooth_thermal returns paired/bonded devices.
      // Pair your printer in Android Bluetooth settings first.
      final pairedDevices = await PrintBluetoothThermal.pairedBluetooths;

      if (!mounted) return;
      setState(() {
        devices
          ..clear()
          ..addAll(pairedDevices);
        scanning = false;
      });

      if (devices.isEmpty) {
        _error('No paired printers found. Pair your printer in Android Bluetooth settings first.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => scanning = false);
      _error('Could not load paired Bluetooth devices: $e');
    }
  }

  // ----------------------------------------------------------
  // CONNECT
  // ----------------------------------------------------------

  Future<void> _connect(BluetoothInfo device) async {
    final address = device.macAdress;

    if (address.isEmpty) {
      _error('This printer does not have a Bluetooth address.');
      return;
    }

    setState(() {
      connecting = true;
    });

    try {
      if (connected) {
        await PrintBluetoothThermal.disconnect;
      }

      final result = await PrintBluetoothThermal.connect(
        macPrinterAddress: address,
      );

      if (!mounted) return;

      setState(() {
        selectedPrinter = device;
        connected = result;
        connecting = false;
      });

      if (result) {
        _success('${device.name} connected');
      } else {
        _error('Could not connect to printer. Make sure it is paired and nearby.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        connecting = false;
        connected = false;
      });
      _error('Connection failed: $e');
    }
  }

  // ----------------------------------------------------------
  // PRINT
  // ----------------------------------------------------------

  Future<void> _print() async {
    if (!connected || selectedPrinter == null) {
      _error('Connect a printer first.');
      return;
    }

    setState(() {
      printing = true;
    });

    try {
      final isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) {
        if (mounted) {
          setState(() => connected = false);
        }
        _error('Printer disconnected. Connect it again.');
        return;
      }

      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      final bytes = _buildReceipt(generator);

      final result = await PrintBluetoothThermal.writeBytes(bytes);

      if (!mounted) return;

      if (result) {
        _success('Slip sent to printer.');
      } else {
        _error('Printer did not accept the print data.');
      }
    } catch (e) {
      if (!mounted) return;
      _error('Printing failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          printing = false;
        });
      }
    }
  }

  // ----------------------------------------------------------
  // ESC/POS RECEIPT
  // ----------------------------------------------------------

  List<int> _buildReceipt(
      Generator generator,
      ) {
    final List<int> bytes = [];

    final ld = widget.labourDay;
    final c = widget.calc;

    final lines = slipLines(
      c,
      ld,
    ).where((line) => showCrew || !line.label.toLowerCase().contains('crew')).toList();

    final scale = fontSize;

    PosStyles normal = PosStyles(
      fontType: PosFontType.fontA,
      height: _textSize(scale),
      width: PosTextSize.size1,
      bold: false,
      align: PosAlign.left,
    );

    PosStyles small = PosStyles(
      fontType: PosFontType.fontA,
      height: _textSize(scale),
      width: PosTextSize.size1,
      bold: false,
      align: PosAlign.left,
    );

    PosStyles bold = PosStyles(
      fontType: PosFontType.fontA,
      height: _textSize(scale),
      width: PosTextSize.size1,
      bold: true,
      align: PosAlign.left,
    );

    // --------------------------------------------------------
    // HEADER
    // --------------------------------------------------------

    bytes.addAll(
      generator.text(
        widget.mill.isEmpty
            ? 'DAILY LABOUR SLIP'
            : widget.mill.toUpperCase(),
        styles: bold.copyWith(
          align: PosAlign.center,
        ),
      ),
    );

    bytes.addAll(
      generator.text(
        fmtDay(c.day.date),
        styles: normal.copyWith(
          align: PosAlign.center,
        ),
      ),
    );

    bytes.addAll(
      generator.hr(
        len: 32,
      ),
    );

    // --------------------------------------------------------
    // LABOUR
    // --------------------------------------------------------

    bytes.addAll(
      generator.text(
        ld.labour.name,
        styles: PosStyles(
          bold: true,
          align: PosAlign.center,
          fontType: PosFontType.fontA,
          height: _textSize(scale),
          width: PosTextSize.size1,
        ),
      ),
    );

    if (showCrew) {
      final crew = c.crew
          .map((x) => x.labour.name)
          .join(', ');

      bytes.addAll(
        generator.text(
          'Crew: $crew',
          styles: small,
        ),
      );
    }

    bytes.addAll(
      generator.hr(
        len: 32,
      ),
    );

    // --------------------------------------------------------
    // DETAILS
    // --------------------------------------------------------

    for (final l in lines) {
      if (l.topLine) {
        bytes.addAll(
          generator.hr(
            len: 32,
          ),
        );
      }

      String label = l.label;

      if (l.sub != null) {
        bytes.addAll(
          generator.text(
            label,
            styles: PosStyles(
              bold: l.bold,
              height: _textSize(scale),
              width: PosTextSize.size1,
            ),
          ),
        );

        bytes.addAll(
          generator.text(
            l.sub!,
            styles: small,
          ),
        );
      } else {
        bytes.addAll(
          generator.row(
            [
              PosColumn(
                text: label,
                width: 8,
                styles: PosStyles(
                  bold: l.bold,
                  height: _textSize(scale),
                  width: PosTextSize.size1,
                ),
              ),
              PosColumn(
                text: l.value,
                width: 4,
                styles: PosStyles(
                  bold: boldValues || l.bold,
                  align: PosAlign.right,
                  height: _textSize(scale),
                  width: PosTextSize.size1,
                ),
              ),
            ],
          ),
        );
      }

      if (lineSpacing > 1) {
        bytes.addAll(
          generator.feed(
            lineSpacing.round() - 1,
          ),
        );
      }
    }

    // --------------------------------------------------------
    // NET PAY
    // --------------------------------------------------------

    bytes.addAll(
      generator.hr(
        len: 32,
      ),
    );

    bytes.addAll(
      generator.text(
        'NET PAY',
        styles: PosStyles(
          bold: true,
          align: PosAlign.center,
        ),
      ),
    );

    bytes.addAll(
      generator.text(
        'Rs ${money(ld.payable)}',
        styles: PosStyles(
          bold: true,
          align: PosAlign.center,
          height: _textSize(scale),
          width: PosTextSize.size1,
        ),
      ),
    );

    // --------------------------------------------------------
    // BALANCE
    // --------------------------------------------------------

    if (showBalance && ld.newBal > 0) {
      bytes.addAll(
        generator.text(
          'Balance carried forward:',
          styles: small.copyWith(
            align: PosAlign.center,
          ),
        ),
      );

      bytes.addAll(
        generator.text(
          'Rs ${money(ld.newBal)}',
          styles: bold.copyWith(
            align: PosAlign.center,
          ),
        ),
      );
    }

    // --------------------------------------------------------
    // SIGNATURES
    // --------------------------------------------------------

    if (showSignatures) {
      bytes.addAll(
        generator.feed(1),
      );

      bytes.addAll(
        generator.text(
          '________________    ________________',
          styles: small.copyWith(
            align: PosAlign.center,
          ),
        ),
      );

      bytes.addAll(
        generator.text(
          'Labour                  Munshi',
          styles: small.copyWith(
            align: PosAlign.center,
          ),
        ),
      );
    }

    bytes.addAll(
      generator.feed(2),
    );

    bytes.addAll(
      generator.cut(),
    );

    return bytes;
  }

  PosTextSize _textSize(double value) {
    if (value <= 0.85) {
      return PosTextSize.size1;
    }

    if (value >= 1.15) {
      return PosTextSize.size2;
    }

    return PosTextSize.size1;
  }

  // ----------------------------------------------------------
  // UI
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final printer = selectedPrinter;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Print via Bluetooth',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Scan again',
            onPressed: scanning ? null : _scan,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _slipHeader(),

          const SizedBox(height: 14),

          _connectionCard(printer),

          const SizedBox(height: 14),

          _customizationCard(),

          const SizedBox(height: 18),

          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed:
              connected && !printing
                  ? _print
                  : null,
              icon: printing
                  ? const SizedBox(
                width: 20,
                height: 20,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(
                Icons.print_rounded,
              ),
              label: Text(
                printing
                    ? 'Printing...'
                    : 'Print Slip',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            'Tip: Keep the font around 1.0× for the best '
                'balance between readability and paper usage.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _slipHeader() {
    final ld = widget.labourDay;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kEarnBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: kEarn,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected slip',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ld.labour.name,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Rs ${money(ld.payable)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kEarn,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionCard(
      BluetoothInfo? printer,
      ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(18),
        side: BorderSide(
          color: Colors.black.withOpacity(.07),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.bluetooth_rounded,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Bluetooth Printer',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (connected)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green
                          .withOpacity(.1),
                      borderRadius:
                      BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Connected',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight:
                        FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 14),

            if (scanning)
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Scanning for printers...'),
                ],
              )
            else if (devices.isEmpty)
              _emptyPrinters()
            else
              ...devices.map(
                    (device) =>
                    _printerTile(device),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyPrinters() {
    return Column(
      children: [
        const SizedBox(height: 8),

        Icon(
          Icons.print_disabled_rounded,
          size: 38,
          color: Colors.grey.shade400,
        ),

        const SizedBox(height: 8),

        const Text(
          'No Bluetooth printers found',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 4),

        const Text(
          'Turn on Bluetooth and make sure your '
              'thermal printer is powered on.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.black54,
          ),
        ),

        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: scanning ? null : _scan,
          icon: const Icon(
            Icons.bluetooth_searching,
          ),
          label: const Text('Scan again'),
        ),
      ],
    );
  }

  Widget _printerTile(
      BluetoothInfo device,
      ) {
    final isSelected =
        selectedPrinter?.macAdress ==
            device.macAdress;

    return Container(
      margin: const EdgeInsets.only(
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? kEarnBg
            : Colors.grey.shade50,
        borderRadius:
        BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSelected
              ? kEarn
              : Colors.white,
          child: Icon(
            Icons.print_rounded,
            color: isSelected
                ? Colors.white
                : Colors.black54,
          ),
        ),

        title: Text(
          device.name.isNotEmpty
              ? device.name
              : 'Unknown printer',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),

        subtitle: Text(
          device.macAdress.isNotEmpty ? device.macAdress : 'No address',
          style: const TextStyle(
            fontSize: 11,
          ),
        ),

        trailing: connecting &&
            isSelected
            ? const SizedBox(
          width: 22,
          height: 22,
          child:
          CircularProgressIndicator(
            strokeWidth: 2,
          ),
        )
            : FilledButton(
          onPressed:
          connected && isSelected
              ? null
              : () => _connect(
            device,
          ),
          child: Text(
            isSelected && connected
                ? 'Connected'
                : 'Connect',
          ),
        ),
      ),
    );
  }

  Widget _customizationCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(18),
        side: BorderSide(
          color: Colors.black.withOpacity(.07),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune_rounded),
                SizedBox(width: 8),
                Text(
                  'Slip customization',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Show crew names',
              ),
              subtitle: const Text(
                'Turn off to save paper',
              ),
              value: showCrew,
              onChanged: (v) {
                setState(() {
                  showCrew = v;
                });
              },
            ),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Show signatures',
              ),
              value: showSignatures,
              onChanged: (v) {
                setState(() {
                  showSignatures = v;
                });
              },
            ),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Show carried balance',
              ),
              value: showBalance,
              onChanged: (v) {
                setState(() {
                  showBalance = v;
                });
              },
            ),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Bold values',
              ),
              value: boldValues,
              onChanged: (v) {
                setState(() {
                  boldValues = v;
                });
              },
            ),

            const SizedBox(height: 4),

            Text(
              'Font size  '
                  '${fontSize.toStringAsFixed(2)}×',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),

            Slider(
              min: .75,
              max: 1.25,
              divisions: 10,
              value: fontSize,
              onChanged: (v) {
                setState(() {
                  fontSize = v;
                });
              },
            ),

            Text(
              'Line spacing  '
                  '${lineSpacing.toStringAsFixed(1)}×',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),

            Slider(
              min: 1,
              max: 2,
              divisions: 4,
              value: lineSpacing,
              onChanged: (v) {
                setState(() {
                  lineSpacing = v;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _success(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }

  void _error(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }
}
