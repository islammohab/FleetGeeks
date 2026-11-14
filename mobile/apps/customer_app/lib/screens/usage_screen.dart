import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'vehicles_screen.dart';

const incidentTypes = ['Accident', 'Theft', 'Vandalism', 'TrafficFine', 'Toll', 'Breakdown', 'Other'];

/// Driver's fuel receipt and incident report from the road. Both work without signal: they wait in the outbox and are
/// sent once (the same Idempotency-Key, and for fuel the same provider reference, so a retry never books twice).
class UsageScreen extends ConsumerStatefulWidget {
  const UsageScreen({super.key, this.vehicleId});
  final String? vehicleId;

  @override
  ConsumerState<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends ConsumerState<UsageScreen> {
  late String? _vehicle = widget.vehicleId;
  final _litres = TextEditingController();
  final _amount = TextEditingController();
  final _odometer = TextEditingController();
  final _station = TextEditingController();
  String _type = 'Accident';
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _reference = TextEditingController();
  bool _triedFuel = false;
  bool _triedIncident = false;

  @override
  void dispose() {
    for (final c in [_litres, _amount, _odometer, _station, _description, _location, _reference]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  Future<void> _saveFuel() async {
    final s = ref.read(stringsProvider);
    setState(() => _triedFuel = true);
    if (_vehicle == null || _num(_litres) <= 0) {
      FgHaptics.warning();
      return;
    }
    final key = const Uuid().v4();
    await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit('/fuel', key: key, label: '${s.t('recordFuel')} $_vehicle', body: {
        'vehicleId': _vehicle,
        'litres': _num(_litres),
        'amount': _num(_amount),
        'odometer': _num(_odometer),
        'station': _station.text.trim(),
        'whenUtc': DateTime.now().toUtc().toIso8601String(),
        'externalRef': key,
      }),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveIncident() async {
    final s = ref.read(stringsProvider);
    setState(() => _triedIncident = true);
    if (_vehicle == null || _description.text.trim().isEmpty) {
      FgHaptics.warning();
      return;
    }
    await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit('/incidents', label: '${s.t('reportIncident')} $_vehicle', body: {
        'vehicleId': _vehicle,
        'type': _type,
        'whenUtc': DateTime.now().toUtc().toIso8601String(),
        'location': _location.text.trim(),
        'description': _description.text.trim(),
        'reference': _reference.text.trim(),
        'amount': 0,
      }),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final vehicles = ref.watch(vehiclesProvider);
    const decimal = TextInputType.numberWithOptions(decimal: true);
    const tabular = TextStyle(fontFeatures: FgFonts.tabular);
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: Text(s.t('usage')),
            actions: [OutboxButton(onPressed: () => context.push('/outbox'))],
            bottom: TabBar(tabs: [
              Tab(icon: const Icon(FgIcons.fuel, size: 20), text: s.t('recordFuel')),
              Tab(icon: const Icon(FgIcons.incident, size: 20), text: s.t('reportIncident')),
            ]),
          ),
          bottomNavigationBar: OfflineBanner(safeArea: true, onOpenOutbox: () => context.push('/outbox')),
          body: AsyncBody(
            value: vehicles,
            onRetry: () => ref.invalidate(vehiclesProvider),
            builder: (vs) {
              _vehicle ??= vs.isEmpty ? null : vs.first.s('VehicleId');
              Widget picker() => DropdownButtonFormField<String>(
                    initialValue: _vehicle,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: s.t('vehicle'), prefixIcon: const Icon(FgIcons.vehicles, size: 20)),
                    items: [for (final v in vs) DropdownMenuItem(value: v.s('VehicleId'), child: Text(vehicleOption(v), overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _vehicle = v),
                  );
              return TabBarView(children: [
                ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
                  picker(),
                  const SizedBox(height: FgSpace.s3),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _litres,
                        keyboardType: decimal,
                        style: tabular,
                        onChanged: (_) {
                          if (_triedFuel) setState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: s.t('litres'),
                          suffixText: 'L',
                          errorText: _triedFuel && _num(_litres) <= 0 ? s.t('required') : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: FgSpace.s3),
                    Expanded(child: TextField(controller: _amount, keyboardType: decimal, style: tabular, decoration: InputDecoration(labelText: s.t('amount')))),
                  ]),
                  const SizedBox(height: FgSpace.s3),
                  TextField(
                    controller: _odometer,
                    keyboardType: TextInputType.number,
                    style: tabular,
                    decoration: InputDecoration(labelText: s.t('odometer'), suffixText: 'km', prefixIcon: const Icon(FgIcons.odometer, size: 20)),
                  ),
                  const SizedBox(height: FgSpace.s3),
                  TextField(controller: _station, decoration: InputDecoration(labelText: s.t('station'), prefixIcon: const Icon(FgIcons.location, size: 20))),
                  const SizedBox(height: FgSpace.s5),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: _saveFuel,
                    icon: const Icon(FgIcons.fuel, size: 18),
                    label: Text(s.t('save')),
                  ),
                ]),
                ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
                  picker(),
                  const SizedBox(height: FgSpace.s4),
                  Text(s.t('incidentType'), style: context.tt.titleSmall),
                  const SizedBox(height: FgSpace.s2),
                  Wrap(spacing: FgSpace.s2, runSpacing: FgSpace.s2, children: [
                    for (final x in incidentTypes)
                      ChoiceChip(
                        avatar: Icon(FgIcons.status(x), size: 16),
                        label: Text(s.status(x)),
                        selected: _type == x,
                        onSelected: (_) {
                          FgHaptics.tap();
                          setState(() => _type = x);
                        },
                      ),
                  ]),
                  const SizedBox(height: FgSpace.s4),
                  TextField(
                    controller: _description,
                    maxLines: 4,
                    minLines: 3,
                    onChanged: (_) {
                      if (_triedIncident) setState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: s.t('description'),
                      alignLabelWithHint: true,
                      errorText: _triedIncident && _description.text.trim().isEmpty ? s.t('required') : null,
                    ),
                  ),
                  const SizedBox(height: FgSpace.s3),
                  TextField(controller: _location, decoration: InputDecoration(labelText: s.t('location'), prefixIcon: const Icon(FgIcons.location, size: 20))),
                  const SizedBox(height: FgSpace.s3),
                  TextField(controller: _reference, decoration: InputDecoration(labelText: s.t('reference'), prefixIcon: const Icon(FgIcons.document, size: 20))),
                  const SizedBox(height: FgSpace.s5),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: _saveIncident,
                    icon: const Icon(FgIcons.send, size: 18),
                    label: Text(s.t('reportIncident')),
                  ),
                ]),
              ]);
            },
          ),
        );
      }),
    );
  }
}
