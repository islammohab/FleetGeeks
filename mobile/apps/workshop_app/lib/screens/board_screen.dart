import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bookings_review_screen.dart';

final queuesProvider = FutureProvider.autoDispose<FgRow>((ref) async => asRow(await ref.watch(apiProvider).get('/workshop/queues')));

/// Stages of the board in order; the two alert lanes first.
const boardLanes = [
  'atRiskPromises', 'releaseBlockers', 'arrivals', 'atGate', 'received', 'awaitingApproval', 'inProgress',
  'awaitingParts', 'qualityCheck', 'rework', 'readyForCollection', 'pendingHandovers',
];

const _alertLanes = {'atRiskPromises', 'releaseBlockers'};

IconData laneIcon(String lane) => switch (lane) {
      'atRiskPromises' => FgIcons.time,
      'releaseBlockers' => FgIcons.safety,
      'arrivals' => FgIcons.calendar,
      'atGate' => FgIcons.gate,
      'received' => FgIcons.event('arrived'),
      'awaitingApproval' => FgIcons.estimate,
      'inProgress' => FgIcons.tasks,
      'awaitingParts' => FgIcons.parts,
      'qualityCheck' => FgIcons.qc,
      'rework' => FgIcons.retry,
      'readyForCollection' => FgIcons.event('ready'),
      'pendingHandovers' => FgIcons.handover,
      _ => FgIcons.board,
    };

FgTone laneTone(String lane) => switch (lane) {
      'atRiskPromises' || 'releaseBlockers' || 'rework' => FgTone.bad,
      'awaitingApproval' || 'awaitingParts' || 'pendingHandovers' => FgTone.attention,
      'readyForCollection' => FgTone.good,
      'arrivals' || 'atGate' => FgTone.info,
      _ => FgTone.progress,
    };

/// Workshop board: key figures, alert banners, then one section per stage with horizontally scrolling vehicle cards.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  String? _lane;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final queues = ref.watch(queuesProvider);
    final reviewer = ref.watch(authProvider).value?.has(bookingReviewRoles) ?? false;
    final requests = reviewer ? (ref.watch(requestedBookingsProvider).value ?? const <FgRow>[]).where((b) => b.s('status') == 'Requested').length : 0;
    final unread = unreadByOrder(ref.watch(unreadMessagesProvider).value).entries.where((e) => e.value > 0).toList();
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const FgBrandMark(size: 30),
          const SizedBox(width: FgSpace.s2),
          Flexible(child: Text(s.t('board'), overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          OutboxButton(onPressed: () => context.push('/outbox')),
          IconButton(tooltip: s.t('refresh'), icon: const Icon(FgIcons.refresh), onPressed: () => ref.invalidate(queuesProvider)),
        ],
      ),
      body: FgRefresh(
        onRefresh: () {
          ref.invalidate(unreadMessagesProvider);
          if (reviewer) ref.invalidate(requestedBookingsProvider);
          return ref.refresh(queuesProvider.future);
        },
        child: AsyncBody(
          value: queues,
          onRetry: () => ref.invalidate(queuesProvider),
          builder: (q) {
            int n(String lane) => asRows(q[lane]).length;
            final lanes = _lane == null ? boardLanes : [_lane!];
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
              children: [
                StatGrid(children: [
                  StatCard(label: s.t('inProgress'), value: fmtNum(n('inProgress')), icon: FgIcons.tasks, onTap: () => setState(() => _lane = 'inProgress')),
                  StatCard(
                    label: s.t('awaitingParts'),
                    value: fmtNum(n('awaitingParts')),
                    icon: FgIcons.parts,
                    tone: n('awaitingParts') > 0 ? FgTone.attention : FgTone.neutral,
                    onTap: () => setState(() => _lane = 'awaitingParts'),
                  ),
                  StatCard(
                    label: s.t('readyForCollection'),
                    value: fmtNum(n('readyForCollection')),
                    icon: FgIcons.event('ready'),
                    tone: FgTone.good,
                    onTap: () => setState(() => _lane = 'readyForCollection'),
                  ),
                  StatCard(
                    label: s.t('arrivals'),
                    value: fmtNum(n('arrivals')),
                    icon: FgIcons.calendar,
                    tone: FgTone.info,
                    onTap: () => setState(() => _lane = 'arrivals'),
                  ),
                ]),
                if (requests > 0) ...[
                  const SizedBox(height: FgSpace.s3),
                  FgNotice(
                    tone: FgTone.attention,
                    icon: FgIcons.proposal,
                    title: '${s.t('bookingsToConfirm')} ($requests)',
                    message: s.t('bookingsToConfirmHint'),
                    action: TextButton(onPressed: () => context.push('/bookings'), child: Text(s.t('show'))),
                  ),
                ],
                if (unread.isNotEmpty) ...[
                  const SizedBox(height: FgSpace.s3),
                  FgNotice(
                    tone: FgTone.info,
                    icon: FgIcons.messages,
                    title: s.t('customerMessages', [unread.fold<int>(0, (n, e) => n + e.value)]),
                    message: unread.map((e) => '${e.key} (${e.value})').join(' · '),
                    action: TextButton(
                      onPressed: () => context.push('/orders/${Uri.encodeComponent(unread.first.key)}/messages'),
                      child: Text(s.t('show')),
                    ),
                  ),
                ],
                for (final alert in _alertLanes)
                  if (n(alert) > 0) ...[
                    const SizedBox(height: FgSpace.s3),
                    FgNotice(
                      tone: FgTone.bad,
                      icon: laneIcon(alert),
                      title: '${s.t(alert)} (${n(alert)})',
                      message: s.t('${alert}Hint'),
                      action: TextButton(onPressed: () => setState(() => _lane = alert), child: Text(s.t('show'))),
                    ),
                  ],
                const SizedBox(height: FgSpace.s3),
                SizedBox(
                  height: 48,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    ChoiceChip(
                      label: Text(s.t('allStages')),
                      selected: _lane == null,
                      onSelected: (_) {
                        FgHaptics.tap();
                        setState(() => _lane = null);
                      },
                    ),
                    for (final lane in boardLanes) ...[
                      const SizedBox(width: FgSpace.s2),
                      ChoiceChip(
                        avatar: Icon(laneIcon(lane), size: 16),
                        label: Text('${s.t(lane)} · ${n(lane)}'),
                        selected: _lane == lane,
                        onSelected: (_) {
                          FgHaptics.tap();
                          setState(() => _lane = _lane == lane ? null : lane);
                        },
                      ),
                    ],
                  ]),
                ),
                for (final lane in lanes) _Lane(lane: lane, items: asRows(q[lane]), expanded: _lane != null),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Lane extends ConsumerWidget {
  const _Lane({required this.lane, required this.items, required this.expanded});
  final String lane;
  final List<FgRow> items;

  /// Single lane selected: cards stacked vertically instead of a horizontal strip.
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = context.fg.tone(items.isEmpty ? FgTone.neutral : laneTone(lane));
    final header = Padding(
      padding: const EdgeInsets.only(top: FgSpace.s5, bottom: FgSpace.s2),
      child: Row(children: [
        Icon(laneIcon(lane), size: 18, color: c.fg),
        const SizedBox(width: FgSpace.s2),
        Expanded(child: Semantics(header: true, child: Text(s.t(lane), style: context.tt.titleSmall))),
        CountPill(items.length, tone: laneTone(lane)),
      ]),
    );
    if (items.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Text(s.t('laneEmpty'), style: context.tt.bodySmall),
      ]);
    }
    if (expanded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        for (final r in items.take(60)) ...[BoardCard(row: r, lane: lane), const SizedBox(height: FgSpace.s2)],
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length > 30 ? 30 : items.length,
          separatorBuilder: (context, index) => const SizedBox(width: FgSpace.s2),
          itemBuilder: (context, i) => SizedBox(width: 260, child: BoardCard(row: items[i], lane: lane)),
        ),
      ),
    ]);
  }
}

