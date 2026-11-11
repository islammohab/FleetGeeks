import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'job_actions.dart';
import 'providers.dart';

/// Technician job screen: one job line with big start / pause / finish buttons (gloves, workshop light), checklist,
/// QC and photo. Same outbox commands as the job cards of the order screen.
class JobScreen extends ConsumerWidget {
  const JobScreen({super.key, required this.orderId, required this.line});
  final String orderId;
  final String line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final user = ref.watch(authProvider).value;
    final tech = user?.has(['Technician']) ?? false;
    final qc = user?.has(['QC']) ?? false;
    final detail = ref.watch(orderProvider(orderId));
    return Scaffold(
      appBar: AppBar(
        title: Text('$orderId / $line'),
        actions: [
          OutboxButton(onPressed: () => context.push('/outbox')),
          IconButton(tooltip: s.t('refresh'), icon: const Icon(FgIcons.refresh), onPressed: () => ref.invalidate(orderProvider(orderId))),
        ],
      ),
      bottomNavigationBar: OfflineBanner(safeArea: true, onOpenOutbox: () => context.push('/outbox')),
      body: FgRefresh(
        onRefresh: () => ref.refresh(orderProvider(orderId).future),
        child: AsyncBody(
          value: detail,
          loading: const SkeletonList(header: true, count: 2),
          onRetry: () => ref.invalidate(orderProvider(orderId)),
          builder: (d) {
            final o = asRow(d['order']);
            final job = asRows(d['jobs']).where((j) => j.s('LineNum') == line).firstOrNull;
            if (job == null) {
              return ListView(children: [EmptyState(art: FgArt.search, title: s.t('jobNotFound'))]);
            }
            final status = job.s('JobStatus');
            final c = context.fg.tone(toneOf(status));
            final canStart = tech && {'Authorized', 'Paused', 'QCFailed'}.contains(status);
            final running = tech && status == 'InProgress';
            final checklist = (tech || qc) && job.s('QCTemplate').isNotEmpty && status != 'QCPassed';
            final qcNow = qc && status == 'Completed';
            final promise = o.d('CurrentPromise');
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
              children: [
                Container(
                  padding: const EdgeInsets.all(FgSpace.s5),
                  decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brXl),
                  child: Column(children: [
                    Icon(FgIcons.status(status), size: 48, color: c.fg),
                    const SizedBox(height: FgSpace.s2),
                    Semantics(liveRegion: true, child: Text(s.status(status), style: context.tt.headlineMedium?.copyWith(color: c.fg))),
                    const SizedBox(height: FgSpace.s1),
                    Text(
                      job.s('Description').isEmpty ? job.s('JobTypeId') : job.s('Description'),
                      textAlign: TextAlign.center,
                      style: context.tt.titleMedium,
                    ),
                    Text(job.s('JobTypeId'), style: context.tt.bodySmall),
                  ]),
                ),
                const SizedBox(height: FgSpace.s3),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: FgSpace.s4, vertical: FgSpace.s2),
                    child: Column(children: [
                      KeyValueRow(s.t('vehicle'), o.s('VehicleId'), icon: FgIcons.vehicles),
                      if (promise != null) KeyValueRow(s.t('promise'), '${fmtDate(promise, s.lang)} · ${promiseText(s, promise)}', icon: FgIcons.promise, tabular: true),
                      if (o.s('Complaint').isNotEmpty) KeyValueRow(s.t('complaint'), o.s('Complaint'), icon: FgIcons.fault),
                    ]),
                  ),
                ),
                const SizedBox(height: FgSpace.s4),
                if (!tech && !qc) FgNotice(tone: FgTone.info, message: s.t('noJobRole')),
                if (canStart) ...[
                  FgBigButton(icon: FgIcons.start, label: s.t('start'), caption: s.t('startCaption'), height: 88, onPressed: () => jobCommand(context, ref, orderId, line, 'start')),
                  const SizedBox(height: FgSpace.s3),
                ],
                if (running) ...[
                  FgBigButton(icon: FgIcons.finish, label: s.t('finish'), caption: s.t('finishCaption'), height: 88, onPressed: () => jobCommand(context, ref, orderId, line, 'finish')),
                  const SizedBox(height: FgSpace.s3),
                  FgBigButton(icon: FgIcons.pause, label: s.t('pause'), caption: s.t('pauseCaption'), kind: FgButtonKind.neutral, height: 72, onPressed: () => jobPause(context, ref, orderId, line)),
                  const SizedBox(height: FgSpace.s3),
                ],
                if (qcNow) ...[
                  Row(children: [
                    Expanded(child: FgBigButton(icon: FgIcons.qc, label: s.t('qcPass'), kind: FgButtonKind.primary, onPressed: () => jobQc(context, ref, orderId, line, true))),
                    const SizedBox(width: FgSpace.s3),
                    Expanded(child: FgBigButton(icon: FgIcons.bad, label: s.t('qcFail'), kind: FgButtonKind.danger, onPressed: () => jobQc(context, ref, orderId, line, false))),
                  ]),
                  const SizedBox(height: FgSpace.s3),
                ],
                if (checklist) ...[
                  FgBigButton(
                    icon: FgIcons.checklist,
                    label: s.t('checklist'),
                    caption: job.s('QCTemplate'),
                    kind: FgButtonKind.neutral,
                    height: 64,
                    onPressed: () => openChecklist(context, orderId, int.parse(line), job.s('QCTemplate')),
                  ),
                  const SizedBox(height: FgSpace.s3),
                ],
                FgBigButton(
                  icon: FgIcons.camera,
                  label: s.t('photo'),
                  kind: FgButtonKind.neutral,
                  height: 64,
                  onPressed: () => takeEvidencePhoto(context, ref, orderId),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
