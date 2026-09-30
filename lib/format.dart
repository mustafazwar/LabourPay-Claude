// Pure helpers: money, numbers, dates, CSV.

const _weekShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseYmd(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String fmtDay(String s) {
  final d = parseYmd(s);
  return '${_weekShort[d.weekday - 1]} ${d.day} ${_monShort[d.month - 1]} ${d.year}';
}

String fmtShort(String s) {
  final d = parseYmd(s);
  return '${_weekShort[d.weekday - 1]} ${d.day} ${_monShort[d.month - 1]}';
}

String fmtDate(String s) {
  final d = parseYmd(s);
  return '${d.day} ${_monShort[d.month - 1]} ${d.year}';
}

String fmtLong(DateTime d) =>
    '${_weekLong[d.weekday - 1]}, ${d.day} ${_monShort[d.month - 1]} ${d.year}';

String fmtMonthYear(String s) {
  final d = parseYmd(s);
  return '${_monLong[d.month - 1]} ${d.year}';
}

String fmtDateTime(String iso) {
  if (iso.isEmpty) return 'Never';
  final d = DateTime.tryParse(iso);
  if (d == null) return 'Never';
  final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
  final ap = d.hour >= 12 ? 'pm' : 'am';
  return '${d.day} ${_monShort[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} $ap';
}

String stamp() {
  final n = DateTime.now();
  return '${ymd(n)}_${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
}

String _group(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

/// Whole rupees with commas: 1300 -> "1,300"
String money(double v) {
  final r = v.abs().round();
  final g = _group(r.toString());
  return (v < 0 && r != 0) ? '-$g' : g;
}

String rs(double v) => 'Rs ${money(v)}';

/// Plain number without commas (for text fields): 250 -> "250", 2.5 -> "2.5"
String fmtNum(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// Quantity with commas: 1250 -> "1,250", 2.5 -> "2.5"
String fmtQty(double v) {
  final s = fmtNum(v);
  final neg = s.startsWith('-');
  final body = neg ? s.substring(1) : s;
  final parts = body.split('.');
  final g = _group(parts[0]);
  return '${neg ? '-' : ''}$g${parts.length > 1 ? '.${parts[1]}' : ''}';
}

double numOf(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

double dd(Object? v) => v == null ? 0.0 : (v as num).toDouble();
int ii(Object? v) => v == null ? 0 : (v as num).toInt();

String toCsv(List<List<Object?>> rows) {
  String cell(Object? v) {
    final s = '${v ?? ''}';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  return rows.map((r) => r.map(cell).join(',')).join('\n');
}
