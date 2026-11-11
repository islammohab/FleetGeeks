import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Custody roles a vehicle can be handed to (FGCustodyRole, same list as the Workshop Portal).
const custodyRoles = ['Customer', 'Gate', 'Reception', 'Workshop', 'Technician', 'Stores', 'Partner', 'QC', 'Cashier', 'Collector'];

/// Offer a handover (POST /workshop/handovers) through the outbox. A late handover back from the workshop is refused by
/// D365 (422 "delay ...") until it carries a delay reason (reasons LateHandover, or Delay codes LH-*) and a note: the
/// card then asks for them and sends the offer again.
class OfferHandoverCard extends ConsumerStatefulWidget {
  const OfferHandoverCard({super.key, required this.orderId, required this.order});
  final String orderId;
  final FgRow order;

  @override
  ConsumerState<OfferHandoverCard> createState() => _OfferHandoverCardState();
}

class _OfferHandoverCardState extends ConsumerState<OfferHandoverCard> {
  String _toRole = 'Customer';
  final _toParty = TextEditingController();
  final _toUser = TextEditingController();
  final _odometer = TextEditingController();
  final _fuel = TextEditingController();
  final _keys = TextEditingController(text: '1');
  final _condition = TextEditingController();
  bool _busy = false;
  bool _open = false;

  @override
  void dispose() {
    for (final c in [_toParty, _toUser, _odometer, _fuel, _keys, _condition]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  Future<List<FgRow>> _delayReasons() async {
    final rows = <FgRow>[];
    try {
      rows.addAll(await ref.read(lookupProvider('reasons?type=LateHandover').future));
    } on ApiException {
      // fall back to the Delay codes below
    }
    try {
      final delay = await ref.read(lookupProvider('reasons?type=Delay').future);
      rows.addAll(delay.where((r) => r.s('id').startsWith('LH-') && rows.every((x) => x.s('id') != r.s('id'))));
    } on ApiException {
      // keep what we have
    }
    return rows;
  }

  Future<void> _offer({String? delayReason, String? delayNote}) async {
    final s = ref.read(stringsProvider);
    if (_toParty.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref.read(outboxProvider.notifier).submit('/workshop/handovers', label: '${s.t('offerHandover')} · ${widget.orderId} → ${s.status(_toRole)}', body: {
        'serviceOrderId': widget.orderId,
        'toRole': _toRole,
        'toParty': _toParty.text.trim(),
        'toUser': _toUser.text.trim(),
        'location': widget.order.s('Workshop'),
        'odometer': _num(_odometer),
        'fuelPercent': _num(_fuel).clamp(0, 100),
        'condition': _condition.text.trim(),
        'keys': int.tryParse(_keys.text.trim()) ?? 0,
        'delayReason': delayReason,
        'delayNote': delayNote,
      });
      FgHaptics.success();
      messenger.showSnackBar(SnackBar(content: Text(r.queued ? s.t('queued') : s.t('handoverOffered'))));
      if (mounted) setState(() => _open = false);
      ref.invalidate(orderProvider(widget.orderId));
    } on ApiException catch (e) {
      if (e.status == 422 && e.message.toLowerCase().contains('delay') && delayReason == null && mounted) {
        setState(() => _busy = false);
        FgHaptics.warning();
        final reasons = await _delayReasons();
        if (!mounted) return;
        final answer = await showModalBottomSheet<(String, String)>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _DelaySheet(reasons: reasons, message: e.message),
        );
        if (answer != null && mounted) await _offer(delayReason: answer.$1, delayNote: answer.$2);
        return;
      }
      FgHaptics.warning();
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    const decimal = TextInputType.numberWithOptions(decimal: true);
    const tabular = TextStyle(fontFeatures: FgFonts.tabular);
    if (!_open) {
      return FgBigButton(
        icon: FgIcons.handover,
        label: s.t('offerHandover'),
        caption: s.t('offerHandoverCaption'),
        kind: FgButtonKind.neutral,
        height: 64,
        onPressed: () => setState(() => _open = true),
      );
    }
    return SectionCard(
      title: s.t('offerHandover'),
      icon: FgIcons.handover,
      trailing: IconButton(tooltip: s.t('cancel'), icon: const Icon(FgIcons.close), onPressed: () => setState(() => _open = false)),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _toRole,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.t('toRole')),
          items: [for (final r in custodyRoles) DropdownMenuItem(value: r, child: Text(s.status(r)))],
          onChanged: (v) => setState(() => _toRole = v ?? 'Customer'),
        ),
        const SizedBox(height: FgSpace.s3),
        TextField(
          controller: _toParty,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: s.t('toParty'), prefixIcon: const Icon(FgIcons.driver, size: 20)),
        ),
        const SizedBox(height: FgSpace.s3),
        TextField(controller: _toUser, decoration: InputDecoration(labelText: s.t('toUser'))),
        const SizedBox(height: FgSpace.s3),
        Row(children: [
          Expanded(child: TextField(controller: _odometer, keyboardType: decimal, style: tabular, decoration: InputDecoration(labelText: s.t('odometer'), suffixText: 'km'))),
          const SizedBox(width: FgSpace.s2),
          Expanded(child: TextField(controller: _fuel, keyboardType: decimal, style: tabular, decoration: InputDecoration(labelText: s.t('fuelLevel'), suffixText: '%'))),
          const SizedBox(width: FgSpace.s2),
          Expanded(child: TextField(controller: _keys, keyboardType: TextInputType.number, style: tabular, decoration: InputDecoration(labelText: s.t('keys')))),
        ]),
        const SizedBox(height: FgSpace.s3),
        TextField(controller: _condition, minLines: 2, maxLines: 3, decoration: InputDecoration(labelText: s.t('conditionNotes'), alignLabelWithHint: true)),
        const SizedBox(height: FgSpace.s3),
        FilledButton.icon(
          onPressed: _busy || _toParty.text.trim().isEmpty ? null : () => _offer(),
          icon: _busy
              ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.fg.onAction))
              : const Icon(FgIcons.send, size: 18),
          label: Text(s.t('offerHandover')),
        ),
      ],
    );
  }
}

