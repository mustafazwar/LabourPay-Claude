import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';
import 'format.dart';

export 'db.dart';
export 'format.dart';

const kInk = Color(0xFF1B2740);
const kInk2 = Color(0xFF5A6680);
const kLine = Color(0xFFE2E6EC);
const kBg = Color(0xFFF2F4F7);
const kJute = Color(0xFFB9832F);
const kJuteBg = Color(0xFFF7EBD3);
const kJuteDk = Color(0xFF7A5316);
const kEarn = Color(0xFF1F7A57);
const kEarnBg = Color(0xFFDDF1E8);
const kAdv = Color(0xFFC0432F);
const kAdvBg = Color(0xFFFBE4DF);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kInk).copyWith(
    primary: kInk,
    onPrimary: Colors.white,
    secondary: kJute,
    onSecondary: Colors.white,
    error: kAdv,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kInk,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kJute,
      foregroundColor: Colors.white,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: kJuteBg,
    ),
  );
}

InputDecoration dec(String label, {String? prefix, String? suffix, String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      suffixText: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );

Future<T?> go<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext context, String title, String msg, {String ok = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(BuildContext context, String title,
    {String initial = '', String hint = '', bool number = false, bool obscure = false}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: obscure,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: dec(hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
  return r;
}

/// Asks for the PIN if one is set. Returns true when allowed to continue.
Future<bool> askPin(BuildContext context, {String title = 'Enter PIN'}) async {
  final pin = await Db.setting('pin');
  if (pin.isEmpty) return true;
  if (!context.mounted) return false;
  final v = await askText(context, title, hint: 'PIN', number: true, obscure: true);
  if (v == pin) return true;
  if (v != null && context.mounted) toast(context, 'Wrong PIN');
  return false;
}

/// PIN check only when "lock closed days" is on.
Future<bool> askPinIfLocked(BuildContext context) async {
  if ((await Db.setting('lock_closed')) != '1') return true;
  if (!context.mounted) return false;
  return askPin(context, title: 'Enter PIN to change a closed day');
}

Future<void> shareTextFile(String filename, String content) async {
  final dir = await getTemporaryDirectory();
  final f = File(p.join(dir.path, filename));
  await f.writeAsString(content);
  await Share.shareXFiles([XFile(f.path)]);
}

Future<void> shareFile(String path) async {
  await Share.shareXFiles([XFile(path)]);
}

// ------------------------------------------------------------------ widgets

/// Loads data, and reloads whenever the database changes.
class AsyncData<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  const AsyncData({super.key, required this.load, required this.builder});
  @override
  State<AsyncData<T>> createState() => _AsyncDataState<T>();
}

class _AsyncDataState<T> extends State<AsyncData<T>> {
  late Future<T> _f;

  @override
  void initState() {
    super.initState();
    _f = widget.load();
    dbTick.addListener(_reload);
  }

  void _reload() {
    if (mounted) setState(() => _f = widget.load());
  }

  @override
  void dispose() {
    dbTick.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Something went wrong:\n${snap.error}', textAlign: TextAlign.center),
          ));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return widget.builder(context, snap.data as T);
      },
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final bool dark;
  final double size;
  const Avatar(this.name, {super.key, this.dark = false, this.size = 38});
  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: dark ? kInk : kJuteBg,
      child: Text(
        t.isEmpty ? '?' : t[0].toUpperCase(),
        style: TextStyle(color: dark ? Colors.white : kJuteDk, fontWeight: FontWeight.w800, fontSize: size * 0.4),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const Pill(this.text, {super.key, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    if (status == 'open') return const Pill('Open', bg: kJuteBg, fg: kJuteDk);
    if (status == 'paid') return const Pill('Paid', bg: kEarnBg, fg: kEarn);
    return const Pill('Closed', bg: Color(0xFFE4E8EF), fg: kInk2);
  }
}

Widget sectionLabel(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk2)),
    );

Widget kv(String l, String v, {bool bold = false, Color? color, double size = 13.5}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
            child: Text(l,
                style: TextStyle(fontSize: size, color: bold ? kInk : kInk2, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
        Text(v,
            style: TextStyle(
                fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w700, color: color ?? kInk)),
      ]),
    );

Widget emptyState(String title, String sub) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(sub, style: const TextStyle(color: kInk2), textAlign: TextAlign.center),
        ]),
      ),
    );

/// White list row used everywhere.
Widget listRow({
  Widget? leading,
  required String title,
  String? sub,
  Widget? trailing,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) {
  return InkWell(
    onTap: onTap,
    onLongPress: onLongPress,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: kLine))),
      child: Row(children: [
        if (leading != null) ...[leading, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            if (sub != null && sub.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(sub, style: const TextStyle(fontSize: 12, color: kInk2)),
              ),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ]),
    ),
  );
}

Widget amountText(String v, {Color? color, double size = 14}) =>
    Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: size, color: color ?? kInk));

Widget editDeleteButtons({VoidCallback? onEdit, VoidCallback? onDelete}) => Row(mainAxisSize: MainAxisSize.min, children: [
      if (onEdit != null)
        IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.edit_outlined, size: 19, color: kInk2),
            onPressed: onEdit),
      if (onDelete != null)
        IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.delete_outline, size: 19, color: kAdv),
            onPressed: onDelete),
    ]);

/// Rounded chip used for filters.
Widget filterChip(String label, bool on, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        onSelected: (_) => onTap(),
        selectedColor: kInk,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(color: on ? Colors.white : kInk, fontWeight: FontWeight.w600, fontSize: 13),
        showCheckmark: false,
      ),
    );

/// Grey box with a light border.
Widget boxed({required Widget child, EdgeInsets? padding, Color? color}) => Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLine),
      ),
      child: child,
    );

/// TabBar that is readable on the dark app bar.
TabBar darkTabBar(TabController? c, List<String> labels) => TabBar(
      controller: c,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: kJute,
      indicatorWeight: 3,
      tabs: [for (final l in labels) Tab(text: l)],
    );
