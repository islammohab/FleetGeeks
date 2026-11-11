import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cycle.dart';
import '../fg_icons.dart';
import '../format.dart';
import '../haptics.dart';
import '../i18n.dart';
import '../models.dart';
import '../outbox.dart';
import '../status.dart';
import '../theme.dart';
import 'cards.dart';
import 'illustrations.dart';
import 'photos.dart';
import 'shell.dart';
import 'skeleton.dart';
import 'states.dart';
import 'status_pill.dart';
import 'timeline.dart';

Widget _loadingLines() => const Shimmer(
      child: Column(children: [SkeletonBox(), SizedBox(height: 8), SkeletonBox(), SizedBox(height: 8), SkeletonBox(width: 160)]),
    );

FgTone _eventTone(String type) {
  final t = type.toLowerCase();
  if (t.contains('declin') || t.contains('reject') || t.contains('fail') || t.contains('hold') || t.contains('delay')) return FgTone.bad;
  if (t.contains('ready') || t.contains('release') || t.contains('paid') || t.contains('pass') || t.contains('approv')) return FgTone.good;
  if (t.contains('estimate') || t.contains('propos') || t.contains('request') || t.contains('message')) return FgTone.attention;
  return FgTone.progress;
}

/// Order events from D365 (GET /service-orders/{id}/timeline), newest first, in the user's language.
/// [photos] maps evidence ids to photos so events with a picture show it.
class OrderEventsTimeline extends ConsumerWidget {
  const OrderEventsTimeline({super.key, required this.orderId, this.photos = const {}});
  final String orderId;
  final Map<String, FgPhoto> photos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return switch (ref.watch(orderTimelineProvider(orderId))) {
      AsyncData(:final value) => value.isEmpty
          ? Text(s.t('noData'), style: context.tt.bodySmall)
          : FgTimeline(entries: [
              for (final e in value.reversed)
                FgTimelineEntry(
                  title: s.lang == 'ar' && e.s('textAr').isNotEmpty ? e.s('textAr') : (e.s('text').isNotEmpty ? e.s('text') : s.status(e.s('type'))),
                  subtitle: [s.status(e.s('type')), e.s('actor')].where((x) => x.isNotEmpty).join(' · '),
                  time: e.d('at'),
                  icon: FgIcons.orderEvent(e.s('type')),
                  tone: _eventTone(e.s('type')),
                  photos: photos[e.s('evidence')] == null ? const [] : [photos[e.s('evidence')]!],
                ),
            ]),
      AsyncError(:final error) => ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(orderTimelineProvider(orderId))),
      _ => _loadingLines(),
    };
  }
}

/// Jobs with planned start / finish, hours and "working now" (GET /service-orders/{id}/progress).
class JobProgressList extends ConsumerWidget {
  const JobProgressList({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    return switch (ref.watch(orderProgressProvider(orderId))) {
      AsyncData(:final value) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (value['technicianWorking'] == true) ...[
            FgNotice(tone: FgTone.progress, icon: FgIcons.technician, message: s.t('technicianWorking')),
            const SizedBox(height: FgSpace.s3),
          ],
          if (asRows(value['jobs']).isEmpty) Text(s.t('noJobsYet'), style: context.tt.bodySmall),
          for (final j in asRows(value['jobs']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconTile(j['workingNow'] == true ? FgIcons.technician : FgIcons.status(j.s('status')), tone: j['workingNow'] == true ? FgTone.progress : toneOf(j.s('status')), size: 36),
                const SizedBox(width: FgSpace.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(j.s('description').isEmpty ? j.s('jobTypeId') : j.s('description'), style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    if (j.d('plannedStart') != null || j.d('plannedFinish') != null)
                      Text(
                        '${s.t('planned')}: ${fmtShortDate(j.d('plannedStart'), s.lang)} ${fmtTime(j.d('plannedStart'), s.lang)} – ${fmtTime(j.d('plannedFinish'), s.lang)}',
                        style: context.tt.bodySmall?.copyWith(fontFeatures: FgFonts.tabular),
                      ),
                    if (j['workingNow'] == true)
                      Text(
                        j.d('since') == null ? s.t('workingNow') : '${s.t('workingNow')} · ${s.t('since')} ${fmtTime(j.d('since'), s.lang)}',
                        style: context.tt.labelMedium?.copyWith(color: fg.primary, fontWeight: FontWeight.w600),
                      ),
                    if (j.n('estimatedHours') > 0)
                      Text(
                        s.t('hoursProgress', [fmtNum(j.n('actualHours'), decimals: 1), fmtNum(j.n('estimatedHours'), decimals: 1)]),
                        style: context.tt.labelSmall?.copyWith(fontFeatures: FgFonts.tabular),
                      ),
                  ]),
                ),
                const SizedBox(width: FgSpace.s2),
                StatusPill(j.s('status'), dense: true),
              ]),
            ),
        ]),
      AsyncError(:final error) => ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(orderProgressProvider(orderId))),
      _ => _loadingLines(),
    };
  }
}

