import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'documents.dart';
import 'vehicles_screen.dart';

/// Digital service book: released / closed visits with odometer, jobs and documents.
final serviceBookProvider = FutureProvider.autoDispose.family<FgRow, String>(
  (ref, id) async => asRow(await ref.watch(apiProvider).get('/vehicles/${Uri.encodeComponent(id)}/service-book')),
);

final vehicleProvider = FutureProvider.autoDispose.family<FgRow, String>(
  (ref, id) async => asRow(await ref.watch(apiProvider).get('/vehicles/${Uri.encodeComponent(id)}')),
);

/// Vehicle 360: hero, key figures, maintenance due, odometer reading (works offline) and the service book.
class VehicleScreen extends ConsumerStatefulWidget {
  const VehicleScreen({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  ConsumerState<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends ConsumerState<VehicleScreen> {
  final _reading = TextEditingController();

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  Future<void> _saveReading() async {
    final s = ref.read(stringsProvider);
    final id = Uri.encodeComponent(widget.vehicleId);
    final value = double.tryParse(_reading.text.replaceAll(',', '.').trim());
    if (value == null) return;
    FocusScope.of(context).unfocus();
    await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit('/vehicles/$id/readings',
          label: '${s.t('addReading')} ${widget.vehicleId}: $value',
          body: {'kind': 'Odometer', 'value': value, 'readingUtc': DateTime.now().toUtc().toIso8601String()}),
      done: s.t('readingSaved'),
    );
    _reading.clear();
    ref.invalidate(vehicleProvider(widget.vehicleId));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final detail = ref.watch(vehicleProvider(widget.vehicleId));
    final id = Uri.encodeComponent(widget.vehicleId);
    final title = detail.value == null ? widget.vehicleId : vehiclePlate(asRow(detail.value!['vehicle']));
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        OfflineBanner(onOpenOutbox: () => context.push('/outbox')),
        FgActionBar(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/fault?vehicle=$id'),
              icon: const Icon(FgIcons.fault, size: 18),
              label: Text(s.t('reportFault')),
            ),
          ),
          const SizedBox(width: FgSpace.s3),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => context.go('/book?vehicle=$id'),
              icon: const Icon(FgIcons.book, size: 18),
              label: Text(s.t('book')),
            ),
          ),
        ]),
      ]),
      body: FgRefresh(
        onRefresh: () => ref.refresh(vehicleProvider(widget.vehicleId).future),
        child: AsyncBody(
          value: detail,
          loading: const SkeletonList(header: true, count: 3),
          onRetry: () => ref.invalidate(vehicleProvider(widget.vehicleId)),
          builder: (d) {
            final v = asRow(d['vehicle']);
            final pm = asRows(d['pm'])..sort((a, b) => (a.d('NextDueDate') ?? DateTime(9999)).compareTo(b.d('NextDueDate') ?? DateTime(9999)));
            final history = asRows(d['serviceHistory']);
            final nextDue = pm.isEmpty ? null : pm.first.d('NextDueDate');
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
              children: [
                HeroHeader(
                  child: Row(children: [
                    VehicleArt(kind: vehicleKindOf(v.s('VehicleClass')), width: 112),
                    const SizedBox(width: FgSpace.s4),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        PlateBadge(vehiclePlate(v), large: true),
                        const SizedBox(height: FgSpace.s2),
                        Text(vehicleTitle(v), style: context.tt.titleMedium?.copyWith(color: Colors.white)),
                        Text(
                          [v.s('VehicleClass'), if (v.s('EnergyType').isNotEmpty) s.status(v.s('EnergyType'))].join(' · '),
                          style: context.tt.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                        ),
                        const SizedBox(height: FgSpace.s2),
                        StatusPill(v.s('Availability'), dense: true),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: FgSpace.s4),
                StatGrid(children: [
                  StatCard(label: s.t('odometer'), value: fmtKm(v.n('CurrentOdometer')), icon: FgIcons.odometer, caption: v.d('LastReadingDateTime') == null ? null : fmtDate(v.d('LastReadingDateTime'), s.lang)),
                  StatCard(
                    label: s.t('nextService'),
                    value: nextDue == null ? '—' : fmtShortDate(nextDue, s.lang),
                    icon: FgIcons.promise,
                    tone: pm.isNotEmpty ? toneOf(pm.first.s('Status')) : FgTone.neutral,
                    caption: nextDue == null ? null : promiseText(s, nextDue),
                  ),
                ]),
                const SizedBox(height: FgSpace.s4),
                SectionCard(
                  title: s.t('pmDue'),
                  icon: FgIcons.promise,
                  children: [
                    if (pm.isEmpty) EmptyState(compact: true, art: FgArt.done, title: s.t('nothingDue')),
                    for (final p in pm)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          IconTile(FgIcons.status(p.s('Status')), tone: toneOf(p.s('Status')), size: 40),
                          const SizedBox(width: FgSpace.s3),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${p.s('JobType')} ${p.s('Variant')}'.trim(), style: context.tt.titleSmall),
                              Text(fmtDate(p.d('NextDueDate'), s.lang, time: false), style: context.tt.bodySmall),
                            ]),
                          ),
                          StatusPill(p.s('Status'), dense: true),
                        ]),
                      ),
                  ],
                ),
                const SizedBox(height: FgSpace.s3),
                SectionCard(
                  title: s.t('addReading'),
                  icon: FgIcons.odometer,
                  subtitle: s.t('worksOffline'),
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: TextField(
                          controller: _reading,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontFeatures: FgFonts.tabular),
                          decoration: InputDecoration(labelText: s.t('odometer'), suffixText: 'km'),
                          onSubmitted: (_) => _saveReading(),
                        ),
                      ),
                      const SizedBox(width: FgSpace.s3),
                      SizedBox(height: 52, child: FilledButton(onPressed: _saveReading, child: Text(s.t('save')))),
                    ]),
                  ],
                ),
                const SizedBox(height: FgSpace.s3),
                SectionCard(
                  title: s.t('details'),
                  icon: FgIcons.info,
                  children: [
                    KeyValueRow('VIN', v.s('VIN'), tabular: true),
                    if (v.s('FleetNumber').isNotEmpty) KeyValueRow(s.t('fleetNumber'), v.s('FleetNumber'), tabular: true),
                    KeyValueRow(s.t('vehicleClass'), v.s('VehicleClass')),
                    if (v.d('RegistrationExpiry') != null) KeyValueRow(s.t('registrationExpiry'), fmtDate(v.d('RegistrationExpiry'), s.lang, time: false)),
                    if (v.d('InsuranceExpiry') != null) KeyValueRow(s.t('insuranceExpiry'), fmtDate(v.d('InsuranceExpiry'), s.lang, time: false)),
                    if (v.d('WarrantyEnd') != null) KeyValueRow(s.t('warrantyEnd'), fmtDate(v.d('WarrantyEnd'), s.lang, time: false)),
                  ],
                ),
                const SizedBox(height: FgSpace.s3),
                SectionCard(
                  title: s.t('serviceHistory'),
                  icon: FgIcons.history,
                  trailing: TextButton.icon(
                    onPressed: () => context.push('/usage?vehicle=$id'),
                    icon: const Icon(FgIcons.fuel, size: 18),
                    label: Text(s.t('usageShort')),
                  ),
                  children: [
                    if (history.isEmpty) EmptyState(compact: true, art: FgArt.calendar, title: s.t('noHistory')),
                    if (history.isNotEmpty)
                      FgTimeline(entries: [
                        for (final o in history)
                          FgTimelineEntry(
                            title: '${o.s('ServiceOrderId')} · ${s.status(o.s('ServiceType'))}',
                            time: o.d('ReleasedDateTime') ?? o.d('ArrivedDateTime') ?? o.d('CurrentPromise'),
                            icon: FgIcons.status(o.s('Status')),
                            tone: toneOf(o.s('Status')),
                            trailing: StatusPill(o.s('Status'), dense: true),
                            onTap: () => context.push('/orders/${Uri.encodeComponent(o.s('ServiceOrderId'))}'),
                          ),
                      ]),
                  ],
                ),
                const SizedBox(height: FgSpace.s3),
                SectionCard(
                  title: s.t('serviceBook'),
                  subtitle: s.t('serviceBookHint'),
                  icon: FgIcons.serviceBook,
                  trailing: IconButton(
                    tooltip: s.t('downloadPdf'),
                    icon: const Icon(FgIcons.download),
                    onPressed: () => openPdf(context, ref, '/vehicles/$id/service-book.pdf', 'service-book-${widget.vehicleId}.pdf', query: {'lang': s.lang}),
                  ),
                  children: [_ServiceBook(vehicleId: widget.vehicleId)],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The service book visits as a timeline (newest first): workshop, odometer in / out, jobs, documents (tap to open).
class _ServiceBook extends ConsumerWidget {
  const _ServiceBook({required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return switch (ref.watch(serviceBookProvider(vehicleId))) {
      AsyncData(:final value) => asRows(value['visits']).isEmpty
          ? EmptyState(compact: true, art: FgArt.calendar, title: s.t('noVisits'))
          : FgTimeline(entries: [
              for (final visit in asRows(value['visits']))
                FgTimelineEntry(
                  title: '${visit.s('serviceOrderId')} · ${s.status(visit.s('serviceType'))}',
                  subtitle: [
                    visit.s('workshopName').isEmpty ? visit.s('workshop') : visit.s('workshopName'),
                    if (visit.n('odometerOut') > 0 || visit.n('odometerIn') > 0) fmtKm(visit.n('odometerOut') > 0 ? visit.n('odometerOut') : visit.n('odometerIn')),
                    for (final j in asRows(visit['jobs'])) j.s('description').isEmpty ? j.s('jobTypeId') : j.s('description'),
                  ].where((x) => x.isNotEmpty).join(' · '),
                  time: visit.d('released') ?? visit.d('arrived'),
                  icon: FgIcons.serviceBook,
                  tone: FgTone.good,
                  trailing: asRows(visit['documents']).isEmpty
                      ? null
                      : IconButton(
                          tooltip: s.status(asRows(visit['documents']).first.s('documentType')),
                          icon: const Icon(FgIcons.document, size: 20),
                          onPressed: () {
                            final doc = asRows(visit['documents']).first;
                            openPdf(context, ref, '/documents/${Uri.encodeComponent(doc.s('evidenceId'))}', '${doc.s('documentType')}-${visit.s('serviceOrderId')}.pdf');
                          },
                        ),
                  onTap: () => context.push('/orders/${Uri.encodeComponent(visit.s('serviceOrderId'))}'),
                ),
            ]),
      AsyncError(:final error) => ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(serviceBookProvider(vehicleId))),
      _ => const Shimmer(child: Column(children: [SkeletonBox(), SizedBox(height: 8), SkeletonBox(width: 180)])),
    };
  }
}
