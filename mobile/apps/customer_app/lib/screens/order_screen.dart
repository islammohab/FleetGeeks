import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'documents.dart';

final orderProvider = FutureProvider.autoDispose.family<FgRow, String>(
  (ref, id) async => asRow(await ref.watch(apiProvider).get('/service-orders/${Uri.encodeComponent(id)}')),
);

final estimateProvider = FutureProvider.autoDispose.family<FgRow, String>(
  (ref, id) async => asRow(await ref.watch(apiProvider).get('/estimates/${Uri.encodeComponent(id)}')),
);

/// Photos of a service order (evidence rows that are images), newest first.
List<FgPhoto> orderPhotos(List<FgRow> evidence, Strings s) => [
      for (final e in evidence.where(isImageEvidence))
        FgPhoto(
          builder: (fit) => EvidenceImage(e.s('EvidenceId'), fit: fit),
          label: s.status(e.s('Category')),
          caption: fmtDate(e.d('CapturedDateTime'), s.lang),
          category: e.s('Category'),
        ),
    ];

/// Service order for the customer: stage tracker (Requested → Released) with "what happens next", messages, estimates
/// waiting for a decision, live job progress, checks (incl. delivery), photos with a before / after slider, documents
/// (PDF), payment, the D365 timeline and the promise history.
class OrderScreen extends ConsumerWidget {
  const OrderScreen({super.key, required this.orderId});
  final String orderId;

