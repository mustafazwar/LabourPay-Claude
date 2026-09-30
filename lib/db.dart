import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'format.dart';

/// Screens listen to this and reload whenever data changes.
final ValueNotifier<int> dbTick = ValueNotifier<int>(0);
void notifyData() => dbTick.value = dbTick.value + 1;

const workTypes = ['milling', 'unload', 'load'];
String workLabel(String t) =>
    t == 'milling' ? 'Milling' : (t == 'unload' ? 'Unload' : (t == 'load' ? 'Load' : 'Tips'));

const _settingDefaults = <String, String>{
  'munn_kg': '40',
  'round': '1',
  'carry': '1',
  'mill_name': '',
  'pin': '',
  'lock_closed': '1',
  'auto_backup': '1',
  'last_backup': '',
  'tip_default': 'all',
};

// ------------------------------------------------------------------ models

class Labour {
  final int id;
  final String name;
  final String phone;
  final bool active;
  final double balance; // money he owes the mill (carried advance)
  final String? last; // last day worked (yyyy-MM-dd)
  Labour({
    required this.id,
    required this.name,
    this.phone = '',
    this.active = true,
    this.balance = 0,
    this.last,
  });
  factory Labour.from(Map<String, Object?> m) => Labour(
        id: ii(m['id']),
        name: (m['name'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        active: ii(m['active'] ?? 1) == 1,
        balance: dd(m['balance']),
        last: m['last'] as String?,
      );
}

class DayRow {
  final int id;
  final String date;
  final String status; // open | closed | paid
  DayRow(this.id, this.date, this.status);
}

class DaySummary {
  final int id;
  final String date;
  final String status;
  final int crew;
  final double work;
  final double tips;
  final double adv;
  DaySummary({
    required this.id,
    required this.date,
    required this.status,
    required this.crew,
    required this.work,
    required this.tips,
    required this.adv,
  });
  double get pool => work + tips;
}

class WorkEntry {
  final int? id;
  final int dayId;
  final String material;
  final String type;
  final double bags;
  final double kgPerBag;
  final double munn;
  final double rate;
  final double amount;
  final String party;
  WorkEntry({
    this.id,
    required this.dayId,
    required this.material,
    required this.type,
    required this.bags,
    required this.kgPerBag,
    required this.munn,
    required this.rate,
    required this.amount,
    this.party = '',
  });
  factory WorkEntry.from(Map<String, Object?> m) => WorkEntry(
        id: ii(m['id']),
        dayId: ii(m['day_id']),
        material: (m['material_name'] ?? '') as String,
        type: (m['work_type'] ?? 'unload') as String,
        bags: dd(m['bags']),
        kgPerBag: dd(m['kg_per_bag']),
        munn: dd(m['munn']),
        rate: dd(m['rate_used']),
        amount: dd(m['amount']),
        party: (m['party'] ?? '') as String,
      );
  Map<String, Object?> toMap() => {
        'day_id': dayId,
        'material_name': material,
        'work_type': type,
        'bags': bags,
        'kg_per_bag': kgPerBag,
        'munn': munn,
        'rate_used': rate,
        'amount': amount,
        'party': party,
      };
}

class TipRow {
  final int? id;
  final int dayId;
  final double amount;
  final String from;
  final List<int> labourIds; // empty = everyone present
  TipRow({this.id, required this.dayId, required this.amount, this.from = '', this.labourIds = const []});
  factory TipRow.from(Map<String, Object?> m) {
    final raw = (m['labour_ids'] ?? '') as String;
    final ids = raw.isEmpty ? <int>[] : raw.split(',').map((e) => int.parse(e)).toList();
    return TipRow(
      id: ii(m['id']),
      dayId: ii(m['day_id']),
      amount: dd(m['amount']),
      from: (m['from_name'] ?? '') as String,
      labourIds: ids,
    );
  }
}

class AdvanceRow {
  final int? id;
  final int dayId;
  final int labourId;
  final String labourName;
  final double amount;
  final String note;
  final String date;
  AdvanceRow({
    this.id,
    required this.dayId,
    required this.labourId,
    this.labourName = '',
    required this.amount,
    this.note = '',
    this.date = '',
  });
  factory AdvanceRow.from(Map<String, Object?> m) => AdvanceRow(
        id: ii(m['id']),
        dayId: ii(m['day_id']),
        labourId: ii(m['labour_id']),
        labourName: (m['name'] ?? '') as String,
        amount: dd(m['amount']),
        note: (m['note'] ?? '') as String,
        date: (m['date'] ?? '') as String,
      );
}

class MaterialRate {
  final int id;
  final String name;
  final double? rate;
  final String? since;
  MaterialRate(this.id, this.name, this.rate, this.since);
}

class LabourDay {
  final Labour labour;
  final double weight;
  final double workShare;
  final double tipShare;
  final double earned;
  final double advance;
  final double prevBal;
  final double payable;
  final double newBal;
  final Map<String, double> byType;
  LabourDay({
    required this.labour,
    required this.weight,
    required this.workShare,
    required this.tipShare,
    required this.earned,
    required this.advance,
    required this.prevBal,
    required this.payable,
    required this.newBal,
    required this.byType,
  });
  double get net => earned - advance - prevBal;
}

class DayCalc {
  final DayRow day;
  final List<WorkEntry> work;
  final List<TipRow> tips;
  final List<AdvanceRow> advances;
  final List<LabourDay> crew;
  final double workTotal;
  final double tipTotal;
  final double advTotal;
  final double totalWeight;
  DayCalc({
    required this.day,
    required this.work,
    required this.tips,
    required this.advances,
    required this.crew,
    required this.workTotal,
    required this.tipTotal,
    required this.advTotal,
    required this.totalWeight,
  });
  double get pool => workTotal + tipTotal;
  double get perHead => totalWeight > 0 ? pool / totalWeight : 0;
  double get totalPayable {
    double s = 0;
    for (final l in crew) {
      s += l.payable;
    }
    return s;
  }

  bool get locked => day.status != 'open';
  bool get allFull {
    for (final l in crew) {
      if (l.weight != 1) return false;
    }
    return true;
  }
}

class LedgerRow {
  final DayRow day;
  final LabourDay ld;
  LedgerRow(this.day, this.ld);
}

class ReportRow {
  final Labour labour;
  int days = 0;
  double earned = 0;
  double workShare = 0;
  double tipShare = 0;
  double advance = 0;
  double net = 0;
  final Map<String, double> byType = {};
  ReportRow(this.labour);
  double earnedFor(String type) => type == 'all' ? earned : (byType[type] ?? 0.0);
}

class Report {
  int days = 0;
  double work = 0;
  double tips = 0;
  double adv = 0;
  double net = 0;
  final Map<String, double> byType = {'milling': 0, 'unload': 0, 'load': 0, 'tips': 0};
  List<ReportRow> rows = [];
}

// ------------------------------------------------------------------ database

class Db {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<String> dbPath() async => p.join(await getDatabasesPath(), 'labour_pay.db');

  static Future<Database> _open() async {
    final path = await dbPath();
    return openDatabase(
      path,
      version: 1,
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (d, v) async {
        await d.execute(
            'CREATE TABLE labour(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT DEFAULT \'\', active INTEGER DEFAULT 1, balance REAL DEFAULT 0)');
        await d.execute(
            'CREATE TABLE day(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE, status TEXT NOT NULL DEFAULT \'open\', note TEXT DEFAULT \'\')');
        await d.execute(
            'CREATE TABLE day_labour(id INTEGER PRIMARY KEY AUTOINCREMENT, day_id INTEGER NOT NULL REFERENCES day(id) ON DELETE CASCADE, labour_id INTEGER NOT NULL REFERENCES labour(id), weight REAL DEFAULT 1, bal_before REAL DEFAULT 0, bal_after REAL DEFAULT 0, net_paid REAL DEFAULT 0, paid INTEGER DEFAULT 0, UNIQUE(day_id, labour_id))');
        await d.execute('CREATE TABLE material(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
        await d.execute(
            'CREATE TABLE rate(id INTEGER PRIMARY KEY AUTOINCREMENT, material_id INTEGER NOT NULL REFERENCES material(id) ON DELETE CASCADE, work_type TEXT NOT NULL, per_munn REAL NOT NULL, effective_from TEXT NOT NULL)');
        await d.execute(
            'CREATE TABLE work_entry(id INTEGER PRIMARY KEY AUTOINCREMENT, day_id INTEGER NOT NULL REFERENCES day(id) ON DELETE CASCADE, material_name TEXT, work_type TEXT, bags REAL, kg_per_bag REAL, munn REAL, rate_used REAL, amount REAL, party TEXT DEFAULT \'\')');
        await d.execute(
            'CREATE TABLE tip(id INTEGER PRIMARY KEY AUTOINCREMENT, day_id INTEGER NOT NULL REFERENCES day(id) ON DELETE CASCADE, amount REAL, from_name TEXT DEFAULT \'\', labour_ids TEXT DEFAULT \'\')');
        await d.execute(
            'CREATE TABLE advance(id INTEGER PRIMARY KEY AUTOINCREMENT, day_id INTEGER NOT NULL REFERENCES day(id) ON DELETE CASCADE, labour_id INTEGER NOT NULL, amount REAL, note TEXT DEFAULT \'\')');
        await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');

        const milling = <String, double>{'Wheat': 25, 'Maize': 20, 'Bajra': 22, 'Gram': 30};
        for (final e in milling.entries) {
          final id = await d.insert('material', {'name': e.key});
          await d.insert('rate', {'material_id': id, 'work_type': 'milling', 'per_munn': e.value, 'effective_from': '2000-01-01'});
          await d.insert('rate', {'material_id': id, 'work_type': 'unload', 'per_munn': 5.0, 'effective_from': '2000-01-01'});
          await d.insert('rate', {'material_id': id, 'work_type': 'load', 'per_munn': 5.0, 'effective_from': '2000-01-01'});
        }
      },
    );
  }

  // ---------------------------------------------------------------- settings

  static Future<String> setting(String key) async {
    final d = await db;
    final r = await d.query('settings', where: 'key = ?', whereArgs: [key]);
    if (r.isEmpty) return _settingDefaults[key] ?? '';
    return (r.first['value'] ?? '') as String;
  }

  static Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, String>> allSettings() async {
    final out = Map<String, String>.from(_settingDefaults);
    final d = await db;
    final r = await d.query('settings');
    for (final row in r) {
      out['${row['key']}'] = '${row['value'] ?? ''}';
    }
    return out;
  }

  // ---------------------------------------------------------------- labour

  static const _labourSql =
      'SELECT l.id AS id, l.name AS name, l.phone AS phone, l.active AS active, l.balance AS balance, '
      '(SELECT MAX(d.date) FROM day d JOIN day_labour dl ON dl.day_id = d.id WHERE dl.labour_id = l.id) AS last '
      'FROM labour l';

  static Future<List<Labour>> labours({bool activeOnly = false}) async {
    final d = await db;
    final rows = await d.rawQuery(
        '$_labourSql ${activeOnly ? 'WHERE l.active = 1' : ''} ORDER BY l.name COLLATE NOCASE');
    return rows.map((r) => Labour.from(r)).toList();
  }

  static Future<Labour?> labourById(int id) async {
    final d = await db;
    final rows = await d.rawQuery('$_labourSql WHERE l.id = ?', [id]);
    if (rows.isEmpty) return null;
    return Labour.from(rows.first);
  }

  static Future<int> addLabour(String name, {String phone = ''}) async {
    final d = await db;
    final id = await d.insert('labour', {'name': name.trim(), 'phone': phone.trim(), 'active': 1, 'balance': 0});
    notifyData();
    return id;
  }

  static Future<void> updateLabour(int id, {required String name, String phone = '', bool active = true}) async {
    final d = await db;
    await d.update('labour', {'name': name.trim(), 'phone': phone.trim(), 'active': active ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    notifyData();
  }

  /// Returns false when the labour has history (then only deactivate).
  static Future<bool> deleteLabour(int id) async {
    final d = await db;
    final r = await d.query('day_labour', where: 'labour_id = ?', whereArgs: [id], limit: 1);
    if (r.isNotEmpty) return false;
    await d.delete('labour', where: 'id = ?', whereArgs: [id]);
    notifyData();
    return true;
  }

  // ---------------------------------------------------------------- days

  static Future<DayRow?> dayByDate(String date) async {
    final d = await db;
    final r = await d.query('day', where: 'date = ?', whereArgs: [date]);
    if (r.isEmpty) return null;
    return DayRow(ii(r.first['id']), r.first['date'] as String, r.first['status'] as String);
  }

  static Future<DayRow?> dayById(int id) async {
    final d = await db;
    final r = await d.query('day', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return null;
    return DayRow(ii(r.first['id']), r.first['date'] as String, r.first['status'] as String);
  }

  static Future<List<DayRow>> openDaysBefore(String date) async {
    final d = await db;
    final r = await d.query('day', where: "status = 'open' AND date < ?", whereArgs: [date], orderBy: 'date DESC');
    return r.map((x) => DayRow(ii(x['id']), x['date'] as String, x['status'] as String)).toList();
  }

  static Future<int> createDay(String date, Map<int, double> crew) async {
    final d = await db;
    final id = await d.insert('day', {'date': date, 'status': 'open'});
    for (final e in crew.entries) {
      await d.insert('day_labour', {'day_id': id, 'labour_id': e.key, 'weight': e.value});
    }
    notifyData();
    return id;
  }

  static Future<Map<int, double>> crewOf(int dayId) async {
    final d = await db;
    final r = await d.query('day_labour', where: 'day_id = ?', whereArgs: [dayId]);
    final out = <int, double>{};
    for (final x in r) {
      out[ii(x['labour_id'])] = dd(x['weight']);
    }
    return out;
  }

  static Future<Map<int, double>> lastCrewBefore(String date) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT d.id AS id FROM day d WHERE d.date < ? AND EXISTS (SELECT 1 FROM day_labour x WHERE x.day_id = d.id) ORDER BY d.date DESC LIMIT 1',
        [date]);
    if (r.isEmpty) return {};
    final crew = await crewOf(ii(r.first['id']));
    return crew.map((k, v) => MapEntry(k, 1.0));
  }

  static Future<void> setCrew(int dayId, Map<int, double> crew) async {
    final d = await db;
    final cur = await crewOf(dayId);
    for (final id in cur.keys) {
      if (!crew.containsKey(id)) {
        await d.delete('advance', where: 'day_id = ? AND labour_id = ?', whereArgs: [dayId, id]);
        await d.delete('day_labour', where: 'day_id = ? AND labour_id = ?', whereArgs: [dayId, id]);
      }
    }
    for (final e in crew.entries) {
      if (cur.containsKey(e.key)) {
        await d.update('day_labour', {'weight': e.value},
            where: 'day_id = ? AND labour_id = ?', whereArgs: [dayId, e.key]);
      } else {
        await d.insert('day_labour', {'day_id': dayId, 'labour_id': e.key, 'weight': e.value});
      }
    }
    notifyData();
  }

  static Future<List<Labour>> crewLabours(int dayId) async {
    final d = await db;
    final rows = await d.rawQuery(
        '$_labourSql JOIN day_labour dl ON dl.labour_id = l.id WHERE dl.day_id = ? ORDER BY l.name COLLATE NOCASE',
        [dayId]);
    return rows.map((r) => Labour.from(r)).toList();
  }

  static Future<void> deleteDay(int id) async {
    final day = await dayById(id);
    if (day == null) return;
    if (day.status != 'open') await reopenDay(id);
    final d = await db;
    await d.delete('day', where: 'id = ?', whereArgs: [id]);
    notifyData();
  }

  static Future<List<DaySummary>> summaries({String? from, String? to, int? limit}) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT d.id AS id, d.date AS date, d.status AS status, '
        '(SELECT COUNT(*) FROM day_labour x WHERE x.day_id = d.id) AS crew, '
        '(SELECT IFNULL(SUM(amount),0) FROM work_entry w WHERE w.day_id = d.id) AS work, '
        '(SELECT IFNULL(SUM(amount),0) FROM tip t WHERE t.day_id = d.id) AS tips, '
        '(SELECT IFNULL(SUM(amount),0) FROM advance a WHERE a.day_id = d.id) AS adv '
        'FROM day d WHERE d.date >= ? AND d.date <= ? ORDER BY d.date DESC ${limit != null ? 'LIMIT $limit' : ''}',
        [from ?? '0000-01-01', to ?? '9999-12-31']);
    return rows
        .map((r) => DaySummary(
              id: ii(r['id']),
              date: r['date'] as String,
              status: r['status'] as String,
              crew: ii(r['crew']),
              work: dd(r['work']),
              tips: dd(r['tips']),
              adv: dd(r['adv']),
            ))
        .toList();
  }

  // ---------------------------------------------------------------- work / tips / advances

  static Future<List<WorkEntry>> workEntries(int dayId) async {
    final d = await db;
    final r = await d.query('work_entry', where: 'day_id = ?', whereArgs: [dayId], orderBy: 'id');
    return r.map((x) => WorkEntry.from(x)).toList();
  }

  static Future<void> saveWork(WorkEntry e) async {
    final d = await db;
    if (e.id == null) {
      await d.insert('work_entry', e.toMap());
    } else {
      await d.update('work_entry', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
    }
    notifyData();
  }

  static Future<void> deleteWork(int id) async {
    final d = await db;
    await d.delete('work_entry', where: 'id = ?', whereArgs: [id]);
    notifyData();
  }

  static Future<List<TipRow>> tipsOf(int dayId) async {
    final d = await db;
    final r = await d.query('tip', where: 'day_id = ?', whereArgs: [dayId], orderBy: 'id');
    return r.map((x) => TipRow.from(x)).toList();
  }

  static Future<void> saveTip(TipRow t) async {
    final d = await db;
    final m = {
      'day_id': t.dayId,
      'amount': t.amount,
      'from_name': t.from,
      'labour_ids': t.labourIds.join(','),
    };
    if (t.id == null) {
      await d.insert('tip', m);
    } else {
      await d.update('tip', m, where: 'id = ?', whereArgs: [t.id]);
    }
    notifyData();
  }

  static Future<void> deleteTip(int id) async {
    final d = await db;
    await d.delete('tip', where: 'id = ?', whereArgs: [id]);
    notifyData();
  }

  static Future<List<AdvanceRow>> advancesOf(int dayId) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT a.id AS id, a.day_id AS day_id, a.labour_id AS labour_id, a.amount AS amount, a.note AS note, l.name AS name, d.date AS date '
        'FROM advance a JOIN labour l ON l.id = a.labour_id JOIN day d ON d.id = a.day_id WHERE a.day_id = ? ORDER BY a.id',
        [dayId]);
    return r.map((x) => AdvanceRow.from(x)).toList();
  }

  static Future<List<AdvanceRow>> advancesFor(int labourId, String from, String to) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT a.id AS id, a.day_id AS day_id, a.labour_id AS labour_id, a.amount AS amount, a.note AS note, l.name AS name, d.date AS date '
        'FROM advance a JOIN labour l ON l.id = a.labour_id JOIN day d ON d.id = a.day_id '
        'WHERE a.labour_id = ? AND d.date >= ? AND d.date <= ? ORDER BY d.date DESC, a.id DESC',
        [labourId, from, to]);
    return r.map((x) => AdvanceRow.from(x)).toList();
  }

  static Future<void> saveAdvance(AdvanceRow a) async {
    final d = await db;
    final m = {'day_id': a.dayId, 'labour_id': a.labourId, 'amount': a.amount, 'note': a.note};
    if (a.id == null) {
      await d.insert('advance', m);
    } else {
      await d.update('advance', m, where: 'id = ?', whereArgs: [a.id]);
    }
    notifyData();
  }

  static Future<void> deleteAdvance(int id) async {
    final d = await db;
    await d.delete('advance', where: 'id = ?', whereArgs: [id]);
    notifyData();
  }

  // ---------------------------------------------------------------- materials / rates

  static Future<List<String>> materialNames() async {
    final d = await db;
    final r = await d.query('material', orderBy: 'name COLLATE NOCASE');
    return r.map((x) => x['name'] as String).toList();
  }

  static Future<int> addMaterial(String name, {Map<String, double> rates = const {}}) async {
    final d = await db;
    final ex = await d.query('material', where: 'name = ? COLLATE NOCASE', whereArgs: [name.trim()]);
    int id;
    if (ex.isNotEmpty) {
      id = ii(ex.first['id']);
    } else {
      id = await d.insert('material', {'name': name.trim()});
    }
    for (final e in rates.entries) {
      if (e.value > 0) {
        await d.insert('rate',
            {'material_id': id, 'work_type': e.key, 'per_munn': e.value, 'effective_from': '2000-01-01'});
      }
    }
    notifyData();
    return id;
  }

  static Future<List<MaterialRate>> rateTable(String type) async {
    final d = await db;
    final today = ymd(DateTime.now());
    final rows = await d.rawQuery(
        'SELECT m.id AS id, m.name AS name, r.per_munn AS per_munn, r.effective_from AS since FROM material m '
        'LEFT JOIN rate r ON r.id = (SELECT id FROM rate WHERE material_id = m.id AND work_type = ? AND effective_from <= ? '
        'ORDER BY effective_from DESC, id DESC LIMIT 1) ORDER BY m.name COLLATE NOCASE',
        [type, today]);
    return rows
        .map((r) => MaterialRate(
              ii(r['id']),
              r['name'] as String,
              r['per_munn'] == null ? null : dd(r['per_munn']),
              r['since'] as String?,
            ))
        .toList();
  }

  static Future<double?> currentRate(String material, String type, String date) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT r.per_munn AS v FROM rate r JOIN material m ON m.id = r.material_id '
        'WHERE m.name = ? AND r.work_type = ? AND r.effective_from <= ? ORDER BY r.effective_from DESC, r.id DESC LIMIT 1',
        [material, type, date]);
    if (r.isEmpty) return null;
    return dd(r.first['v']);
  }

  static Future<void> setRate(int materialId, String type, double rate, String from) async {
    final d = await db;
    await d.delete('rate',
        where: 'material_id = ? AND work_type = ? AND effective_from = ?', whereArgs: [materialId, type, from]);
    await d.insert('rate', {'material_id': materialId, 'work_type': type, 'per_munn': rate, 'effective_from': from});
    notifyData();
  }

  static Future<List<Map<String, Object?>>> rateHistory(int materialId, String type) async {
    final d = await db;
    return d.query('rate',
        where: 'material_id = ? AND work_type = ?',
        whereArgs: [materialId, type],
        orderBy: 'effective_from DESC, id DESC',
        limit: 6);
  }

  static Future<void> applyRateToDay(int dayId, String material, String type, double rate) async {
    final d = await db;
    await d.rawUpdate(
        'UPDATE work_entry SET rate_used = ?, amount = munn * ? WHERE day_id = ? AND material_name = ? AND work_type = ?',
        [rate, rate, dayId, material, type]);
    notifyData();
  }

  // ---------------------------------------------------------------- the calculation

  static Future<DayCalc> calc(int dayId) async {
    final d = await db;
    final dr = await d.query('day', where: 'id = ?', whereArgs: [dayId]);
    if (dr.isEmpty) throw Exception('Day not found');
    final day = DayRow(ii(dr.first['id']), dr.first['date'] as String, dr.first['status'] as String);
    final work = await workEntries(dayId);
    final tips = await tipsOf(dayId);
    final advs = await advancesOf(dayId);
    final rows = await d.rawQuery(
        'SELECT dl.labour_id AS labour_id, dl.weight AS weight, dl.bal_before AS bal_before, dl.bal_after AS bal_after, '
        'dl.net_paid AS net_paid, l.name AS name, l.phone AS phone, l.active AS active, l.balance AS balance '
        'FROM day_labour dl JOIN labour l ON l.id = dl.labour_id WHERE dl.day_id = ? ORDER BY l.name COLLATE NOCASE',
        [dayId]);
    final roundTo = int.tryParse(await setting('round')) ?? 1;
    final carry = (await setting('carry')) == '1';
    double rnd(double v) {
      if (roundTo <= 1) return v.roundToDouble();
      return (v / roundTo).round() * roundTo.toDouble();
    }

    final closed = day.status != 'open';
    double totalW = 0;
    for (final r in rows) {
      totalW += dd(r['weight']);
    }
    final typeTotal = <String, double>{'milling': 0, 'unload': 0, 'load': 0};
    double workTotal = 0;
    for (final w in work) {
      workTotal += w.amount;
      typeTotal[w.type] = (typeTotal[w.type] ?? 0.0) + w.amount;
    }
    double tipTotal = 0;
    for (final t in tips) {
      tipTotal += t.amount;
    }
    double advTotal = 0;
    for (final a in advs) {
      advTotal += a.amount;
    }
    final ids = rows.map((r) => ii(r['labour_id'])).toList();

    final crew = <LabourDay>[];
    for (final r in rows) {
      final id = ii(r['labour_id']);
      final w = dd(r['weight']);
      final lab = Labour(
        id: id,
        name: r['name'] as String,
        phone: (r['phone'] ?? '') as String,
        active: ii(r['active']) == 1,
        balance: dd(r['balance']),
      );
      final byType = <String, double>{};
      typeTotal.forEach((k, v) {
        byType[k] = totalW > 0 ? v * w / totalW : 0.0;
      });
      final workShare = totalW > 0 ? workTotal * w / totalW : 0.0;
      double tipShare = 0;
      for (final t in tips) {
        var rec = t.labourIds.where((x) => ids.contains(x)).toList();
        if (rec.isEmpty) rec = ids;
        if (rec.contains(id)) tipShare += t.amount / rec.length;
      }
      final earned = rnd(workShare + tipShare);
      double adv = 0;
      for (final a in advs) {
        if (a.labourId == id) adv += a.amount;
      }
      double prev;
      double payable;
      double newBal;
      if (closed) {
        prev = dd(r['bal_before']);
        payable = dd(r['net_paid']);
        newBal = dd(r['bal_after']);
      } else {
        prev = carry ? lab.balance : 0.0;
        final net = earned - adv - prev;
        payable = net > 0 ? net : 0.0;
        newBal = (carry && net < 0) ? -net : 0.0;
      }
      crew.add(LabourDay(
        labour: lab,
        weight: w,
        workShare: workShare,
        tipShare: tipShare,
        earned: earned,
        advance: adv,
        prevBal: prev,
        payable: payable,
        newBal: newBal,
        byType: byType,
      ));
    }
    return DayCalc(
      day: day,
      work: work,
      tips: tips,
      advances: advs,
      crew: crew,
      workTotal: workTotal,
      tipTotal: tipTotal,
      advTotal: advTotal,
      totalWeight: totalW,
    );
  }

  static Future<void> closeDay(int dayId, {bool markPaid = false}) async {
    final c = await calc(dayId);
    final carry = (await setting('carry')) == '1';
    final d = await db;
    await d.transaction((txn) async {
      for (final ld in c.crew) {
        await txn.update(
            'day_labour',
            {
              'bal_before': ld.prevBal,
              'bal_after': ld.newBal,
              'net_paid': ld.payable,
              'paid': markPaid ? 1 : 0,
            },
            where: 'day_id = ? AND labour_id = ?',
            whereArgs: [dayId, ld.labour.id]);
        if (carry) {
          await txn.update('labour', {'balance': ld.newBal}, where: 'id = ?', whereArgs: [ld.labour.id]);
        }
      }
      await txn.update('day', {'status': markPaid ? 'paid' : 'closed'}, where: 'id = ?', whereArgs: [dayId]);
    });
    notifyData();
  }

  static Future<void> reopenDay(int dayId) async {
    final d = await db;
    final rows = await d.query('day_labour', where: 'day_id = ?', whereArgs: [dayId]);
    final carry = (await setting('carry')) == '1';
    await d.transaction((txn) async {
      for (final r in rows) {
        if (carry) {
          await txn.update('labour', {'balance': dd(r['bal_before'])}, where: 'id = ?', whereArgs: [ii(r['labour_id'])]);
        }
      }
      await txn.update('day_labour', {'bal_before': 0, 'bal_after': 0, 'net_paid': 0, 'paid': 0},
          where: 'day_id = ?', whereArgs: [dayId]);
      await txn.update('day', {'status': 'open'}, where: 'id = ?', whereArgs: [dayId]);
    });
    notifyData();
  }

  static Future<void> setPaid(int dayId, bool paid) async {
    final d = await db;
    await d.update('day', {'status': paid ? 'paid' : 'closed'}, where: 'id = ?', whereArgs: [dayId]);
    await d.update('day_labour', {'paid': paid ? 1 : 0}, where: 'day_id = ?', whereArgs: [dayId]);
    notifyData();
  }

  // ---------------------------------------------------------------- ledger / reports

  static Future<List<LedgerRow>> ledger(int labourId, String from, String to) async {
    final d = await db;
    final days = await d.rawQuery(
        'SELECT d.id AS id FROM day d JOIN day_labour dl ON dl.day_id = d.id '
        'WHERE dl.labour_id = ? AND d.date >= ? AND d.date <= ? ORDER BY d.date DESC',
        [labourId, from, to]);
    final out = <LedgerRow>[];
    for (final r in days) {
      final c = await calc(ii(r['id']));
      for (final x in c.crew) {
        if (x.labour.id == labourId) out.add(LedgerRow(c.day, x));
      }
    }
    return out;
  }

  static Future<Report> report(String from, String to, {int? labourId}) async {
    final d = await db;
    final days = await d.query('day', where: 'date >= ? AND date <= ?', whereArgs: [from, to], orderBy: 'date');
    final rep = Report();
    final rows = <int, ReportRow>{};
    for (final dr in days) {
      final c = await calc(ii(dr['id']));
      var any = false;
      for (final ld in c.crew) {
        if (labourId != null && ld.labour.id != labourId) continue;
        any = true;
        final r = rows.putIfAbsent(ld.labour.id, () => ReportRow(ld.labour));
        r.days += 1;
        r.advance += ld.advance;
        r.net += ld.payable;
        r.earned += ld.earned;
        r.workShare += ld.workShare;
        r.tipShare += ld.tipShare;
        ld.byType.forEach((k, v) {
          r.byType[k] = (r.byType[k] ?? 0.0) + v;
        });
        r.byType['tips'] = (r.byType['tips'] ?? 0.0) + ld.tipShare;
      }
      if (any) rep.days += 1;
    }
    final list = rows.values.toList();
    list.sort((a, b) => a.labour.name.toLowerCase().compareTo(b.labour.name.toLowerCase()));
    for (final r in list) {
      rep.work += r.workShare;
      rep.tips += r.tipShare;
      rep.adv += r.advance;
      rep.net += r.net;
      r.byType.forEach((k, v) {
        rep.byType[k] = (rep.byType[k] ?? 0.0) + v;
      });
    }
    rep.rows = list;
    return rep;
  }

  static Future<List<List<Object?>>> csvRows({String? from, String? to, int? labourId}) async {
    final d = await db;
    final out = <List<Object?>>[
      ['Date', 'Labour', 'Work share', 'Tips share', 'Earned', 'Advance', 'Previous balance', 'Net pay', 'Status']
    ];
    final days = await d.query('day',
        where: 'date >= ? AND date <= ?', whereArgs: [from ?? '0000-01-01', to ?? '9999-12-31'], orderBy: 'date');
    for (final dr in days) {
      final c = await calc(ii(dr['id']));
      for (final ld in c.crew) {
        if (labourId != null && ld.labour.id != labourId) continue;
        out.add([
          c.day.date,
          ld.labour.name,
          ld.workShare.round(),
          ld.tipShare.round(),
          ld.earned.round(),
          ld.advance.round(),
          ld.prevBal.round(),
          ld.payable.round(),
          c.day.status,
        ]);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- backup / restore / import / export

  static Future<File> backupNow() async {
    final d = await db;
    try {
      await d.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}
    final dir = await getApplicationDocumentsDirectory();
    final bdir = Directory(p.join(dir.path, 'backups'));
    if (!await bdir.exists()) await bdir.create(recursive: true);
    final f = await File(await dbPath()).copy(p.join(bdir.path, 'labour_pay_${stamp()}.db'));
    final files = bdir.listSync().whereType<File>().toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    while (files.length > 7) {
      await files.removeAt(0).delete();
    }
    await setSetting('last_backup', DateTime.now().toIso8601String());
    return f;
  }

  static Future<void> restoreDb(String srcPath) async {
    // make sure it is a real Labour Pay database first
    final t = await openDatabase(srcPath, readOnly: true);
    try {
      await t.rawQuery('SELECT COUNT(*) FROM labour');
      await t.rawQuery('SELECT COUNT(*) FROM day');
    } finally {
      await t.close();
    }
    await backupNow();
    await _db?.close();
    _db = null;
    await File(srcPath).copy(await dbPath());
    notifyData();
  }

  static Future<Map<String, dynamic>> exportAll() async {
    final d = await db;
    final labours = await d.query('labour', orderBy: 'name COLLATE NOCASE');
    final nameOf = <int, String>{for (final l in labours) ii(l['id']): l['name'] as String};
    final mats = await d.query('material', orderBy: 'name COLLATE NOCASE');
    final rates = await d.rawQuery(
        'SELECT m.name AS material, r.work_type AS work_type, r.per_munn AS per_munn, r.effective_from AS effective_from '
        'FROM rate r JOIN material m ON m.id = r.material_id');
    final days = await d.query('day', orderBy: 'date');
    final outDays = <Map<String, dynamic>>[];
    for (final day in days) {
      final id = ii(day['id']);
      final crew = await d.rawQuery(
          'SELECT l.name AS name, dl.weight AS weight, dl.bal_before AS bal_before, dl.bal_after AS bal_after, dl.net_paid AS net_paid, dl.paid AS paid '
          'FROM day_labour dl JOIN labour l ON l.id = dl.labour_id WHERE dl.day_id = ?',
          [id]);
      final work = await workEntries(id);
      final tips = await tipsOf(id);
      final advs = await advancesOf(id);
      outDays.add({
        'date': day['date'],
        'status': day['status'],
        'crew': crew.map((r) => Map<String, Object?>.from(r)).toList(),
        'work': work
            .map((w) => {
                  'material': w.material,
                  'type': w.type,
                  'bags': w.bags,
                  'kg_per_bag': w.kgPerBag,
                  'munn': w.munn,
                  'rate': w.rate,
                  'amount': w.amount,
                  'party': w.party,
                })
            .toList(),
        'tips': tips
            .map((t) => {
                  'amount': t.amount,
                  'from': t.from,
                  'labours': t.labourIds.map((x) => nameOf[x] ?? '').where((n) => n.isNotEmpty).toList(),
                })
            .toList(),
        'advances': advs.map((a) => {'labour': a.labourName, 'amount': a.amount, 'note': a.note}).toList(),
      });
    }
    return {
      'app': 'labour_pay',
      'version': 1,
      'exported': DateTime.now().toIso8601String(),
      'labours': labours.map((r) => Map<String, Object?>.from(r)).toList(),
      'materials': mats.map((m) => m['name']).toList(),
      'rates': rates.map((r) => Map<String, Object?>.from(r)).toList(),
      'days': outDays,
    };
  }

  static Future<String> importAll(Map<String, dynamic> data, {required bool replace}) async {
    if (data['app'] != 'labour_pay') throw Exception('This file is not a Labour Pay export');
    if (replace) {
      await backupNow();
      final d0 = await db;
      for (final t in ['advance', 'tip', 'work_entry', 'day_labour', 'day', 'rate', 'material', 'labour']) {
        await d0.delete(t);
      }
    }
    final d = await db;
    var added = 0;
    var skipped = 0;
    await d.transaction((txn) async {
      Future<int> labourId(String name, {String phone = '', bool active = true, double balance = 0}) async {
        final r = await txn.query('labour', where: 'name = ? COLLATE NOCASE', whereArgs: [name]);
        if (r.isNotEmpty) return ii(r.first['id']);
        return txn.insert('labour', {'name': name, 'phone': phone, 'active': active ? 1 : 0, 'balance': balance});
      }

      Future<int> materialId(String name) async {
        final r = await txn.query('material', where: 'name = ? COLLATE NOCASE', whereArgs: [name]);
        if (r.isNotEmpty) return ii(r.first['id']);
        return txn.insert('material', {'name': name});
      }

      for (final l in ((data['labours'] as List?) ?? [])) {
        final m = Map<String, dynamic>.from(l as Map);
        await labourId('${m['name']}',
            phone: '${m['phone'] ?? ''}', active: ii(m['active'] ?? 1) == 1, balance: dd(m['balance']));
      }
      for (final n in ((data['materials'] as List?) ?? [])) {
        await materialId('$n');
      }
      for (final r in ((data['rates'] as List?) ?? [])) {
        final m = Map<String, dynamic>.from(r as Map);
        final mid = await materialId('${m['material']}');
        final ex = await txn.query('rate',
            where: 'material_id = ? AND work_type = ? AND effective_from = ?',
            whereArgs: [mid, '${m['work_type']}', '${m['effective_from']}']);
        if (ex.isEmpty) {
          await txn.insert('rate', {
            'material_id': mid,
            'work_type': '${m['work_type']}',
            'per_munn': dd(m['per_munn']),
            'effective_from': '${m['effective_from']}',
          });
        }
      }
      for (final dayAny in ((data['days'] as List?) ?? [])) {
        final day = Map<String, dynamic>.from(dayAny as Map);
        final date = '${day['date']}';
        final ex = await txn.query('day', where: 'date = ?', whereArgs: [date]);
        if (ex.isNotEmpty) {
          skipped++;
          continue;
        }
        final dayId = await txn.insert('day', {'date': date, 'status': '${day['status'] ?? 'closed'}'});
        for (final cAny in ((day['crew'] as List?) ?? [])) {
          final c = Map<String, dynamic>.from(cAny as Map);
          final lid = await labourId('${c['name']}');
          await txn.insert('day_labour', {
            'day_id': dayId,
            'labour_id': lid,
            'weight': dd(c['weight'] ?? 1),
            'bal_before': dd(c['bal_before']),
            'bal_after': dd(c['bal_after']),
            'net_paid': dd(c['net_paid']),
            'paid': ii(c['paid']),
          });
        }
        for (final wAny in ((day['work'] as List?) ?? [])) {
          final w = Map<String, dynamic>.from(wAny as Map);
          await txn.insert('work_entry', {
            'day_id': dayId,
            'material_name': '${w['material']}',
            'work_type': '${w['type']}',
            'bags': dd(w['bags']),
            'kg_per_bag': dd(w['kg_per_bag']),
            'munn': dd(w['munn']),
            'rate_used': dd(w['rate']),
            'amount': dd(w['amount']),
            'party': '${w['party'] ?? ''}',
          });
        }
        for (final tAny in ((day['tips'] as List?) ?? [])) {
          final t = Map<String, dynamic>.from(tAny as Map);
          final ids = <int>[];
          for (final n in ((t['labours'] as List?) ?? [])) {
            ids.add(await labourId('$n'));
          }
          await txn.insert('tip', {
            'day_id': dayId,
            'amount': dd(t['amount']),
            'from_name': '${t['from'] ?? ''}',
            'labour_ids': ids.join(','),
          });
        }
        for (final aAny in ((day['advances'] as List?) ?? [])) {
          final a = Map<String, dynamic>.from(aAny as Map);
          final lid = await labourId('${a['labour']}');
          await txn.insert('advance', {
            'day_id': dayId,
            'labour_id': lid,
            'amount': dd(a['amount']),
            'note': '${a['note'] ?? ''}',
          });
        }
        added++;
      }
    });
    notifyData();
    return 'Imported $added day(s)${skipped > 0 ? ', skipped $skipped that already exist' : ''}.';
  }
}
