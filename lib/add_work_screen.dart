import 'dart:core';

import 'package:flutter/material.dart';

import 'utils.dart';

class AddWorkScreen extends StatefulWidget {
  final int dayId;
  final String date;
  final WorkEntry? entry;

  const AddWorkScreen({
    super.key,
    required this.dayId,
    required this.date,
    this.entry,
  });

  @override
  State<AddWorkScreen> createState() => _AddWorkScreenState();
}

class _AddWorkScreenState extends State<AddWorkScreen> {
  String type = 'unload';
  String? material;
  List<String> materials = [];

  double kg = 100;
  bool otherKg = false;

// FIX: `override` is a Dart keyword, so use a different variable name.
  bool useCustomRate = false;

  double? tableRate;
  double munnKg = 40;
  bool ready = false;

  final bagsC = TextEditingController();
  final kgC = TextEditingController();
  final rateC = TextEditingController();
  final partyC = TextEditingController();

  static const kgChoices = [20.0, 40.0, 50.0, 100.0];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    bagsC.dispose();
    kgC.dispose();
    rateC.dispose();
    partyC.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    munnKg = numOf(await Db.setting('munn_kg'));

    if (munnKg <= 0) {
      munnKg = 40;
    }

    materials = await Db.materialNames();

    final e = widget.entry;

    if (e != null) {
      type = e.type;
      material = e.material;
      kg = e.kgPerBag;

      bagsC.text = fmtNum(e.bags);
      partyC.text = e.party;
      rateC.text = fmtNum(e.rate);

// FIXED
      useCustomRate = true;

      if (!materials.contains(e.material)) {
        materials.add(e.material);
      }

      if (!kgChoices.contains(kg)) {
        otherKg = true;
        kgC.text = fmtNum(kg);
      }
    } else {
      material = materials.isNotEmpty ? materials.first : null;
    }

    await _loadRate();

    if (mounted) {
      setState(() {
        ready = true;
      });
    }
  }

  Future<void> _loadRate() async {
    if (material == null) {
      tableRate = null;
    } else {
      tableRate = await Db.currentRate(
        material!,
        type,
        widget.date,
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  double get bags => numOf(bagsC.text);

  double get kgPer {
    return otherKg ? numOf(kgC.text) : kg;
  }

  double get munn {
    return munnKg > 0 ? bags * kgPer / munnKg : 0;
  }

// FIXED
  double get rate {
    return showRateField ? numOf(rateC.text) : (tableRate ?? 0);
  }

// FIXED
  bool get showRateField {
    return useCustomRate || tableRate == null;
  }

  double get amount {
    return munn * rate;
  }

  Future<void> _addMaterial() async {
    final name = await askText(
      context,
      'New material',
      hint: 'e.g. Rice',
    );

    if (name == null || name.isEmpty) {
      return;
    }

    await Db.addMaterial(name);

    materials = await Db.materialNames();
    material = name;

    await _loadRate();
  }

  Future<void> _save({bool more = false}) async {
    if (material == null) {
      toast(context, 'Choose a material');
      return;
    }

    if (bags <= 0) {
      toast(context, 'Enter the number of bags');
      return;
    }

    if (kgPer <= 0) {
      toast(context, 'Enter the bag size in kg');
      return;
    }

    if (rate <= 0) {
      toast(
        context,
        'Enter a rate. Set one in the Rates tab or type it here.',
      );
      return;
    }

    final e = WorkEntry(
      id: widget.entry?.id,
      dayId: widget.dayId,
      material: material!,
      type: type,
      bags: bags,
      kgPerBag: kgPer,
      munn: munn,
      rate: rate,
      amount: amount,
      party: partyC.text.trim(),
    );

    await Db.saveWork(e);

    if (!mounted) {
      return;
    }

    if (more && widget.entry == null) {
      bagsC.clear();
      partyC.clear();

      setState(() {});

      toast(
        context,
        'Saved. Add the next entry.',
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.entry != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          editing ? 'Edit work' : 'Add work',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: !ready
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
// ---------------------------------------------------------
// WORK TYPE
// ---------------------------------------------------------
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'milling',
                      label: Text('Milling'),
                    ),
                    ButtonSegment<String>(
                      value: 'unload',
                      label: Text('Unload'),
                    ),
                    ButtonSegment<String>(
                      value: 'load',
                      label: Text('Load'),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) {
                    setState(() {
                      type = s.first;
                    });

                    _loadRate();
                  },
                ),

                const SizedBox(height: 18),

// ---------------------------------------------------------
// MATERIAL
// ---------------------------------------------------------
                const Text(
                  'Material',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kInk2,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 6),

                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final m in materials)
                      ChoiceChip(
                        label: Text(m),
                        selected: material == m,
                        showCheckmark: false,
                        selectedColor: kInk,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: material == m ? Colors.white : kInk,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) {
                          setState(() {
                            material = m;
                          });

                          _loadRate();
                        },
                      ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.add,
                        size: 18,
                      ),
                      label: const Text('New'),
                      onPressed: _addMaterial,
                    ),
                  ],
                ),

                const SizedBox(height: 18),