/// Checklist results grouped by checklist, delivery items marked (GET /service-orders/{id}/checklists).
class ChecklistResults extends ConsumerWidget {
  const ChecklistResults({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    return switch (ref.watch(orderChecklistsProvider(orderId))) {
      AsyncData(:final value) => () {
          final results = asRows(value['results']);
          final groups = <String, List<FgRow>>{};
          for (final r in results) {
            groups.putIfAbsent(r.s('template').isEmpty ? r.s('templateId') : r.s('template'), () => []).add(r);
          }
          final qc = asRows(value['qc']);
          if (results.isEmpty && qc.isEmpty) return Text(s.t('noChecksYet'), style: context.tt.bodySmall);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (value.d('deliveryDone') != null) ...[
              FgNotice(tone: FgTone.good, icon: FgIcons.deliveryCheck, message: s.t('deliveryDoneAt', [fmtDate(value.d('deliveryDone'), s.lang)])),
              const SizedBox(height: FgSpace.s3),
            ],
            for (final entry in groups.entries) ...[
              Row(children: [
                Icon(entry.value.first['delivery'] == true ? FgIcons.deliveryCheck : FgIcons.checklist, size: 18, color: fg.primary),
                const SizedBox(width: FgSpace.s2),
                Expanded(child: Text(entry.key, style: context.tt.titleSmall)),
                if (entry.value.first['delivery'] == true) StatusPill('Delivery', label: s.t('deliveryChecklist'), dense: true),
              ]),
              const SizedBox(height: FgSpace.s1),
              for (final r in entry.value)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: FgSpace.s6, top: 2, bottom: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(
                      r['notApplicable'] == true ? FgIcons.neutral : (r['passed'] == true ? FgIcons.good : FgIcons.bad),
                      size: 16,
                      color: r['notApplicable'] == true ? fg.textMuted : (r['passed'] == true ? fg.success : fg.danger),
                    ),
                    const SizedBox(width: FgSpace.s2),
                    Expanded(
                      child: Text(
                        s.lang == 'ar' && r.s('questionAr').isNotEmpty ? r.s('questionAr') : r.s('question'),
                        style: context.tt.bodyMedium,
                      ),
                    ),
                    if (r.s('answer').isNotEmpty && r.s('answer') != 'Pass' && r.s('answer') != 'Fail')
                      Text(r.s('answer'), style: context.tt.bodySmall),
                  ]),
                ),
              const SizedBox(height: FgSpace.s3),
            ],
            if (qc.isNotEmpty) ...[
              Text(s.t('qc'), style: context.tt.titleSmall),
              for (final q in qc)
                KeyValueRow(
                  '${s.t('line')} ${q.s('jobLine')} · #${q.s('attempt')}',
                  s.status(q.s('outcome')),
                  icon: FgIcons.qc,
                  valueWidget: Align(alignment: AlignmentDirectional.centerEnd, child: StatusPill(q.s('outcome'), dense: true)),
                ),
            ],
          ]);
        }(),
      AsyncError(:final error) => ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(orderChecklistsProvider(orderId))),
      _ => _loadingLines(),
    };
  }
}

/// Two-way messages of a service order. Sending goes through the outbox (works without signal, sent once); the
/// other side's messages are marked read when the thread opens.
class MessageThread extends ConsumerStatefulWidget {
  const MessageThread({super.key, required this.orderId, required this.mySide});
  final String orderId;

  /// 'Customer' or 'Workshop' (FGMessageSender): my bubbles are on the end side.
  final String mySide;

  @override
  ConsumerState<MessageThread> createState() => _MessageThreadState();
}