  void _refreshAll(WidgetRef ref) {
    ref.invalidate(orderProvider(orderId));
    ref.invalidate(orderTimelineProvider(orderId));
    ref.invalidate(orderProgressProvider(orderId));
    ref.invalidate(orderChecklistsProvider(orderId));
    ref.invalidate(orderDocumentsProvider(orderId));
    ref.invalidate(unreadMessagesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final user = ref.watch(authProvider).value;
    final approver = user?.has(['RepairApprover', 'FleetManager', 'CustomerAdmin']) ?? false;
    final detail = ref.watch(orderProvider(orderId));
    final unread = unreadByOrder(ref.watch(unreadMessagesProvider).value)[orderId] ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(orderId), actions: [
        IconButton(
          tooltip: s.t('messages'),
          onPressed: () => context.push('/orders/${Uri.encodeComponent(orderId)}/messages'),
          icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(FgIcons.messages)),
        ),
        OutboxButton(onPressed: () => context.push('/outbox')),
      ]),
      bottomNavigationBar: OfflineBanner(safeArea: true, onOpenOutbox: () => context.push('/outbox')),
      body: FgRefresh(
        onRefresh: () async {
          _refreshAll(ref);
          await ref.read(orderProvider(orderId).future);
        },
        child: AsyncBody(
          value: detail,
          loading: const SkeletonList(header: true, count: 4),
          onRetry: () => ref.invalidate(orderProvider(orderId)),
          builder: (d) {
            final o = asRow(d['order']);
            final status = o.s('Status');
            final submitted = asRows(d['estimates']).where((e) => e.s('Status') == 'Submitted').toList();
            final evidence = asRows(d['evidence']);
            final photos = orderPhotos(evidence, s);
            final photoById = {
              for (final e in evidence.where(isImageEvidence))
                e.s('EvidenceId'): FgPhoto(builder: (fit) => EvidenceImage(e.s('EvidenceId'), fit: fit), label: s.status(e.s('Category')), category: e.s('Category')),
            };
            final promises = asRows(d['promiseHistory']);
            final promise = o.d('CurrentPromise');
            final deposit = o.n('DepositRequired') - o.n('DepositPaid');
            final canPay = deposit > 0 || const {'ReadyForCollection', 'Released', 'Closed'}.contains(status);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(FgSpace.s4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        IconTile(FgIcons.status(status), tone: toneOf(status)),
                        const SizedBox(width: FgSpace.s3),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${s.t('vehicle')} ${o.s('VehicleId')}', style: context.tt.titleMedium),
                            Text(s.status(o.s('ServiceType')), style: context.tt.bodySmall),
                          ]),
                        ),
                        StatusPill(status),
                      ]),
                      if (promise != null && isOrderOpen(status)) ...[
                        const SizedBox(height: FgSpace.s3),
                        KeyValueRow(s.t('promise'), '${fmtDate(promise, s.lang)}\n${promiseText(s, promise)}', icon: FgIcons.promise),
                      ],
                      if (o.s('Complaint').isNotEmpty) KeyValueRow(s.t('complaint'), o.s('Complaint'), icon: FgIcons.fault),
                      if (o.s('SafetyHold') == 'Yes') ...[
                        const SizedBox(height: FgSpace.s2),
                        FgNotice(tone: FgTone.bad, icon: FgIcons.safety, message: s.t('safetyHoldText')),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: FgSpace.s3),
                FgListCard(
                  leading: IconTile(FgIcons.messages, tone: unread > 0 ? FgTone.attention : FgTone.progress),
                  title: s.t('messages'),
                  subtitle: unread > 0 ? s.t('unreadMessages', [unread]) : s.t('messagesHint'),
                  trailing: unread > 0 ? CountPill(unread, tone: FgTone.attention) : null,
                  onTap: () => context.push('/orders/${Uri.encodeComponent(orderId)}/messages'),
                ),
                for (final e in submitted) ...[
                  const SizedBox(height: FgSpace.s3),
                  _EstimateCard(orderId: orderId, estimate: e, canDecide: approver),
                ],
                if (canPay) ...[
                  const SizedBox(height: FgSpace.s3),
                  _PaymentCard(orderId: orderId, order: o),
                ],
                const SizedBox(height: FgSpace.s3),
                SectionCard(
                  title: s.t('progress'),
                  icon: FgIcons.timeline,
                  children: [
                    OrderProgress(status: status, times: {
                      'Arrived': o.d('ArrivedDateTime'),
                      'Ready': o.d('ReadyDateTime'),
                      'Released': o.d('ReleasedDateTime'),
                    }),
                  ],
                ),
                const SizedBox(height: FgSpace.s3),
                SectionCard(title: s.t('jobs'), icon: FgIcons.tasks, children: [JobProgressList(orderId: orderId)]),
                const SizedBox(height: FgSpace.s3),
                SectionCard(title: s.t('checks'), icon: FgIcons.checklist, children: [ChecklistResults(orderId: orderId)]),
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: FgSpace.s3),
                  SectionCard(title: s.t('photos'), icon: FgIcons.gallery, trailing: CountPill(photos.length), children: [PhotoGallery(photos: photos)]),
                ],
                const SizedBox(height: FgSpace.s3),
                SectionCard(title: s.t('documents'), icon: FgIcons.document, children: [_Documents(orderId: orderId)]),
                const SizedBox(height: FgSpace.s3),
                SectionCard(title: s.t('activity'), icon: FgIcons.history, children: [OrderEventsTimeline(orderId: orderId, photos: photoById)]),
                const SizedBox(height: FgSpace.s3),
                SectionCard(
                  title: s.t('promiseHistory'),
                  icon: FgIcons.promise,
                  children: [
                    if (promises.isEmpty) Text(s.t('noData'), style: context.tt.bodySmall),
                    if (promises.isNotEmpty)
                      FgTimeline(entries: [
                        for (final p in promises)
                          FgTimelineEntry(
                            title: fmtDate(p.d('PromisedReady'), s.lang),
                            subtitle: p.s('CustomerText'),
                            icon: FgIcons.promise,
                            tone: FgTone.info,
                          ),
                      ]),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// PDF documents of the order (condition report, estimate, release note, invoice …); tap downloads and opens.
class _Documents extends ConsumerWidget {
  const _Documents({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return switch (ref.watch(orderDocumentsProvider(orderId))) {
      AsyncData(:final value) => value.isEmpty
          ? Text(s.t('noDocumentsYet'), style: context.tt.bodySmall)
          : Column(children: [
              for (final doc in value)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const IconTile(FgIcons.document, size: 40),
                  title: Text(s.status(doc.s('documentType'))),
                  subtitle: Text([doc.s('fileName'), fmtDate(doc.d('at'), s.lang)].where((x) => x.isNotEmpty && x != '—').join(' · ')),
                  trailing: const Icon(FgIcons.download, size: 20),
                  onTap: () => openPdf(
                    context,
                    ref,
                    '/documents/${Uri.encodeComponent(doc.s('evidenceId'))}',
                    doc.s('fileName').isEmpty ? '${doc.s('documentType')}-$orderId.pdf' : doc.s('fileName'),
                  ),
                ),
            ]),
      AsyncError(:final error) => ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(orderDocumentsProvider(orderId))),
      _ => const Shimmer(child: Column(children: [SkeletonBox(), SizedBox(height: 8), SkeletonBox(width: 180)])),
    };
  }
}

/// Deposit or final payment: online through the provider link, otherwise at the counter / on account.
class _PaymentCard extends ConsumerStatefulWidget {
  const _PaymentCard({required this.orderId, required this.order});
  final String orderId;
  final FgRow order;

  @override
  ConsumerState<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends ConsumerState<_PaymentCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final o = widget.order;
    final deposit = o.n('DepositRequired') - o.n('DepositPaid');
    return SectionCard(
      title: s.t('payment'),
      icon: FgIcons.wallet,
      children: [
        if (deposit > 0) KeyValueRow(s.t('depositDue'), fmtMoney(deposit, ''), tabular: true),
        Text(s.t('paymentHint'), style: context.tt.bodySmall),
        const SizedBox(height: FgSpace.s3),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await startPayment(context, ref, widget.orderId);
                  if (mounted) setState(() => _busy = false);
                },
          icon: _busy
              ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.fg.onAction))
              : const Icon(FgIcons.payment, size: 18),
          label: Text(s.t('payNow')),
        ),
      ],
    );
  }
}


