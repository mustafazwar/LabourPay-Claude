import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'utils.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String last = '';
  bool auto = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    last = await Db.setting('last_backup');
    auto = (await Db.setting('auto_backup')) == '1';
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) toast(context, 'Failed: $e');
    }
    if (mounted) setState(() => busy = false);
    await _load();
  }

  Future<void> _backupNow() => _run(() async {
        final f = await Db.backupNow();
        await shareFile(f.path);
      });

  Future<void> _exportCsv() => _run(() async {
        final rows = await Db.csvRows();
        await shareTextFile('labour_pay_${ymd(DateTime.now())}.csv', toCsv(rows));
      });

  Future<void> _exportJson() => _run(() async {
        final data = await Db.exportAll();
        await shareTextFile('labour_pay_data_${ymd(DateTime.now())}.json', jsonEncode(data));
      });

  Future<void> _import() async {
    final List<PlatformFile>?  res = await FilePicker.pickFiles();
    if (res == null || res.isEmpty) return;
    final path = res.single.path;
    if (path == null) return;
    final lower = path.toLowerCase();
    if (!mounted) return;

    if (lower.endsWith('.db')) {
      final ok = await confirm(context, 'Restore this backup?',
          'ALL current data will be replaced by the backup file. A safety copy of the current data is saved first.',
          ok: 'Restore');
      if (!ok) return;
      await _run(() async {
        await Db.restoreDb(path);
        if (mounted) toast(context, 'Backup restored');
      });
      return;
    }

    if (lower.endsWith('.json')) {
      final mode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import data'),
          content: const Text(
              'Add to existing data: days that are not already in the app are added; days with the same date are skipped.\n\n'
              'Replace everything: deletes all current data first (a safety backup is saved).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('Add to existing')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('Replace all')),
          ],
        ),
      );
      if (mode == null) return;
      await _run(() async {
        final text = await File(path).readAsString();
        final data = jsonDecode(text) as Map<String, dynamic>;
        final msg = await Db.importAll(data, replace: mode == 'replace');
        if (mounted) toast(context, msg);
      });
      return;
    }

    toast(context, 'Choose a .json export or a .db backup file');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and data', style: TextStyle(fontWeight: FontWeight.w700))),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.only(bottom: 30), children: [
          sectionLabel('Backup'),
          listRow(
            leading: const Icon(Icons.storage_outlined),
            title: 'Back up now',
            sub: 'Last backup: ${fmtDateTime(last)}. Saves a copy and lets you send it to WhatsApp or Drive.',
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : _backupNow,
          ),
          Container(
            color: Colors.white,
            child: SwitchListTile(
              title: const Text('Automatic backup when a day is closed', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Keeps the last 7 copies on this phone'),
              value: auto,
              onChanged: (v) async {
                await Db.setSetting('auto_backup', v ? '1' : '0');
                setState(() => auto = v);
              },
            ),
          ),
          sectionLabel('Export'),
          listRow(
            leading: const Icon(Icons.table_chart_outlined),
            title: 'Excel-ready CSV',
            sub: 'One row per labour per day',
            trailing: const Icon(Icons.download_outlined),
            onTap: busy ? null : _exportCsv,
          ),
          listRow(
            leading: const Icon(Icons.data_object),
            title: 'Full data (.json)',
            sub: 'Everything, so it can be imported again',
            trailing: const Icon(Icons.download_outlined),
            onTap: busy ? null : _exportJson,
          ),
          listRow(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: 'PDF report',
            sub: 'Open the Reports tab, choose the dates, then tap the download icon',
          ),
          sectionLabel('Import'),
          listRow(
            leading: const Icon(Icons.upload_outlined),
            title: 'Choose file to import',
            sub: '.json export or a .db backup',
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : _import,
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kAdvBg, borderRadius: BorderRadius.circular(10)),
            child: const Text(
                'Restoring a .db backup or choosing Replace all deletes the current data. A safety copy is saved first.',
                style: TextStyle(color: kAdv, fontSize: 12.5)),
          ),
        ]),
        if (busy) const Positioned.fill(child: ColoredBox(color: Color(0x55FFFFFF), child: Center(child: CircularProgressIndicator()))),
      ]),
    );
  }
}