/// A vehicle on the board: order (or appointment), vehicle, service type, promise countdown and handover.
class BoardCard extends ConsumerWidget {
  const BoardCard({super.key, required this.row, required this.lane});
  final FgRow row;
  final String lane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    final id = row.s('ServiceOrderId').isNotEmpty ? row.s('ServiceOrderId') : row.s('AppointmentId');
    final promise = row.d('CurrentPromise');
    final overdue = promise != null && promise.isBefore(DateTime.now());
    final risk = _alertLanes.contains(lane) || overdue;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: risk ? fg.danger : fg.border, width: risk ? 1.5 : 1)),
      child: InkWell(
        onTap: row.s('ServiceOrderId').isEmpty ? null : () => context.push('/orders/${Uri.encodeComponent(row.s('ServiceOrderId'))}'),
        child: Padding(
          padding: const EdgeInsets.all(FgSpace.s3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(id, style: context.tt.titleSmall?.copyWith(fontFeatures: FgFonts.tabular), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (row.s('Status').isNotEmpty) StatusPill(row.s('Status'), dense: true),
            ]),
            const SizedBox(height: FgSpace.s1),
            Row(children: [
              Icon(FgIcons.vehicles, size: 16, color: fg.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [row.s('VehicleId'), if (row.s('ServiceType').isNotEmpty) s.status(row.s('ServiceType'))].join(' · '),
                  style: context.tt.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: FgSpace.s2),
            if (promise != null)
              Row(children: [
                Icon(FgIcons.promise, size: 16, color: overdue ? fg.danger : fg.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${fmtShortDate(promise, s.lang)} ${fmtTime(promise, s.lang)} · ${promiseText(s, promise)}',
                    style: context.tt.labelMedium?.copyWith(color: overdue ? fg.danger : fg.textMuted, fontFeatures: FgFonts.tabular, fontWeight: overdue ? FontWeight.w700 : null),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ])
            else if (row.d('StartDateTime') != null)
              Row(children: [
                Icon(FgIcons.calendar, size: 16, color: fg.textMuted),
                const SizedBox(width: 6),
                Text(fmtDate(row.d('StartDateTime'), s.lang), style: context.tt.labelMedium?.copyWith(color: fg.textMuted, fontFeatures: FgFonts.tabular)),
              ]),
            if (row.s('HandoverId').isNotEmpty) ...[
              const SizedBox(height: FgSpace.s1),
              Row(children: [
                Icon(FgIcons.handover, size: 16, color: fg.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${s.status(row.s('FromRole'))} → ${s.status(row.s('ToRole'))}',
                    style: context.tt.labelMedium?.copyWith(color: fg.warning),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