/// Late handover: reason code + note; pops (reason, note).
class _DelaySheet extends ConsumerStatefulWidget {
  const _DelaySheet({required this.reasons, required this.message});
  final List<FgRow> reasons;
  final String message;

  @override
  ConsumerState<_DelaySheet> createState() => _DelaySheetState();
}

class _DelaySheetState extends ConsumerState<_DelaySheet> {
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final ready = _reason != null && _note.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(FgSpace.gutter, 0, FgSpace.gutter, FgSpace.s4 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.t('lateHandover'), style: context.tt.titleLarge),
            const SizedBox(height: FgSpace.s2),
            FgNotice(tone: FgTone.attention, icon: FgIcons.promise, message: widget.message),
            const SizedBox(height: FgSpace.s3),
            if (widget.reasons.isEmpty)
              Text(s.t('noDelayReasons'), style: context.tt.bodySmall)
            else
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.t('delayReason')),
                items: [
                  for (final r in widget.reasons)
                    DropdownMenuItem(
                      value: r.s('id'),
                      child: Text('${r.s('id')} – ${s.lang == 'ar' && r.s('nameAr').isNotEmpty ? r.s('nameAr') : r.s('name')}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _reason = v),
              ),
            const SizedBox(height: FgSpace.s3),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: s.t('delayNote'), alignLabelWithHint: true),
            ),
            const SizedBox(height: FgSpace.s4),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: ready ? () => Navigator.pop(context, (_reason!, _note.text.trim())) : null,
              icon: const Icon(FgIcons.send, size: 18),
              label: Text(s.t('offerHandover')),
            ),
          ]),
        ),
      ),
    );
  }
}
