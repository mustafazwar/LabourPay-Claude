import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import 'utils.dart';
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
  // ----------------------------------------------------------
  // PRINTER
  // ----------------------------------------------------------

  final List<BluetoothInfo> devices = [];

  BluetoothInfo? selectedPrinter;

  bool scanning = false;
  bool connecting = false;
  bool printing = false;
  bool connected = false;

  int? printerBattery;

  // ----------------------------------------------------------
  // PAPER
  // ----------------------------------------------------------

  PaperSize selectedPaper = PaperSize.mm58;

  int copies = 1;

  bool cutPaper = true;
  bool beepAfterPrint = false;

  int feedAfterPrint = 2;

  // ----------------------------------------------------------
  // SLIP OPTIONS
  // ----------------------------------------------------------

  bool showCrew = false;
  bool showSignatures = true;
  bool showBalance = true;
  bool boldValues = true;

  bool showDate = true;
  bool showMillName = true;
  bool showLabourName = true;
  bool showNetPay = true;

  bool compactMode = false;

  // ----------------------------------------------------------
  // TEXT
  // ----------------------------------------------------------

  double fontSize = 1.0;
  double lineSpacing = 1.0;

  PosFontType selectedFont = PosFontType.fontA;

  // ----------------------------------------------------------
  // INIT
  // ----------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _initializePrinter();
  }

  Future<void> _initializePrinter() async {
    await _checkPermission();
    await _scan();
    await _refreshConnectionStatus();
  }

  // ----------------------------------------------------------
  // PERMISSION
  // ----------------------------------------------------------

  Future<bool> _checkPermission() async {
    try {
      final granted =
      await PrintBluetoothThermal.isPermissionBluetoothGranted;

      if (!granted) {
        _error(
          'Bluetooth permission is required. '
              'Allow Nearby devices permission and try again.',
        );

        return false;
      }

      return true;
    } catch (e) {
      _error('Could not check Bluetooth permission: $e');
      return false;
    }
  }

  // ----------------------------------------------------------
  // CONNECTION STATUS
  // ----------------------------------------------------------

  Future<void> _refreshConnectionStatus() async {
    try {
      final status =
      await PrintBluetoothThermal.connectionStatus;

      if (!mounted) return;

      setState(() {
        connected = status;
      });

      if (status) {
        await _loadBattery();
      }
    } catch (_) {}
  }

  // ----------------------------------------------------------
  // BATTERY
  // ----------------------------------------------------------

  Future<void> _loadBattery() async {
    if (!connected) return;

    try {
      final battery =
      await PrintBluetoothThermal.batteryLevel;

      if (!mounted) return;

      setState(() {
        printerBattery = battery;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        printerBattery = null;
      });
    }
  }

  // ----------------------------------------------------------
  // SCAN
  // ----------------------------------------------------------

  Future<void> _scan() async {
    if (scanning) return;

    final permission = await _checkPermission();

    if (!permission) return;

    try {
      final bluetoothEnabled =
      await PrintBluetoothThermal.bluetoothEnabled;

      if (!bluetoothEnabled) {
        _error(
          'Turn on Bluetooth, then scan again.',
        );
        return;
      }

      if (!mounted) return;

      setState(() {
        scanning = true;
        devices.clear();
      });

      final pairedDevices =
      await PrintBluetoothThermal.pairedBluetooths;

      if (!mounted) return;

      setState(() {
        devices
          ..clear()
          ..addAll(pairedDevices);

        scanning = false;
      });

      if (devices.isEmpty) {
        _error(
          'No paired printers found. '
              'Pair your printer from Android Bluetooth settings first.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        scanning = false;
      });

      _error(
        'Could not load Bluetooth printers: $e',
      );
    }
  }

  // ----------------------------------------------------------
  // CONNECT
  // ----------------------------------------------------------

  Future<void> _connect(
      BluetoothInfo device,
      ) async {
    final address = device.macAdress;

    if (address.isEmpty) {
      _error(
        'This printer does not have a Bluetooth address.',
      );
      return;
    }

    if (connecting) return;

    setState(() {
      connecting = true;
    });

    try {
      if (connected) {
        await PrintBluetoothThermal.disconnect;
      }

      final result =
      await PrintBluetoothThermal.connect(
        macPrinterAddress: address,
      );

      if (!mounted) return;

      setState(() {
        connecting = false;
        connected = result;
        selectedPrinter = result ? device : null;
        printerBattery = null;
      });

      if (result) {
        await _loadBattery();

        _success(
          '${device.name.isEmpty ? 'Printer' : device.name} connected',
        );
      } else {
        _error(
          'Could not connect to printer. '
              'Make sure it is paired and nearby.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        connecting = false;
        connected = false;
        selectedPrinter = null;
      });

      _error(
        'Connection failed: $e',
      );
    }
  }

  // ----------------------------------------------------------
  // DISCONNECT
  // ----------------------------------------------------------

  Future<void> _disconnect() async {
    if (!connected) return;

    try {
      await PrintBluetoothThermal.disconnect;

      if (!mounted) return;

      setState(() {
        connected = false;
        selectedPrinter = null;
        printerBattery = null;
      });

      _success('Printer disconnected');
    } catch (e) {
      _error(
        'Could not disconnect printer: $e',
      );
    }
  }

  // ----------------------------------------------------------
  // TEST PRINT
  // ----------------------------------------------------------

  Future<void> _testPrint() async {
    if (!connected) {
      _error('Connect a printer first.');
      return;
    }

    try {
      final profile =
      await CapabilityProfile.load();

      final generator = Generator(
        selectedPaper,
        profile,
      );

      final width = _paperColumns;

      final bytes = <int>[];

      bytes.addAll(
        generator.text(
          'LABOUR PAY',
          styles: PosStyles(
            fontType: selectedFont,
            bold: true,
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      );

      bytes.addAll(
        generator.text(
          'Bluetooth Test Print',
          styles: PosStyles(
            fontType: selectedFont,
            align: PosAlign.center,
          ),
        ),
      );

      bytes.addAll(
        generator.hr(
          len: width,
        ),
      );

      bytes.addAll(
        generator.row(
          [
            PosColumn(
              text: 'Printer',
              width: 7,
              styles: PosStyles(
                fontType: selectedFont,
                bold: true,
              ),
            ),
            PosColumn(
              text: selectedPrinter?.name ??
                  'Unknown',
              width: 5,
              styles: PosStyles(
                fontType: selectedFont,
                align: PosAlign.right,
              ),
            ),
          ],
        ),
      );

      bytes.addAll(
        generator.row(
          [
            PosColumn(
              text: 'Paper',
              width: 7,
              styles: PosStyles(
                fontType: selectedFont,
              ),
            ),
            PosColumn(
              text: selectedPaper ==
                  PaperSize.mm58
                  ? '58 mm'
                  : '80 mm',
              width: 5,
              styles: PosStyles(
                fontType: selectedFont,
                align: PosAlign.right,
              ),
            ),
          ],
        ),
      );

      bytes.addAll(
        generator.text(
          'Bluetooth connection OK',
          styles: PosStyles(
            fontType: selectedFont,
            bold: true,
            align: PosAlign.center,
          ),
        ),
      );

      bytes.addAll(
        generator.feed(2),
      );

      if (beepAfterPrint) {
        bytes.addAll(
          generator.beep(
            n: 1,
          ),
        );
      }

      if (cutPaper) {
        bytes.addAll(
          generator.cut(),
        );
      }

      final result =
      await PrintBluetoothThermal.writeBytes(
        bytes,
      );

      if (!mounted) return;

      if (result) {
        _success('Test print sent successfully');
      } else {
        _error('Printer rejected the test print');
      }
    } catch (e) {
      _error(
        'Test print failed: $e',
      );
    }
  }

  // ----------------------------------------------------------
  // MAIN PRINT
  // ----------------------------------------------------------

  Future<void> _print() async {
    if (!connected ||
        selectedPrinter == null) {
      _error('Connect a printer first.');
      return;
    }

    if (printing) return;

    setState(() {
      printing = true;
    });

    try {
      final isConnected =
      await PrintBluetoothThermal.connectionStatus;

      if (!isConnected) {
        if (mounted) {
          setState(() {
            connected = false;
            selectedPrinter = null;
          });
        }

        _error(
          'Printer disconnected. Connect it again.',
        );

        return;
      }

      final profile =
      await CapabilityProfile.load();

      final generator = Generator(
        selectedPaper,
        profile,
      );

      final bytes = _buildReceipt(
        generator,
      );

      bool success = true;

      for (int i = 0; i < copies; i++) {
        final result =
        await PrintBluetoothThermal.writeBytes(
          bytes,
        );

        if (!result) {
          success = false;
          break;
        }

        if (i < copies - 1) {
          await Future.delayed(
            const Duration(
              milliseconds: 300,
            ),
          );
        }
      }

      if (!mounted) return;

      if (success) {
        _success(
          copies == 1
              ? 'Slip sent to printer'
              : '$copies copies sent to printer',
        );
      } else {
        _error(
          'Printer did not accept the print data.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      _error(
        'Printing failed: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          printing = false;
        });
      }
    }
  }

  // ----------------------------------------------------------
  // BUILD RECEIPT
  // ----------------------------------------------------------

  List<int> _buildReceipt(
      Generator generator,
      ) {
    final List<int> bytes = [];

    final ld = widget.labourDay;
    final c = widget.calc;

    final scale = fontSize;

    final lines = slipLines(
      c,
      ld,
    ).where(
          (line) {
        if (showCrew) return true;

        return !line.label
            .toLowerCase()
            .contains('crew');
      },
    ).toList();

    final normal = PosStyles(
      fontType: selectedFont,
      height: _textSize(scale),
      width: PosTextSize.size1,
      bold: false,
      align: PosAlign.left,
    );

    final small = PosStyles(
      fontType: selectedFont,
      height: _textSize(scale),
      width: PosTextSize.size1,
      bold: false,
      align: PosAlign.left,
    );

    final bold = PosStyles(
      fontType: selectedFont,
      height: _textSize(scale),
      width: PosTextSize.size1,
      bold: true,
      align: PosAlign.left,
    );

    // --------------------------------------------------------
    // HEADER
    // --------------------------------------------------------

    if (showMillName &&
        widget.mill.trim().isNotEmpty) {
      bytes.addAll(
        generator.text(
          widget.mill.toUpperCase(),
          styles: bold.copyWith(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      );
    } else {
      bytes.addAll(
        generator.text(
          'DAILY LABOUR SLIP',
          styles: bold.copyWith(
            align: PosAlign.center,
          ),
        ),
      );
    }

    if (showDate) {
      bytes.addAll(
        generator.text(
          fmtDay(c.day.date),
          styles: normal.copyWith(
            align: PosAlign.center,
          ),
        ),
      );
    }

    bytes.addAll(
      generator.hr(
        len: _paperColumns,
      ),
    );

    // --------------------------------------------------------
    // LABOUR
    // --------------------------------------------------------

    if (showLabourName) {
      bytes.addAll(
        generator.text(
          ld.labour.name,
          styles: PosStyles(
            fontType: selectedFont,
            bold: true,
            align: PosAlign.center,
            height: _textSize(scale),
            width: PosTextSize.size1,
          ),
        ),
      );
    }

    if (showCrew) {
      final crew = c.crew
          .map(
            (x) => x.labour.name,
      )
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
        len: _paperColumns,
      ),
    );

    // --------------------------------------------------------
    // DETAILS
    // --------------------------------------------------------

    for (final l in lines) {
      if (l.topLine && !compactMode) {
        bytes.addAll(
          generator.hr(
            len: _paperColumns,
          ),
        );
      }

      final label = l.label;

      if (l.sub != null) {
        bytes.addAll(
          generator.text(
            label,
            styles: PosStyles(
              fontType: selectedFont,
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
                  fontType: selectedFont,
                  bold: l.bold,
                  height: _textSize(scale),
                  width: PosTextSize.size1,
                ),
              ),
              PosColumn(
                text: l.value,
                width: 4,
                styles: PosStyles(
                  fontType: selectedFont,
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

      if (!compactMode &&
          lineSpacing > 1) {
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

    if (showNetPay) {
      bytes.addAll(
        generator.hr(
          len: _paperColumns,
        ),
      );

      bytes.addAll(
        generator.text(
          'NET PAY',
          styles: PosStyles(
            fontType: selectedFont,
            bold: true,
            align: PosAlign.center,
          ),
        ),
      );

      bytes.addAll(
        generator.text(
          'Rs ${money(ld.payable)}',
          styles: PosStyles(
            fontType: selectedFont,
            bold: true,
            align: PosAlign.center,
            height: _textSize(scale),
            width: PosTextSize.size2,
          ),
        ),
      );
    }

    // --------------------------------------------------------
    // BALANCE
    // --------------------------------------------------------

    if (showBalance &&
        ld.newBal > 0) {
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
        generator.feed(
          compactMode ? 0 : 1,
        ),
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

    // --------------------------------------------------------
    // END
    // --------------------------------------------------------

    bytes.addAll(
      generator.feed(
        feedAfterPrint,
      ),
    );

    if (beepAfterPrint) {
      bytes.addAll(
        generator.beep(
          n: 1,
        ),
      );
    }

    if (cutPaper) {
      bytes.addAll(
        generator.cut(),
      );
    }

    return bytes;
  }

  // ----------------------------------------------------------
  // PAPER WIDTH
  // ----------------------------------------------------------

  int get _paperColumns {
    if (selectedPaper == PaperSize.mm80) {
      return 48;
    }

    return 32;
  }

  // ----------------------------------------------------------
  // TEXT SIZE
  // ----------------------------------------------------------

  PosTextSize _textSize(
      double value,
      ) {
    if (value >= 1.15) {
      return PosTextSize.size2;
    }

    return PosTextSize.size1;
  }

  // ----------------------------------------------------------
  // UI
  // ----------------------------------------------------------

  @override
  Widget build(
      BuildContext context,
      ) {
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
          if (connected)
            IconButton(
              tooltip: 'Printer battery',
              onPressed: _loadBattery,
              icon: Icon(
                _batteryIcon(),
              ),
            ),
          IconButton(
            tooltip: 'Scan again',
            onPressed:
            scanning ? null : _scan,
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

          _paperCard(),

          const SizedBox(height: 14),

          _printOptionsCard(),

          const SizedBox(height: 14),

          _slipOptionsCard(),

          const SizedBox(height: 14),

          _textOptionsCard(),

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
                    : copies == 1
                    ? 'Print Slip'
                    : 'Print $copies Copies',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          OutlinedButton.icon(
            onPressed:
            connected && !printing
                ? _testPrint
                : null,
            icon: const Icon(
              Icons.receipt_long_rounded,
            ),
            label: const Text(
              'Test Print',
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'Bluetooth thermal printers must normally be paired '
                'from Android Bluetooth settings before they appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // HEADER
  // ----------------------------------------------------------

  Widget _slipHeader() {
    final ld = widget.labourDay;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kEarnBg,
        borderRadius:
        BorderRadius.circular(18),
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

  // ----------------------------------------------------------
  // CONNECTION CARD
  // ----------------------------------------------------------

  Widget _connectionCard(
      BluetoothInfo? printer,
      ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(18),
        side: BorderSide(
          color:
          Colors.black.withOpacity(.07),
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
                  _statusChip(
                    'Connected',
                    Colors.green,
                  ),
              ],
            ),

            const SizedBox(height: 14),

            if (connected &&
                printer != null)
              _connectedPrinter(
                printer,
              )
            else if (scanning)
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
                  Text(
                    'Loading paired printers...',
                  ),
                ],
              )
            else if (devices.isEmpty)
                _emptyPrinters()
              else
                ...devices.map(
                  _printerTile,
                ),
          ],
        ),
      ),
    );
  }

  Widget _connectedPrinter(
      BluetoothInfo printer,
      ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(.06),
        borderRadius:
        BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor:
            Colors.green.withOpacity(.12),
            child: const Icon(
              Icons.print_rounded,
              color: Colors.green,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  printer.name.isNotEmpty
                      ? printer.name
                      : 'Bluetooth Printer',
                  style: const TextStyle(
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  printer.macAdress,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          if (printerBattery != null)
            Column(
              children: [
                Icon(
                  _batteryIcon(),
                  size: 20,
                ),
                Text(
                  '$printerBattery%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),

          const SizedBox(width: 8),

          IconButton(
            tooltip: 'Disconnect',
            onPressed: _disconnect,
            icon: const Icon(
              Icons.link_off_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(
      String text,
      Color color,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.1),
        borderRadius:
        BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // PRINTER EMPTY
  // ----------------------------------------------------------

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
          'No paired printers found',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 4),

        const Text(
          'Pair your thermal printer in Android '
              'Bluetooth settings first.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.black54,
          ),
        ),

        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed:
          scanning ? null : _scan,
          icon: const Icon(
            Icons.bluetooth_searching,
          ),
          label: const Text(
            'Scan Again',
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // PRINTER TILE
  // ----------------------------------------------------------

  Widget _printerTile(
      BluetoothInfo device,
      ) {
    final isSelected =
        selectedPrinter?.macAdress ==
            device.macAdress;

    return Container(
      margin:
      const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? kEarnBg
            : Colors.grey.shade50,
        borderRadius:
        BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
          isSelected
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
          device.macAdress.isNotEmpty
              ? device.macAdress
              : 'No address',
          style: const TextStyle(
            fontSize: 11,
          ),
        ),

        trailing: connecting
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

  // ----------------------------------------------------------
  // PAPER CARD
  // ----------------------------------------------------------

  Widget _paperCard() {
    return _sectionCard(
      icon: Icons.straighten_rounded,
      title: 'Paper & Layout',
      children: [
        const Text(
          'Paper width',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 8),

        SegmentedButton<PaperSize>(
          segments: const [
            ButtonSegment(
              value: PaperSize.mm58,
              label: Text('58 mm'),
              icon: Icon(
                Icons.receipt_rounded,
              ),
            ),
            ButtonSegment(
              value: PaperSize.mm80,
              label: Text('80 mm'),
              icon: Icon(
                Icons.receipt_long_rounded,
              ),
            ),
          ],
          selected: {
            selectedPaper,
          },
          onSelectionChanged: (value) {
            setState(() {
              selectedPaper =
                  value.first;
            });
          },
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // PRINT OPTIONS
  // ----------------------------------------------------------

  Widget _printOptionsCard() {
    return _sectionCard(
      icon: Icons.person_add_alt_rounded,
      title: 'Print Options',
      children: [
        _switchTile(
          title: 'Cut paper',
          subtitle:
          'Cut the receipt after printing',
          value: cutPaper,
          onChanged: (v) {
            setState(() {
              cutPaper = v;
            });
          },
        ),

        _switchTile(
          title: 'Beep after printing',
          subtitle:
          'Printer buzzer after the job',
          value: beepAfterPrint,
          onChanged: (v) {
            setState(() {
              beepAfterPrint = v;
            });
          },
        ),

        const SizedBox(height: 6),

        _valueRow(
          title: 'Copies',
          value: '$copies',
          child: DropdownButton<int>(
            value: copies,
            underline: const SizedBox(),
            items: List.generate(
              5,
                  (index) {
                final value =
                    index + 1;

                return DropdownMenuItem(
                  value: value,
                  child: Text(
                    '$value',
                  ),
                );
              },
            ),
            onChanged: (v) {
              if (v == null) return;

              setState(() {
                copies = v;
              });
            },
          ),
        ),

        _valueRow(
          title: 'Feed after print',
          value: '$feedAfterPrint lines',
          child: DropdownButton<int>(
            value: feedAfterPrint,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                value: 0,
                child: Text('0'),
              ),
              DropdownMenuItem(
                value: 1,
                child: Text('1'),
              ),
              DropdownMenuItem(
                value: 2,
                child: Text('2'),
              ),
              DropdownMenuItem(
                value: 3,
                child: Text('3'),
              ),
              DropdownMenuItem(
                value: 4,
                child: Text('4'),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;

              setState(() {
                feedAfterPrint = v;
              });
            },
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // SLIP OPTIONS
  // ----------------------------------------------------------

  Widget _slipOptionsCard() {
    return _sectionCard(
      icon: Icons.receipt_long_rounded,
      title: 'Slip Content',
      children: [
        _switchTile(
          title: 'Show mill name',
          subtitle:
          'Print the mill name at the top',
          value: showMillName,
          onChanged: (v) {
            setState(() {
              showMillName = v;
            });
          },
        ),

        _switchTile(
          title: 'Show date',
          subtitle:
          'Print the working date',
          value: showDate,
          onChanged: (v) {
            setState(() {
              showDate = v;
            });
          },
        ),

        _switchTile(
          title: 'Show labour name',
          subtitle:
          'Print the labour name',
          value: showLabourName,
          onChanged: (v) {
            setState(() {
              showLabourName = v;
            });
          },
        ),

        _switchTile(
          title: 'Show crew names',
          subtitle:
          'Print all crew members',
          value: showCrew,
          onChanged: (v) {
            setState(() {
              showCrew = v;
            });
          },
        ),

        _switchTile(
          title: 'Show NET PAY',
          subtitle:
          'Print the final payable amount',
          value: showNetPay,
          onChanged: (v) {
            setState(() {
              showNetPay = v;
            });
          },
        ),

        _switchTile(
          title: 'Show carried balance',
          subtitle:
          'Print remaining labour balance',
          value: showBalance,
          onChanged: (v) {
            setState(() {
              showBalance = v;
            });
          },
        ),

        _switchTile(
          title: 'Show signatures',
          subtitle:
          'Labour and Munshi signature lines',
          value: showSignatures,
          onChanged: (v) {
            setState(() {
              showSignatures = v;
            });
          },
        ),

        _switchTile(
          title: 'Bold values',
          subtitle:
          'Make amount values heavier',
          value: boldValues,
          onChanged: (v) {
            setState(() {
              boldValues = v;
            });
          },
        ),

        _switchTile(
          title: 'Compact mode',
          subtitle:
          'Reduce separators and spacing',
          value: compactMode,
          onChanged: (v) {
            setState(() {
              compactMode = v;
            });
          },
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // TEXT OPTIONS
  // ----------------------------------------------------------

  Widget _textOptionsCard() {
    return _sectionCard(
      icon: Icons.text_fields_rounded,
      title: 'Text & Formatting',
      children: [
        const Text(
          'Printer font',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 8),

        SegmentedButton<PosFontType>(
          segments: const [
            ButtonSegment(
              value: PosFontType.fontA,
              label: Text('Font A'),
            ),
            ButtonSegment(
              value: PosFontType.fontB,
              label: Text('Font B'),
            ),
          ],
          selected: {
            selectedFont,
          },
          onSelectionChanged: (value) {
            setState(() {
              selectedFont =
                  value.first;
            });
          },
        ),

        const SizedBox(height: 18),

        Row(
          children: [
            const Expanded(
              child: Text(
                'Font size',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${fontSize.toStringAsFixed(2)}×',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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

        Row(
          children: [
            const Expanded(
              child: Text(
                'Line spacing',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${lineSpacing.toStringAsFixed(1)}×',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
    );
  }

  // ----------------------------------------------------------
  // GENERIC SECTION CARD
  // ----------------------------------------------------------

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(18),
        side: BorderSide(
          color:
          Colors.black.withOpacity(.07),
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
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            ...children,
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // SWITCH TILE
  // ----------------------------------------------------------

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  // ----------------------------------------------------------
  // VALUE ROW
  // ----------------------------------------------------------

  Widget _valueRow({
    required String title,
    required String value,
    required Widget child,
  }) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // BATTERY ICON
  // ----------------------------------------------------------

  IconData _batteryIcon() {
    if (printerBattery == null) {
      return Icons.battery_unknown_rounded;
    }

    if (printerBattery! <= 15) {
      return Icons.battery_0_bar_rounded;
    }

    if (printerBattery! <= 35) {
      return Icons.battery_2_bar_rounded;
    }

    if (printerBattery! <= 60) {
      return Icons.battery_4_bar_rounded;
    }

    if (printerBattery! <= 85) {
      return Icons.battery_5_bar_rounded;
    }

    return Icons.battery_full_rounded;
  }

  // ----------------------------------------------------------
  // SUCCESS
  // ----------------------------------------------------------

  void _success(
      String message,
      ) {
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

  // ----------------------------------------------------------
  // ERROR
  // ----------------------------------------------------------

  void _error(
      String message,
      ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
          Colors.red.shade700,
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }
}