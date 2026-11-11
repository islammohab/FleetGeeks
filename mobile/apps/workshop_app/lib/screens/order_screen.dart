import 'dart:convert';

import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'damage_sheet.dart';
import 'delivery_checklist_sheet.dart';
import 'handover_offer.dart';
import 'health_check_sheet.dart';
import 'job_actions.dart';
import 'providers.dart';

/// Photos of a service order (image evidence).
List<FgPhoto> orderPhotos(List<FgRow> evidence, Strings s) => [
      for (final e in evidence.where(isImageEvidence))
        FgPhoto(
          builder: (fit) => EvidenceImage(e.s('EvidenceId'), fit: fit),
          label: s.status(e.s('Category')),
          caption: fmtDate(e.d('CapturedDateTime'), s.lang),
          category: e.s('Category'),
        ),
    ];

/// Technician / QC / advisor workspace for one service order, in tabs: Jobs, Inspection, Evidence, Handover, Timeline.
/// Job, checklist, QC, damage, health check and handover commands go through the offline outbox, so a technician
/// without signal keeps working and the commands are sent later in order.
class OrderScreen extends ConsumerWidget {
  const OrderScreen({super.key, required this.orderId, this.initialTab = 0});
  final String orderId;
  final int initialTab;

  Future<void> _damage(BuildContext context, WidgetRef ref) async {
    final photo = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => DamageSheet(orderId: orderId));
    if (photo == true && context.mounted) await takeEvidencePhoto(context, ref, orderId, category: 'Damage');
  }

  void _healthCheck(BuildContext context) =>
      showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => HealthCheckSheet(orderId: orderId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final user = ref.watch(authProvider).value;
    final detail = ref.watch(orderProvider(orderId));
    final tech = user?.has(['Technician']) ?? false;
    final qc = user?.has(['QC']) ?? false;
    final pendingHandovers = asRows(detail.value?['handovers']).where((h) => h.s('Status') == 'Offered').length;
    final advisor = user?.has(['Advisor', 'WorkshopManager']) ?? false;
    final unread = unreadByOrder(ref.watch(unreadMessagesProvider).value)[orderId] ?? 0;

    return DefaultTabController(
      length: 5,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(orderId),
          actions: [
            IconButton(
              tooltip: s.t('messages'),
              onPressed: () => context.push('/orders/${Uri.encodeComponent(orderId)}/messages'),
              icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(FgIcons.messages)),
            ),
            OutboxButton(onPressed: () => context.push('/outbox')),
            IconButton(
              tooltip: s.t('refresh'),
              icon: const Icon(FgIcons.refresh),
              onPressed: () {
                ref.invalidate(orderProvider(orderId));
                ref.invalidate(orderTimelineProvider(orderId));
                ref.invalidate(orderChecklistsProvider(orderId));
                ref.invalidate(unreadMessagesProvider);
              },
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: const Icon(FgIcons.tasks, size: 20), text: s.t('jobs')),
              Tab(icon: const Icon(FgIcons.healthCheck, size: 20), text: s.t('inspectionTab')),
              Tab(icon: const Icon(FgIcons.gallery, size: 20), text: s.t('evidence')),
              Tab(
                icon: Badge(isLabelVisible: pendingHandovers > 0, label: Text('$pendingHandovers'), child: const Icon(FgIcons.handover, size: 20)),
                text: s.t('handover'),
              ),
              Tab(icon: const Icon(FgIcons.timeline, size: 20), text: s.t('timeline')),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'photo-$orderId',
          tooltip: s.t('photo'),
          onPressed: () => takeEvidencePhoto(context, ref, orderId),
          child: const Icon(FgIcons.camera),
        ),
        bottomNavigationBar: OfflineBanner(safeArea: true, onOpenOutbox: () => context.push('/outbox')),
        body: AsyncBody(
          value: detail,
          loading: const SkeletonList(header: true, count: 3),
          onRetry: () => ref.invalidate(orderProvider(orderId)),
          builder: (d) {
            final o = asRow(d['order']);
            final jobs = asRows(d['jobs']);
            final handovers = asRows(d['handovers']);
            Future<void> refresh() => ref.refresh(orderProvider(orderId).future);
            Widget tab(List<Widget> children) => FgRefresh(
                  onRefresh: refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s3, FgSpace.gutter, 96),
                    children: children,
                  ),
                );
            return Column(children: [
              _OrderHeader(order: o),
              Expanded(
                child: TabBarView(children: [
                  tab([
                    if (jobs.isEmpty) EmptyState(art: FgArt.empty, title: s.t('noJobsYet')),
                    for (final j in jobs) ...[
                      JobCard(orderId: orderId, job: j, tech: tech, qc: qc),
                      const SizedBox(height: FgSpace.s3),
                    ],
                  ]),
                  tab(_inspectionTab(context, ref, s, d)),
                  tab(_evidenceTab(context, ref, s, d)),
                  tab([
                    if (advisor) ...[
                      FgBigButton(
                        icon: FgIcons.deliveryCheck,
                        label: s.t('deliveryChecklist'),
                        caption: s.t('deliveryChecklistCaption'),
                        kind: FgButtonKind.neutral,
                        height: 64,
                        onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => DeliveryChecklistSheet(orderId: orderId)),
                      ),
                      const SizedBox(height: FgSpace.s3),
                    ],
                    for (final h in handovers.where((h) => h.s('Status') == 'Offered')) ...[
                      _HandoverCard(orderId: orderId, handover: h),
                      const SizedBox(height: FgSpace.s3),
                    ],
                    if (handovers.every((h) => h.s('Status') != 'Offered')) ...[
                      OfferHandoverCard(orderId: orderId, order: o),
                      const SizedBox(height: FgSpace.s3),
                    ],
                    SectionCard(
                      title: s.t('handoverHistory'),
                      icon: FgIcons.history,
                      children: [
                        if (handovers.isEmpty) Text(s.t('noData'), style: context.tt.bodySmall),
                        if (handovers.isNotEmpty)
                          FgTimeline(entries: [
                            for (final h in handovers)
                              FgTimelineEntry(
                                title: '${s.status(h.s('FromRole'))} → ${s.status(h.s('ToRole'))}',
                                subtitle: [h.s('HandoverId'), h.s('ToParty'), h.s('SignerName')].where((x) => x.isNotEmpty).join(' · '),
                                time: h.d('OfferedDateTime'),
                                icon: FgIcons.handover,
                                tone: toneOf(h.s('Status')),
                                trailing: StatusPill(h.s('Status'), dense: true),
                              ),
                          ]),
                      ],
                    ),
                  ]),
                  tab([
                    SectionCard(title: s.t('progress'), icon: FgIcons.timeline, children: [
                      OrderProgress(status: o.s('Status'), times: {
                        'Arrived': o.d('ArrivedDateTime'),
                        'Ready': o.d('ReadyDateTime'),
                        'Released': o.d('ReleasedDateTime'),
                      }),
                    ]),
                    const SizedBox(height: FgSpace.s3),
                    SectionCard(
                      title: s.t('activity'),
                      icon: FgIcons.history,
                      children: [
                        OrderEventsTimeline(orderId: orderId, photos: {
                          for (final e in asRows(d['evidence']).where(isImageEvidence))
                            e.s('EvidenceId'): FgPhoto(builder: (fit) => EvidenceImage(e.s('EvidenceId'), fit: fit), label: s.status(e.s('Category')), category: e.s('Category')),
                        }),
                      ],
                    ),
                  ]),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }

  List<Widget> _inspectionTab(BuildContext context, WidgetRef ref, Strings s, FgRow d) {
    final checks = asRows(d['healthChecks']);
    final damage = asRows(d['damage']);
    return [
      SectionCard(
        title: s.t('healthCheck'),
        icon: FgIcons.healthCheck,
        children: [
          for (final c in checks)
            Padding(
              padding: const EdgeInsets.only(bottom: FgSpace.s2),
              child: Row(children: [
                Expanded(child: Text(c.s('HealthCheckId'), style: context.tt.titleSmall)),
                _Rag(count: c.n('RedCount').round(), tone: FgTone.bad),
                const SizedBox(width: FgSpace.s1),
                _Rag(count: c.n('AmberCount').round(), tone: FgTone.attention),
                const SizedBox(width: FgSpace.s2),
                StatusPill(c.s('Status'), dense: true),
              ]),
            ),
          if (checks.isEmpty) Text(s.t('noHealthCheck'), style: context.tt.bodySmall),
          const SizedBox(height: FgSpace.s2),
          FgBigButton(icon: FgIcons.healthCheck, label: s.t(checks.any((c) => c.s('Status') == 'Draft') ? 'continueHealthCheck' : 'healthCheck'), kind: FgButtonKind.neutral, height: 56, onPressed: () => _healthCheck(context)),
        ],
      ),
      const SizedBox(height: FgSpace.s3),
      SectionCard(
        title: s.t('damageMap'),
        icon: FgIcons.damage,
        trailing: CountPill(damage.length, tone: FgTone.bad),
        children: [
          DamageMap(points: damage),
          const SizedBox(height: FgSpace.s3),
          for (final p in damage)
            Padding(
              padding: const EdgeInsets.only(bottom: FgSpace.s1),
              child: Row(children: [
                Icon(FgIcons.damage, size: 16, color: context.fg.danger),
                const SizedBox(width: FgSpace.s2),
                Expanded(child: Text('${s.status(p.s('Zone'))} · ${s.status(p.s('DamageType'))}${p.s('Note').isEmpty ? '' : ' · ${p.s('Note')}'}', style: context.tt.bodyMedium)),
                StatusPill(p.s('Severity'), dense: true),
              ]),
            ),
          const SizedBox(height: FgSpace.s2),
          FgBigButton(icon: FgIcons.damage, label: s.t('addDamage'), kind: FgButtonKind.neutral, height: 56, onPressed: () => _damage(context, ref)),
        ],
      ),
      const SizedBox(height: FgSpace.s3),
      SectionCard(title: s.t('checks'), icon: FgIcons.checklist, children: [ChecklistResults(orderId: orderId)]),
    ];
  }

  List<Widget> _evidenceTab(BuildContext context, WidgetRef ref, Strings s, FgRow d) {
    final evidence = asRows(d['evidence']);
    final photos = orderPhotos(evidence, s);
    final files = evidence.where((e) => !isImageEvidence(e)).toList();
    return [
      FgBigButton(icon: FgIcons.camera, label: s.t('photo'), caption: s.t('photoCaption'), onPressed: () => takeEvidencePhoto(context, ref, orderId)),
      const SizedBox(height: FgSpace.s3),
      if (photos.isEmpty && files.isEmpty) EmptyState(compact: true, art: FgArt.empty, title: s.t('noPhotos')),
      if (photos.isNotEmpty) SectionCard(title: s.t('photos'), icon: FgIcons.gallery, trailing: CountPill(photos.length), children: [PhotoGallery(photos: photos)]),
      if (files.isNotEmpty) ...[
        const SizedBox(height: FgSpace.s3),
        SectionCard(title: s.t('documents'), icon: FgIcons.document, children: [
          for (final f in files)
            KeyValueRow(s.status(f.s('Category')), f.s('FileName'), icon: FgIcons.document),
        ]),
      ],
    ];
  }
}

class _Rag extends StatelessWidget {
  const _Rag({required this.count, required this.tone});
  final int count;
  final FgTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.fg.tone(count == 0 ? FgTone.neutral : tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brPill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$count', style: context.tt.labelMedium?.copyWith(color: c.fg, fontFeatures: FgFonts.tabular)),
      ]),
    );
  }
}

