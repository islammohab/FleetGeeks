import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'order_screen.dart';
import 'providers.dart';

/// Vehicle seen from above, front at the top. Zones keep their physical left / right meaning in both languages, so
/// the grid is always laid out left-to-right (the same zones as the Workshop Portal and the API whitelist).
const damageZones = [
  ['FrontLeft', 'Front', 'FrontRight'],
  ['LeftSide', 'Roof', 'RightSide'],
  ['RearLeft', 'Rear', 'RearRight'],
];
const damageTypes = ['Scratch', 'Dent', 'Crack', 'Missing', 'Other'];
const severities = ['Low', 'Medium', 'High', 'Critical'];

/// Damage map at reception / handover: tap a zone, pick the damage and severity, record it (through the outbox).
/// Pops `true` when the user also wants a photo of the damage (the order screen then opens the camera).
class DamageSheet extends ConsumerStatefulWidget {
  const DamageSheet({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<DamageSheet> createState() => _DamageSheetState();
}

class _DamageSheetState extends ConsumerState<DamageSheet> {
  String? _zone;
  String _type = 'Scratch';
  String _severity = 'Low';
  bool? _photo;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _record(bool photo) async {
    final s = ref.read(stringsProvider);
    await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit(
            '/workshop/service-orders/${Uri.encodeComponent(widget.orderId)}/damage',
            label: '${s.t('addDamage')} · ${widget.orderId} · ${s.status(_zone!)}',
            body: {'zone': _zone, 'damageType': _type, 'severity': _severity, 'note': _note.text.trim()},
          ),
    );
    ref.invalidate(orderProvider(widget.orderId));
    if (mounted) Navigator.of(context).pop(photo);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final online = ref.watch(connectivityProvider).value ?? true;
    final photo = _photo ?? online;
    final points = asRows(ref.watch(orderProvider(widget.orderId)).value?['damage']);

    Widget choices(String title, List<String> values, String selected, ValueChanged<String> onSelected) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.tt.titleSmall),
            const SizedBox(height: FgSpace.s2),
            Wrap(spacing: FgSpace.s2, runSpacing: FgSpace.s2, children: [
              for (final x in values)
                ChoiceChip(
                  label: Text(s.status(x)),
                  selected: selected == x,
                  onSelected: (_) {
                    FgHaptics.tap();
                    onSelected(x);
                  },
                ),
            ]),
          ],
        );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: FgSpace.gutter, right: FgSpace.gutter, bottom: MediaQuery.viewInsetsOf(context).bottom + FgSpace.s4),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const IconTile(FgIcons.damage, tone: FgTone.bad),
              const SizedBox(width: FgSpace.s3),
              Expanded(child: Text(s.t('damageMap'), style: context.tt.titleLarge)),
            ]),
            const SizedBox(height: FgSpace.s2),
            Text(s.t('damageMapHint'), style: context.tt.bodySmall),
            const SizedBox(height: FgSpace.s3),
            DamageMap(points: points, selected: _zone, onTap: (z) => setState(() => _zone = z)),
            const SizedBox(height: FgSpace.s4),
            choices(s.t('damageType'), damageTypes, _type, (v) => setState(() => _type = v)),
            const SizedBox(height: FgSpace.s3),
            choices(s.t('severity'), severities, _severity, (v) => setState(() => _severity = v)),
            const SizedBox(height: FgSpace.s3),
            TextField(controller: _note, decoration: InputDecoration(labelText: s.t('note'))),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: photo,
              onChanged: (v) => setState(() => _photo = v ?? false),
              secondary: const Icon(FgIcons.camera),
              title: Text(s.t('damagePhoto')),
              subtitle: online ? null : Text(s.t('needsNetwork')),
            ),
            const SizedBox(height: FgSpace.s2),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _zone == null ? null : () => _record(photo),
              icon: Icon(photo ? FgIcons.camera : FgIcons.check, size: 18),
              label: Text(_zone == null ? s.t('chooseZone') : s.t('addDamage')),
            ),
          ]),
        ),
      ),
    );
  }
}
