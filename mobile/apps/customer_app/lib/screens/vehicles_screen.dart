import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final vehiclesProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async => asRows(await ref.watch(apiProvider).get('/vehicles')));

/// "Toyota Hilux 2024" of a vehicle row.
String vehicleTitle(FgRow v) => [v.s('Make'), v.s('ModelName'), v.s('ModelYear')].where((x) => x.isNotEmpty && x != '0').join(' ');

/// Plate, or the vehicle id when the plate is empty.
String vehiclePlate(FgRow v) => v.s('PlateNumber').isEmpty ? v.s('VehicleId') : v.s('PlateNumber');

/// Vehicle picker label used by the forms.
String vehicleOption(FgRow v) => '${vehiclePlate(v)} · ${v.s('Make')} ${v.s('ModelName')}';

enum _Filter { all, available, workshop }

/// Fleet list: search, availability filter and vehicle cards.
class VehiclesScreen extends ConsumerStatefulWidget {
  const VehiclesScreen({super.key});

  @override
  ConsumerState<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends ConsumerState<VehiclesScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(FgRow v) {
    final q = _search.text.trim().toLowerCase();
    final text = '${v.s('PlateNumber')} ${v.s('VehicleId')} ${v.s('Make')} ${v.s('ModelName')} ${v.s('FleetNumber')}'.toLowerCase();
    if (q.isNotEmpty && !text.contains(q)) return false;
    return switch (_filter) {
      _Filter.all => true,
      _Filter.available => v.s('Availability') == 'Available',
      _Filter.workshop => v.s('Availability') != 'Available' && v.s('Availability').isNotEmpty,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final vehicles = ref.watch(vehiclesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('vehicles')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fault-vehicles',
        onPressed: () => context.push('/fault'),
        icon: const Icon(FgIcons.fault),
        label: Text(s.t('reportFault')),
      ),
      body: FgRefresh(
        onRefresh: () => ref.refresh(vehiclesProvider.future),
        child: AsyncBody(
          value: vehicles,
          onRetry: () => ref.invalidate(vehiclesProvider),
          builder: (list) {
            final shown = list.where(_matches).toList();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, 96),
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: s.t('searchVehicles'),
                    prefixIcon: const Icon(FgIcons.search, size: 20),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: s.t('clear'),
                            icon: const Icon(FgIcons.close, size: 18),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
                const SizedBox(height: FgSpace.s3),
                Wrap(spacing: FgSpace.s2, children: [
                  for (final f in _Filter.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        _Filter.all => '${s.t('all')} (${list.length})',
                        _Filter.available => s.status('Available'),
                        _Filter.workshop => s.t('inWorkshop'),
                      }),
                      selected: _filter == f,
                      onSelected: (_) {
                        FgHaptics.tap();
                        setState(() => _filter = f);
                      },
                    ),
                ]),
                const SizedBox(height: FgSpace.s3),
                if (list.isEmpty)
                  EmptyState(art: FgArt.vehicle, title: s.t('noVehicles'), message: s.t('noVehiclesHint'))
                else if (shown.isEmpty)
                  EmptyState(art: FgArt.search, title: s.t('noMatches'), actionLabel: s.t('clearFilters'), onAction: () => setState(() {
                        _search.clear();
                        _filter = _Filter.all;
                      }))
                else
                  for (final v in shown) ...[
                    VehicleCard(
                      plate: vehiclePlate(v),
                      title: vehicleTitle(v),
                      subtitle: v.s('FleetNumber').isEmpty ? v.s('VehicleClass') : '${v.s('FleetNumber')} · ${v.s('VehicleClass')}',
                      vehicleClass: v.s('VehicleClass'),
                      status: v.s('Availability'),
                      odometer: fmtKm(v.n('CurrentOdometer')),
                      onTap: () => context.push('/vehicles/${Uri.encodeComponent(v.s('VehicleId'))}'),
                    ),
                    const SizedBox(height: FgSpace.s3),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}