/// Compact order header above the tabs: vehicle, status, promise countdown, custody and safety hold.
class _OrderHeader extends ConsumerWidget {
  const _OrderHeader({required this.order});
  final FgRow order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    final o = order;
    final promise = o.d('CurrentPromise');
    final overdue = promise != null && promise.isBefore(DateTime.now()) && isOrderOpen(o.s('Status'));
    return Container(
      color: fg.surface,
      padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s3, FgSpace.gutter, FgSpace.s3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.t('vehicle')} ${o.s('VehicleId')}', style: context.tt.titleMedium),
              Text(
                [s.status(o.s('ServiceType')), if (o.s('CustodyRole').isNotEmpty) '${s.t('custody')}: ${s.status(o.s('CustodyRole'))} ${o.s('CustodyHolder')}'.trim()].join(' · '),
                style: context.tt.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          StatusPill(o.s('Status')),
        ]),
        if (promise != null) ...[
          const SizedBox(height: FgSpace.s2),
          Row(children: [
            Icon(FgIcons.promise, size: 16, color: overdue ? fg.danger : fg.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${s.t('promise')}: ${fmtDate(promise, s.lang)} · ${promiseText(s, promise)}',
                style: context.tt.labelMedium?.copyWith(color: overdue ? fg.danger : fg.textMuted, fontFeatures: FgFonts.tabular, fontWeight: overdue ? FontWeight.w700 : null),
              ),
            ),
          ]),
        ],
        if (o.s('SafetyHold') == 'Yes') ...[
          const SizedBox(height: FgSpace.s2),
          FgNotice(tone: FgTone.bad, icon: FgIcons.safety, message: s.t('releaseBlockers')),
        ],
        if (o.s('Complaint').isNotEmpty) ...[
          const SizedBox(height: FgSpace.s2),
          Text(o.s('Complaint'), style: context.tt.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}

/// One job line with the technician / QC actions; tap opens the full-screen job view with big buttons.
class JobCard extends ConsumerWidget {
  const JobCard({super.key, required this.orderId, required this.job, required this.tech, required this.qc});
  final String orderId;
  final FgRow job;
  final bool tech;
  final bool qc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final status = job.s('JobStatus');
    final line = job.s('LineNum');
    final canStart = tech && {'Authorized', 'Paused', 'QCFailed'}.contains(status);
    final running = tech && status == 'InProgress';
    final checklist = (tech || qc) && job.s('QCTemplate').isNotEmpty && status != 'QCPassed';
    final qcNow = qc && status == 'Completed';
    return FgListCard(
      leading: IconTile(FgIcons.status(status), tone: toneOf(status)),
      title: job.s('Description').isEmpty ? job.s('JobTypeId') : job.s('Description'),
      subtitle: '${s.t('line')} $line · ${job.s('JobTypeId')}',
      trailing: StatusPill(status, dense: true),
      onTap: () => context.push('/orders/${Uri.encodeComponent(orderId)}/jobs/${Uri.encodeComponent(line)}'),
      footer: !(canStart || running || checklist || qcNow)
          ? null
          : Wrap(spacing: FgSpace.s2, runSpacing: FgSpace.s2, children: [
              if (canStart)
                FilledButton.icon(onPressed: () => jobCommand(context, ref, orderId, line, 'start'), icon: const Icon(FgIcons.start, size: 18), label: Text(s.t('start'))),
              if (running) ...[
                OutlinedButton.icon(onPressed: () => jobPause(context, ref, orderId, line), icon: const Icon(FgIcons.pause, size: 18), label: Text(s.t('pause'))),
                FilledButton.icon(onPressed: () => jobCommand(context, ref, orderId, line, 'finish'), icon: const Icon(FgIcons.finish, size: 18), label: Text(s.t('finish'))),
              ],
              if (checklist)
                OutlinedButton.icon(
                  onPressed: () => openChecklist(context, orderId, int.parse(line), job.s('QCTemplate')),
                  icon: const Icon(FgIcons.checklist, size: 18),
                  label: Text(s.t('checklist')),
                ),
              if (qcNow) ...[
                FilledButton.icon(onPressed: () => jobQc(context, ref, orderId, line, true), icon: const Icon(FgIcons.qc, size: 18), label: Text(s.t('qcPass'))),
                OutlinedButton.icon(onPressed: () => jobQc(context, ref, orderId, line, false), icon: const Icon(FgIcons.bad, size: 18), label: Text(s.t('qcFail'))),
              ],
            ]),
    );
  }
}