class _MessageThreadState extends ConsumerState<MessageThread> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Mark the other side's messages as read (online only; a failure just leaves them unread).
    ref.read(apiProvider).post('${messagesPath(widget.orderId)}/read').then<void>(
      (_) {
        if (mounted) ref.invalidate(unreadMessagesProvider);
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    final s = ref.read(stringsProvider);
    setState(() => _sending = true);
    final ok = await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit(
            messagesPath(widget.orderId),
            label: '${s.t('message')} · ${widget.orderId}',
            body: {'text': text, 'attachmentEvidenceId': null},
          ),
      done: s.t('messageSent'),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _text.clear();
      ref.invalidate(orderMessagesProvider(widget.orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final messages = ref.watch(orderMessagesProvider(widget.orderId));
    final queued = (ref.watch(outboxProvider).value ?? const <OutboxItem>[]).where((i) => i.path == messagesPath(widget.orderId)).toList();
    final fg = context.fg;
    return Column(children: [
      Expanded(
        child: FgRefresh(
          onRefresh: () => ref.refresh(orderMessagesProvider(widget.orderId).future),
          child: AsyncBody(
            value: messages,
            onRetry: () => ref.invalidate(orderMessagesProvider(widget.orderId)),
            builder: (list) => list.isEmpty && queued.isEmpty
                ? ListView(children: [EmptyState(art: FgArt.empty, title: s.t('noMessages'), message: s.t('noMessagesHint'))])
                : ListView(
                    reverse: true,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(FgSpace.gutter),
                    children: [
                      for (final q in queued.reversed) _Bubble(text: _queuedText(q), name: s.t('waitingToSend'), time: q.createdAt.toLocal(), mine: true, pending: true),
                      for (final m in list.reversed)
                        _Bubble(
                          text: m.s('text'),
                          name: m.s('senderName').isEmpty ? s.status(m.s('sender')) : m.s('senderName'),
                          time: m.d('sent'),
                          mine: m.s('sender') == widget.mySide,
                          system: m.s('sender') == 'System',
                          attachment: m.s('attachment'),
                        ),
                    ],
                  ),
          ),
        ),
      ),
      Material(
        color: fg.surface,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: fg.border))),
          padding: const EdgeInsets.fromLTRB(FgSpace.s3, FgSpace.s2, FgSpace.s2, FgSpace.s2),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: s.t('writeMessage'), counterText: ''),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: FgSpace.s2),
              IconButton.filled(
                tooltip: s.t('send'),
                style: IconButton.styleFrom(backgroundColor: fg.action, foregroundColor: fg.onAction, minimumSize: const Size(48, 48)),
                onPressed: _sending ? null : _send,
                icon: const Icon(FgIcons.send),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  static String _queuedText(OutboxItem item) {
    try {
      final body = jsonDecode(item.body ?? '{}');
      if (body is Map && body['text'] is String) return body['text'] as String;
    } on FormatException {
      // fall through to the label
    }
    return item.label;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.name, required this.time, required this.mine, this.pending = false, this.system = false, this.attachment = ''});
  final String text;
  final String name;
  final DateTime? time;
  final bool mine;
  final bool pending;
  final bool system;
  final String attachment;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    final bg = system ? fg.surface2 : (mine ? fg.primaryBg : fg.surface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FgSpace.s1),
      child: Align(
        alignment: system ? AlignmentDirectional.center : (mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: FgSpace.s3, vertical: FgSpace.s2),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: mine ? fg.primary.withValues(alpha: 0.3) : fg.border),
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(FgRadius.lg),
                topEnd: const Radius.circular(FgRadius.lg),
                bottomStart: Radius.circular(mine ? FgRadius.lg : FgRadius.sm),
                bottomEnd: Radius.circular(mine ? FgRadius.sm : FgRadius.lg),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name, style: context.tt.labelSmall?.copyWith(color: mine ? fg.primary : fg.textMuted, fontWeight: FontWeight.w600)),
              if (text.isNotEmpty) ...[const SizedBox(height: 2), Text(text, style: context.tt.bodyMedium)],
              if (attachment.isNotEmpty) ...[
                const SizedBox(height: FgSpace.s2),
                PhotoTile(
                  size: 120,
                  photo: FgPhoto(builder: (fit) => EvidenceImage(attachment, fit: fit)),
                  onTap: () => PhotoViewer.open(context, [FgPhoto(builder: (fit) => EvidenceImage(attachment, fit: fit))], 0),
                ),
              ],
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (pending) ...[Icon(FgIcons.waiting, size: 12, color: fg.textMuted), const SizedBox(width: 4)],
                Text(time == null ? '' : '${fmtShortDate(time, Localizations.localeOf(context).languageCode)} ${fmtTime(time, Localizations.localeOf(context).languageCode)}',
                    style: context.tt.labelSmall?.copyWith(fontFeatures: FgFonts.tabular)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Full-screen message thread of a service order (both apps).
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key, required this.orderId, required this.mySide});
  final String orderId;
  final String mySide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('${s.t('messages')} · $orderId'),
        actions: [IconButton(tooltip: s.t('refresh'), icon: const Icon(FgIcons.refresh), onPressed: () {
          FgHaptics.light();
          ref.invalidate(orderMessagesProvider(orderId));
        })],
      ),
      body: MessageThread(orderId: orderId, mySide: mySide),
    );
  }
}
