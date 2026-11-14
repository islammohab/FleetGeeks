import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final mobilityProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async => asRows(await ref.watch(apiProvider).get('/mobility')));

/// Pickups, deliveries, replacement vehicles and roadside jobs for the workshop drivers: mark "on the way" and complete
/// (with the odometer for a replacement vehicle). Commands go through the outbox.
class MobilityScreen extends ConsumerWidget {
  const MobilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('mobility')), actions: [
        OutboxButton(onPressed: () => context.push('/outbox')),
        IconButton(tooltip: s.t('refresh'), icon: const Icon(FgIcons.refresh), onPressed: () => ref.invalidate(mobilityProvider)),
      ]),
      bottomNavigationBar: OfflineBanner(safeArea: true, onOpenOutbox: () => context.push('/outbox')),
      body: const MobilityList(),
    );
  }
}

/// The open mobility tasks (Assigned / In progress) as cards with one big next-step button.
class MobilityList extends ConsumerWidget {
  const MobilityList({super.key});

  Future<void> _step(BuildContext context, WidgetRef ref, FgRow request, String verb) async {
    final s = ref.read(stringsProvider);
    double odometer = 0;
    if (request.s('RequestType') == 'Replacement') {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(FgIcons.odometer),
          title: Text(s.t(verb == 'progress' ? 'onTheWay' : 'complete')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontFeatures: FgFonts.tabular),
            decoration: InputDecoration(labelText: s.t('odometer'), suffixText: 'km'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('save'))),
          ],
        ),
      );
      if (ok != true) return;
      odometer = double.tryParse(controller.text.trim()) ?? 0;
    }
    if (!context.mounted) return;
    await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit('/workshop/mobility/${Uri.encodeComponent(request.s('RequestId'))}/$verb',
          label: '${s.t(verb == 'progress' ? 'onTheWay' : 'complete')} ${request.s('RequestId')}', body: {'odometer': odometer}),
    );
    ref.invalidate(mobilityProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final requests = ref.watch(mobilityProvider);
    return FgRefresh(
      onRefresh: () => ref.refresh(mobilityProvider.future),
      child: AsyncBody(
        value: requests,
        onRetry: () => ref.invalidate(mobilityProvider),
        builder: (rows) {
          final mine = rows.where((r) => {'Assigned', 'InProgress'}.contains(r.s('Status'))).toList();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s3, FgSpace.gutter, FgSpace.s6),
            children: [
              if (mine.isEmpty) EmptyState(art: FgArt.done, title: s.t('noMobility'), message: s.t('noMobilityHint')),
              for (final r in mine) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(FgSpace.s4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        IconTile(FgIcons.event(r.s('RequestType')), tone: toneOf(r.s('RequestType'))),
                        const SizedBox(width: FgSpace.s3),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.status(r.s('RequestType')), style: context.tt.titleMedium),
                            Text(r.s('RequestId'), style: context.tt.bodySmall?.copyWith(fontFeatures: FgFonts.tabular)),
                          ]),
                        ),
                        StatusPill(r.s('Status'), dense: true),
                      ]),
                      const SizedBox(height: FgSpace.s3),
                      KeyValueRow(
                        s.t('vehicle'),
                        '${r.s('VehicleId')}${r.s('ReplacementVehicleId').isNotEmpty ? ' → ${r.s('ReplacementVehicleId')}' : ''}',
                        icon: FgIcons.vehicles,
                      ),
                      if (r.s('Address').isNotEmpty) KeyValueRow(s.t('address'), r.s('Address'), icon: FgIcons.location),
                      KeyValueRow(s.t('assignedTo'), r.s('AssignedTo'), icon: FgIcons.driver),
                      KeyValueRow(s.t('eta'), '${fmtDate(r.d('EtaDateTime'), s.lang)}${r.d('EtaDateTime') == null ? '' : ' · ${promiseText(s, r.d('EtaDateTime'))}'}', icon: FgIcons.time, tabular: true),
                      const SizedBox(height: FgSpace.s3),
                      if (r.s('Status') == 'Assigned')
                        FgBigButton(icon: FgIcons.route, label: s.t('onTheWay'), kind: FgButtonKind.primary, height: 60, onPressed: () => _step(context, ref, r, 'progress'))
                      else
                        FgBigButton(icon: FgIcons.finish, label: s.t('complete'), height: 60, onPressed: () => _step(context, ref, r, 'complete')),
                    ]),
                  ),
                ),
                const SizedBox(height: FgSpace.s3),
              ],
            ],
          );
        },
      ),
    );
  }
}