/// Read-only damage map (vehicle from above, front at the top); zones keep their physical left / right meaning, so it is
/// always laid out left-to-right.
class DamageMap extends ConsumerWidget {
  const DamageMap({super.key, required this.points, this.selected, this.onTap});
  final List<FgRow> points;
  final String? selected;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    final count = <String, int>{};
    for (final p in points) {
      count[p.s('Zone')] = (count[p.s('Zone')] ?? 0) + 1;
    }
    Widget zone(String z, {double height = 60}) {
      final n = count[z] ?? 0;
      final isSelected = selected == z;
      final c = fg.tone(n > 0 ? FgTone.bad : FgTone.neutral);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Semantics(
            button: onTap != null,
            selected: isSelected,
            label: n > 0 ? '${s.status(z)}: $n' : s.status(z),
            excludeSemantics: true,
            child: Material(
              color: isSelected ? fg.actionBg : (n > 0 ? c.bg : fg.surface.withValues(alpha: 0.85)),
              shape: RoundedRectangleBorder(
                borderRadius: FgRadius.brMd,
                side: BorderSide(color: isSelected ? fg.action : (n > 0 ? c.fg : fg.border), width: isSelected ? 2 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap == null
                    ? null
                    : () {
                        FgHaptics.tap();
                        onTap!(z);
                      },
                child: SizedBox(
                  height: height,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        n > 0 ? '${s.status(z)} ($n)' : s.status(z),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: context.tt.labelMedium?.copyWith(fontWeight: isSelected || n > 0 ? FontWeight.w700 : FontWeight.w500, color: n > 0 && !isSelected ? c.fg : null),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.all(FgSpace.s2),
        decoration: BoxDecoration(color: fg.surface2, borderRadius: FgRadius.brLg),
        child: Column(children: [
          Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('▲ ${s.t('front')}', style: context.tt.labelSmall)),
          for (final row in damageZones) Row(children: [for (final z in row) zone(z)]),
          Row(children: [zone('Interior', height: 48)]),
        ]),
      ),
    );
  }
}


/// Receiver side of a two-party handover: accept with a signature (POST /workshop/handovers/{id}/sign: accepts and
/// generates the signed condition report / release note; online only), accept without signature through the outbox
/// (also offline), or reject with a D365 reason code.
class _HandoverCard extends ConsumerWidget {
  const _HandoverCard({required this.orderId, required this.handover});
  final String orderId;
  final FgRow handover;

  Future<bool> _respond(BuildContext context, WidgetRef ref, String response, String reason, {String? signerName}) async {
    final s = ref.read(stringsProvider);
    final user = ref.read(authProvider).value;
    final ok = await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit(
            '/workshop/handovers/${Uri.encodeComponent(handover.s('HandoverId'))}/respond',
            label: '${s.t('handover')} ${handover.s('HandoverId')} ${s.t(response == 'Accept' ? 'accept' : 'reject')}',
            body: {'response': response, 'signerName': signerName ?? user?.contactName ?? '', 'reason': reason, 'note': '', 'termsVersion': ''},
          ),
    );
    ref.invalidate(orderProvider(orderId));
    return ok;
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final user = ref.read(authProvider).value;
    // The card disappears once the handover is answered: keep the container and API client.
    final container = ProviderScope.containerOf(context, listen: false);
    final api = ref.read(apiProvider);
    final online = ref.read(connectivityProvider).value ?? true;
    final controller = SignatureController();
    final signer = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (context) => _SignatureSheet(controller: controller, handover: handover, initialName: user?.contactName ?? '', online: online),
    );
    if (signer == null || !context.mounted) {
      controller.dispose();
      return;
    }
    final png = await controller.toPngBytes();
    controller.dispose();
    if (!context.mounted) return;
    if (png == null || !online) {
      await _respond(context, ref, 'Accept', '', signerName: signer);
      return;
    }
    try {
      await api.post('/workshop/handovers/${Uri.encodeComponent(handover.s('HandoverId'))}/sign', idempotencyKey: const Uuid().v4(), body: {
        'signaturePng': base64Encode(png),
        'signerName': signer,
        'signerRole': handover.s('ToRole'),
        'termsVersion': '',
        'language': s.lang,
      });
      container.invalidate(orderProvider(orderId));
      container.invalidate(orderDocumentsProvider(orderId));
      container.invalidate(orderTimelineProvider(orderId));
      if (context.mounted) showDone(context, s.t('handoverSigned'));
    } on ApiException catch (e) {
      // No connection, or a role that may not sign: accept without the signature (outbox), and say so.
      if ((e.isNetwork || e.status == 403) && context.mounted) {
        final ok = await _respond(context, ref, 'Accept', '', signerName: signer);
        if (ok && context.mounted) showError(context, s.t('signatureNotSaved'));
      } else if (context.mounted) {
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    final overdue = handover.s('DelayReason').isNotEmpty;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: fg.warning, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(FgSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const IconTile(FgIcons.handover, tone: FgTone.attention),
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.t('handover')} ${handover.s('HandoverId')}', style: context.tt.titleMedium),
                Text('${s.status(handover.s('FromRole'))} → ${s.status(handover.s('ToRole'))} ${handover.s('ToParty')}', style: context.tt.bodySmall),
              ]),
            ),
          ]),
          if (handover.s('ConditionNotes').isNotEmpty) ...[
            const SizedBox(height: FgSpace.s2),
            Text(handover.s('ConditionNotes'), style: context.tt.bodyMedium),
          ],
          if (overdue) ...[
            const SizedBox(height: FgSpace.s2),
            FgNotice(tone: FgTone.attention, icon: FgIcons.promise, title: s.t('lateHandover'), message: [handover.s('DelayReason'), handover.s('DelayNote')].where((x) => x.isNotEmpty).join(' · ')),
          ],
          const SizedBox(height: FgSpace.s3),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(FgIcons.close, size: 18),
                label: Text(s.t('reject')),
                onPressed: () async {
                  final reasons = await ref.read(lookupProvider('reasons?type=Rejection').future);
                  if (!context.mounted) return;
                  final reason = await pickLookup(context, title: s.t('reason'), rows: reasons, s: s, showId: false);
                  if (reason != null && context.mounted) await _respond(context, ref, 'Reject', reason);
                },
              ),
            ),
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(FgIcons.signature, size: 18),
                label: Text(s.t('accept')),
                onPressed: () => _accept(context, ref),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Signature and signer name; pops the signer name (accept) or null (cancel). Without strokes (or offline) the handover