/// Estimate waiting for the customer (wave 5, D-077): lines per job group, an explicit approve / decline per group (nothing
/// is approved by default), a reason when declining, confirmation of version and amount; 409 shows the current version.
class _EstimateCard extends ConsumerStatefulWidget {
  const _EstimateCard({required this.orderId, required this.estimate, required this.canDecide});
  final String orderId;
  final FgRow estimate;
  final bool canDecide;

  @override
  ConsumerState<_EstimateCard> createState() => _EstimateCardState();
}

class _EstimateCardState extends ConsumerState<_EstimateCard> {
  final Map<int, bool> _approve = {};
  String _reasonCode = '';
  final _note = TextEditingController();
  List<FgRow> _reasons = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).get('/lookups/reasons', query: {'type': 'EstimateDecline'}).then((r) {
      if (mounted) setState(() => _reasons = asRows(r));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _label(Strings s, FgRow g) => g.n('jobLine').round() == 0 ? s.t('estGeneral') : (g.s('description').isNotEmpty ? g.s('description') : s.t('estJobGroup', [g.n('jobLine').round()]));

  /// D-106: lines waiting for the customer's decision (information-only lines need none).
  List<FgRow> _decidable(List<FgRow> lines) => lines.where((l) => l.s('InformationOnly') != 'Yes' && (l.s('Decision').isEmpty || l.s('Decision') == 'Pending')).toList();
  int _no(FgRow l) => l.n('LineNum').round();

  Future<void> _send(Strings s, List<FgRow> lines, String currency) async {
    final declined = lines.where((l) => _approve[_no(l)] == false).toList();
    final accepted = lines.where((l) => _approve[_no(l)] == true).toList();
    final amount = accepted.fold<double>(0, (a, l) => a + l.n('PayableAmount') + l.n('TaxAmount'));
    final rounded = (amount * 100).round() / 100;
    final version = int.tryParse(widget.estimate.s('Version')) ?? widget.estimate.n('Version').round();
    final id = widget.estimate.s('EstimateId');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('estConfirmTitle')),
        content: Text([
          s.t('estConfirmLines', [fmtMoney(rounded, currency), accepted.length, lines.length, id, version]),
          if (declined.isNotEmpty) s.t('estConfirmRejected', [declined.map((l) => l.s('Description')).join(', ')]),
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('back'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('estConfirm'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final danger = context.fg.danger;
    try {
      await ref.read(apiProvider).post('/estimates/${Uri.encodeComponent(id)}/decision', idempotencyKey: const Uuid().v4(), body: {
        'version': version,
        'lines': [for (final l in lines) {'line': _no(l), 'decision': _approve[_no(l)]! ? 'Approved' : 'Declined'}],
        if (declined.isNotEmpty && _reasonCode.isNotEmpty) 'reasonCode': _reasonCode,
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        'confirmedAmount': rounded,
      });
      FgHaptics.success();
      messenger.showSnackBar(SnackBar(content: Text(s.t('decisionSaved'))));
      ref.invalidate(orderProvider(widget.orderId));
    } on ApiException catch (err) {
      FgHaptics.warning();
      messenger.showSnackBar(SnackBar(backgroundColor: danger, content: Text(err.isConflict ? '${s.t('estChangedTitle')}: ${err.message}' : err.message)));
      if (err.isConflict) {
        ref.invalidate(orderProvider(widget.orderId));
        ref.invalidate(estimateProvider(id));
      }
    } catch (err) {
      FgHaptics.warning();
      messenger.showSnackBar(SnackBar(backgroundColor: danger, content: Text('$err')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    final id = widget.estimate.s('EstimateId');
    final detail = ref.watch(estimateProvider(id));
    final currency = widget.estimate.s('CurrencyCode');
    return Card(
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: fg.action, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: fg.actionBg,
          padding: const EdgeInsets.all(FgSpace.s4),
          child: Row(children: [
            Icon(FgIcons.estimate, color: fg.action),
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.t('estimate')} $id · v${widget.estimate.s('Version')}', style: context.tt.titleMedium),
                Text(s.t(widget.canDecide ? 'estimateWaiting' : 'estimateWaitingOther'), style: context.tt.bodySmall),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(FgSpace.s4),
          child: switch (detail) {
            AsyncData(:final value) => _body(context, s, value, currency),
            AsyncError(:final error) => ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(estimateProvider(id))),
            _ => const Shimmer(child: Column(children: [SkeletonBox(), SizedBox(height: 8), SkeletonBox(), SizedBox(height: 8), SkeletonBox(width: 120)])),
          },
        ),
      ]),
    );
  }

  Widget _body(BuildContext context, Strings s, FgRow e, String currency) {
    final fg = context.fg;
    final lines = asRows(e['lines']);
    final groups = asRows(e['groups']);
    final toDecide = _decidable(lines);
    final head = asRow(e['estimate']);
    final money = context.tt.bodyMedium?.copyWith(fontFeatures: FgFonts.tabular, fontWeight: FontWeight.w500);
    final undecided = toDecide.where((l) => _approve[_no(l)] == null).length;
    final anyDeclined = toDecide.any((l) => _approve[_no(l)] == false);
    final reasonMissing = anyDeclined && _reasonCode.isEmpty && _note.text.trim().isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.canDecide && toDecide.isNotEmpty) ...[
        Text(s.t('estNoDefaultLines'), style: context.tt.bodySmall),
        const SizedBox(height: FgSpace.s2),
        Wrap(spacing: FgSpace.s2, children: [
          OutlinedButton(onPressed: () => setState(() => [for (final l in toDecide) _approve[_no(l)] = true]), child: Text(s.t('estAcceptAll'))),
          OutlinedButton(onPressed: () => setState(() => [for (final l in toDecide) _approve[_no(l)] = false]), child: Text(s.t('estRejectAll'))),
        ]),
        const SizedBox(height: FgSpace.s3),
      ],
      for (final g in groups) ...[
        Text(_label(s, g), style: context.tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        for (final l in lines.where((l) => l.n('JobLineNum').round() == g.n('jobLine').round()))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.s('Description'), style: context.tt.bodyMedium),
                  Text('${fmtNum(l.n('Quantity'), decimals: l.n('Quantity') % 1 == 0 ? 0 : 2)} ${l.s('Unit')} × ${fmtMoney(l.n('UnitPrice'), currency)}${l.s('InformationOnly') == 'Yes' ? ' · ${s.t('estPreAuthorized')}' : ''}', style: context.tt.bodySmall),
                ]),
              ),
              const SizedBox(width: FgSpace.s3),
              Text(fmtMoney(l.n('PayableAmount'), currency), style: money),
            ]),
          ),
        // D-106: accept or reject each line of the job
        for (final l in toDecide.where((l) => l.n('JobLineNum').round() == g.n('jobLine').round()))
          if (widget.canDecide)
            Padding(
              padding: const EdgeInsets.only(bottom: FgSpace.s2),
              child: Row(children: [
                Expanded(child: Text(l.s('Description'), style: context.tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  segments: [
                    ButtonSegment(value: true, icon: const Icon(FgIcons.approve, size: 16), tooltip: s.t('estAccept'), label: Text(s.t('estAccept'))),
                    ButtonSegment(value: false, icon: const Icon(FgIcons.decline, size: 16), tooltip: s.t('estReject'), label: Text(s.t('estReject'))),
                  ],
                  selected: _approve[_no(l)] == null ? <bool>{} : {_approve[_no(l)]!},
                  onSelectionChanged: (v) {
                    FgHaptics.tap();
                    setState(() => v.isEmpty ? _approve.remove(_no(l)) : _approve[_no(l)] = v.first);
                  },
                ),
              ]),
            ),
        const SizedBox(height: FgSpace.s3),
      ],
      const Divider(height: FgSpace.s5),
      if (head.n('TaxAmount') != 0) KeyValueRow(s.t('tax'), fmtMoney(head.n('TaxAmount'), currency), tabular: true),
      Row(children: [
        Expanded(child: Text(s.t('total'), style: context.tt.titleMedium)),
        Text(
          fmtMoney(head.n('TotalInclTax') != 0 ? head.n('TotalInclTax') : head.n('PayableAmount'), currency),
          style: context.tt.titleLarge?.copyWith(fontFeatures: FgFonts.tabular, fontWeight: FontWeight.w700),
        ),
      ]),
      if (widget.canDecide && toDecide.isNotEmpty) ...[
        if (anyDeclined) ...[
          const SizedBox(height: FgSpace.s3),
          DropdownButtonFormField<String>(
            value: _reasonCode.isEmpty ? null : _reasonCode,
            decoration: InputDecoration(labelText: s.t('estDeclineReasonCode')),
            items: [for (final r in _reasons) DropdownMenuItem(value: r.s('id'), child: Text(s.lang == 'ar' && r.s('nameAr').isNotEmpty ? r.s('nameAr') : r.s('name')))],
            onChanged: (v) => setState(() => _reasonCode = v ?? ''),
          ),
          const SizedBox(height: FgSpace.s2),
          TextField(controller: _note, maxLength: 255, decoration: InputDecoration(labelText: s.t('estDecisionNote')), onChanged: (_) => setState(() {})),
        ],
        const SizedBox(height: FgSpace.s2),
        if (undecided > 0) Text(s.t('estUndecided', [undecided]), style: context.tt.bodySmall),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy || undecided > 0 || reasonMissing ? null : () => _send(s, toDecide, currency),
          icon: _busy
              ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg.onAction))
              : const Icon(FgIcons.send, size: 18),
          label: Text(s.t('sendDecision')),
        ),
      ],
    ]);
  }
}