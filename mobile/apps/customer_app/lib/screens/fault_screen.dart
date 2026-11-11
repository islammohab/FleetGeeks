import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'vehicles_screen.dart';

final symptomsProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async => asRows(await ref.watch(apiProvider).get('/lookups/symptoms')));

/// Fault report from the road. Works without signal: the report waits in the outbox and is sent once (Idempotency-Key).
class FaultScreen extends ConsumerStatefulWidget {
  const FaultScreen({super.key, this.vehicleId});
  final String? vehicleId;

  @override
  ConsumerState<FaultScreen> createState() => _FaultScreenState();
}

class _FaultScreenState extends ConsumerState<FaultScreen> {
  late String? _vehicle = widget.vehicleId;
  String? _symptom;
  final _complaint = TextEditingController();
  final _location = TextEditingController();
  bool _breakdown = false;
  bool _warning = false;
  bool _tried = false;

  @override
  void dispose() {
    _complaint.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = ref.read(stringsProvider);
    setState(() => _tried = true);
    if (_vehicle == null || _complaint.text.trim().isEmpty) {
      FgHaptics.warning();
      return;
    }
    await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit('/faults', label: '${s.t('reportFault')} $_vehicle', body: {
        'vehicleId': _vehicle,
        'complaint': _complaint.text.trim(),
        'symptom': _symptom,
        'breakdown': _breakdown,
        'warningLights': _warning,
        'location': _location.text.trim(),
        'latitude': 0,
        'longitude': 0,
      }),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final vehicles = ref.watch(vehiclesProvider);
    final symptoms = ref.watch(symptomsProvider).value ?? const <FgRow>[];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('reportFault')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        OfflineBanner(onOpenOutbox: () => context.push('/outbox')),
        FgActionBar(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _submit,
              icon: const Icon(FgIcons.send, size: 18),
              label: Text(s.t('submit')),
            ),
          ),
        ]),
      ]),
      body: AsyncBody(
        value: vehicles,
        onRetry: () => ref.invalidate(vehiclesProvider),
        builder: (vs) {
          _vehicle ??= vs.isEmpty ? null : vs.first.s('VehicleId');
          return ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
            FgNotice(tone: FgTone.info, icon: FgIcons.offline, message: s.t('faultOfflineHint')),
            const SizedBox(height: FgSpace.s4),
            DropdownButtonFormField<String>(
              initialValue: _vehicle,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.t('vehicle'), prefixIcon: const Icon(FgIcons.vehicles, size: 20)),
              items: [for (final v in vs) DropdownMenuItem(value: v.s('VehicleId'), child: Text(vehicleOption(v), overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _vehicle = v),
            ),
            const SizedBox(height: FgSpace.s4),
            if (symptoms.isNotEmpty) ...[
              Text(s.t('symptom'), style: context.tt.titleSmall),
              const SizedBox(height: FgSpace.s2),
              Wrap(spacing: FgSpace.s2, runSpacing: FgSpace.s2, children: [
                for (final x in symptoms)
                  ChoiceChip(
                    label: Text(s.lang == 'ar' && x.s('nameAr').isNotEmpty ? x.s('nameAr') : x.s('name')),
                    selected: _symptom == x.s('id'),
                    onSelected: (on) {
                      FgHaptics.tap();
                      setState(() => _symptom = on ? x.s('id') : null);
                    },
                  ),
              ]),
              const SizedBox(height: FgSpace.s4),
            ],
            TextField(
              controller: _complaint,
              maxLines: 4,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_tried) setState(() {});
              },
              decoration: InputDecoration(
                labelText: s.t('complaint'),
                alignLabelWithHint: true,
                errorText: _tried && _complaint.text.trim().isEmpty ? s.t('required') : null,
              ),
            ),
            const SizedBox(height: FgSpace.s3),
            Card(
              child: Column(children: [
                SwitchListTile(
                  value: _breakdown,
                  onChanged: (v) {
                    FgHaptics.tap();
                    setState(() => _breakdown = v);
                  },
                  secondary: IconTile(FgIcons.incident, tone: _breakdown ? FgTone.bad : FgTone.neutral, size: 40),
                  title: Text(s.t('breakdown')),
                ),
                const Divider(),
                SwitchListTile(
                  value: _warning,
                  onChanged: (v) {
                    FgHaptics.tap();
                    setState(() => _warning = v);
                  },
                  secondary: IconTile(FgIcons.warning, tone: _warning ? FgTone.attention : FgTone.neutral, size: 40),
                  title: Text(s.t('warningLights')),
                ),
              ]),
            ),
            const SizedBox(height: FgSpace.s3),
            TextField(
              controller: _location,
              decoration: InputDecoration(labelText: s.t('location'), prefixIcon: const Icon(FgIcons.location, size: 20)),
            ),
          ]);
        },
      ),
    );
  }
}