/// is accepted without a signed document.
class _SignatureSheet extends ConsumerStatefulWidget {
  const _SignatureSheet({required this.controller, required this.handover, required this.initialName, required this.online});
  final SignatureController controller;
  final FgRow handover;
  final String initialName;
  final bool online;

  @override
  ConsumerState<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends ConsumerState<_SignatureSheet> {
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s5, FgSpace.gutter, FgSpace.s4 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('signHandover'), style: context.tt.titleLarge),
          const SizedBox(height: FgSpace.s1),
          Text(
            '${widget.handover.s('HandoverId')} · ${s.status(widget.handover.s('FromRole'))} → ${s.status(widget.handover.s('ToRole'))}',
            style: context.tt.bodySmall,
          ),
          const SizedBox(height: FgSpace.s3),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: s.t('signerName'), prefixIcon: const Icon(FgIcons.driver, size: 20)),
          ),
          const SizedBox(height: FgSpace.s3),
          SignaturePad(controller: widget.controller, height: 180),
          const SizedBox(height: FgSpace.s2),
          if (!widget.online)
            FgNotice(tone: FgTone.attention, icon: FgIcons.offline, message: s.t('signOffline'))
          else
            Text(s.t('signatureHint'), style: context.tt.bodySmall),
          const SizedBox(height: FgSpace.s3),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel')))),
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => FilledButton.icon(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () {
                          FgHaptics.success();
                          Navigator.pop(context, _name.text.trim());
                        },
                  icon: const Icon(FgIcons.check, size: 18),
                  label: Text(s.t(widget.controller.isEmpty || !widget.online ? 'acceptUnsigned' : 'acceptAndSign')),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