// ---------------------------------------------------------
// BAG SIZE
// ---------------------------------------------------------
                const Text(
                  'Bag size',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kInk2,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 6),

                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final k in kgChoices)
                      ChoiceChip(
                        label: Text(
                          '${fmtNum(k)} kg',
                        ),
                        selected: !otherKg && kg == k,
                        showCheckmark: false,
                        selectedColor: kInk,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: !otherKg && kg == k ? Colors.white : kInk,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) {
                          setState(() {
                            otherKg = false;
                            kg = k;
                          });
                        },
                      ),
                    ChoiceChip(
                      label: const Text('Other'),
                      selected: otherKg,
                      showCheckmark: false,
                      selectedColor: kInk,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: otherKg ? Colors.white : kInk,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) {
                        setState(() {
                          otherKg = true;
                        });
                      },
                    ),
                  ],
                ),

                if (otherKg) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: kgC,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: dec(
                      'Bag size',
                      suffix: 'kg',
                    ),
                    onChanged: (_) {
                      setState(() {});
                    },
                  ),
                ],

                const SizedBox(height: 16),

// ---------------------------------------------------------
// NUMBER OF BAGS
// ---------------------------------------------------------
                TextField(
                  controller: bagsC,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: dec(
                    'Number of bags',
                    suffix: 'bags',
                  ),
                  onChanged: (_) {
                    setState(() {});
                  },
                ),

                const SizedBox(height: 14),

// ---------------------------------------------------------
// CALCULATION SUMMARY
// ---------------------------------------------------------
                boxed(
                  child: Column(
                    children: [
                      kv(
                        'Total weight',
                        '${fmtQty(bags * kgPer)} kg',
                      ),
                      kv(
                        'In munn (${fmtNum(munnKg)} kg)',
                        '${fmtQty(munn)} munn',
                      ),
                      kv(
                        tableRate == null ? 'Rate' : 'Rate from Rates tab',
                        tableRate == null
                            ? 'Not set'
                            : 'Rs ${fmtNum(tableRate!)} / munn',
                      ),
                    ],
                  ),
                ),

// ---------------------------------------------------------
// CUSTOM RATE SWITCH
// ---------------------------------------------------------
                if (tableRate != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Use a different rate for this entry',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: const Text(
                      'Only if today\'s deal is special',
                    ),

// FIXED
                    value: useCustomRate,

                    onChanged: (v) {
                      setState(() {
                        useCustomRate = v;

                        if (v) {
                          rateC.text = fmtNum(tableRate ?? 0);
                        }
                      });
                    },
                  ),

// ---------------------------------------------------------
// RATE FIELD
// ---------------------------------------------------------
                if (showRateField) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: rateC,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: dec(
                      'Rate per munn',
                      prefix: 'Rs ',
                    ),
                    onChanged: (_) {
                      setState(() {});
                    },
                  ),
                ],

                const SizedBox(height: 10),

// ---------------------------------------------------------
// PARTY / TRUCK
// ---------------------------------------------------------
                TextField(
                  controller: partyC,
                  decoration: dec(
                    'Truck or customer (optional)',
                  ),
                ),

                const SizedBox(height: 16),

// ---------------------------------------------------------
// AMOUNT
// ---------------------------------------------------------
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Amount',
                        style: TextStyle(
                          color: kInk2,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      rs(amount),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

// ---------------------------------------------------------
// SAVE BUTTONS
// ---------------------------------------------------------
                Row(
                  children: [
                    if (!editing)
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(14),
                          ),
                          onPressed: () => _save(
                            more: true,
                          ),
                          child: const Text(
                            'Save and add more',
                          ),
                        ),
                      ),
                    if (!editing) const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(14),
                        ),
                        onPressed: () => _save(),
                        child: Text(
                          editing ? 'Save changes' : 'Save entry',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
