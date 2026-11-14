import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gate_screen.dart' show QrScanPage;
import 'providers.dart';

/// Custody roles a vehicle can be handed to (FGCustodyRole, same list as the Workshop Portal).
const custodyRoles = ['Customer', 'Gate', 'Reception', 'Workshop', 'Technician', 'Stores', 'Partner', 'QC', 'Cashier', 'Collector'];

/// Prompt 2 (4.8) / 3 (B2): the roles the custody chain allows now for the order, the usual next one, the active staff of
/// each custody role in the order's workshop and whether the caller may hand over outside the chain (workshop manager).
/// Null when the API refused (older API): the full role list is offered and D365 still checks the chain.
final handoverRolesProvider = FutureProvider.autoDispose.family<FgRow?, String>((ref, orderId) async {
  try {
    return asRow(await ref.watch(apiProvider).get('/workshop/service-orders/${Uri.encodeComponent(orderId)}/handover-roles'));
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
    return null;
  }
});

/// Offer a handover (POST /workshop/handovers) through the outbox. Only the roles the custody chain allows are listed,
/// the usual next one preselected; the receiver is picked from the active staff of that role or read from their badge QR.
/// The workshop manager may hand over outside the chain with a reason (POST /workshop/handovers/override, written to the
/// custody history). A late handover back from the workshop is refused by D365 (422 "delay ...") until it carries a
/// delay reason (reasons LateHandover, or Delay codes LH-*) and a note: the card then asks for them and sends the offer again.
class OfferHandoverCard extends ConsumerStatefulWidget {
  const OfferHandoverCard({super.key, required this.orderId, required this.order});
  final String orderId;
  final FgRow order;

  @override
  ConsumerState<OfferHandoverCard> createState() => _OfferHandoverCardState();
}

class _OfferHandoverCardState extends ConsumerState<OfferHandoverCard> {
  String? _toRole;
  final _toParty = TextEditingController();
  final _toUser = TextEditingController();
  final _odometer = TextEditingController();
  final _fuel = TextEditingController();
  final _keys = TextEditingController(text: '1');
  final _condition = TextEditingController();
  final _overrideReason = TextEditingController();
  bool _override = false;
  bool _busy = false;
  bool _open = false;

  @override
  void dispose() {
    for (final c in [_toParty, _toUser, _odometer, _fuel, _keys, _condition, _overrideReason]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Roles offered now: the chain's allowed roles (all roles while overriding, or when the API sent none).
  List<String> _roles(FgRow? info) {
    final allowed = [for (final r in (info?['allowed'] is List ? info!['allowed'] as List : const [])) '$r'];
    return _override || allowed.isEmpty ? custodyRoles : allowed;
  }

  /// Active staff of a custody role ({user, name}).
  List<FgRow> _staff(FgRow? info, String role) {
    final staff = info?['staff'];
    return staff is Map ? asRows(staff[role]) : const [];
  }

  /// Scans a staff badge (or a customer's arrival QR) and fills role, receiver and user from it.
  Future<void> _scanBadge() async {
    final s = ref.read(stringsProvider);
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => QrScanPage(title: s.t('scanBadge'), hint: s.t('scanBadgeHint'))));
    if (code == null || !mounted) return;
    try {
      final r = asRow(await ref.read(apiProvider).post('/workshop/badges/resolve', body: {'code': code}));
      setState(() {
        if (r.s('toRole').isNotEmpty) _toRole = r.s('toRole');
        _toParty.text = r.s('toParty');
        _toUser.text = r.s('toUser');
      });
      if (mounted) showDone(context, s.t('badgeRead', [r.s('toParty')]));
    } catch (e) {
      if (mounted) showError(context, e);
    }
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

  Future<void> _offer(String role, {String? delayReason, String? delayNote}) async {
    final s = ref.read(stringsProvider);
    if (_toParty.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = _override
          // prompt 2 (4.8): outside the custody chain, workshop manager only, reason kept in the custody history
          ? await ref.read(outboxProvider.notifier).submit('/workshop/handovers/override', label: '${s.t('handoverOverride')} · ${widget.orderId} → ${s.status(role)}', body: {
              'serviceOrderId': widget.orderId,
              'toRole': role,
              'toParty': _toParty.text.trim(),
              'toUser': _toUser.text.trim(),
              'odometer': _num(_odometer),
              'fuelPercent': _num(_fuel).clamp(0, 100),
              'condition': _condition.text.trim(),
              'keys': int.tryParse(_keys.text.trim()) ?? 0,
              'reason': _overrideReason.text.trim(),
            })
          : await ref.read(outboxProvider.notifier).submit('/workshop/handovers', label: '${s.t('offerHandover')} · ${widget.orderId} → ${s.status(role)}', body: {
              'serviceOrderId': widget.orderId,
              'toRole': role,
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
      ref.invalidate(handoverRolesProvider(widget.orderId));
    } on ApiException catch (e) {
      if (!_override && e.status == 422 && e.message.toLowerCase().contains('delay') && delayReason == null && mounted) {
        setState(() => _busy = false);
        FgHaptics.warning();
        final reasons = await _delayReasons();
        if (!mounted) return;
        final answer = await showModalBottomSheet<(String, String)>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _DelaySheet(reasons: reasons, message: e.message),
        );
        if (answer != null && mounted) await _offer(role, delayReason: answer.$1, delayNote: answer.$2);
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
    final rolesInfo = ref.watch(handoverRolesProvider(widget.orderId));
    final info = rolesInfo.value;
    final roles = _roles(info);
    final suggested = info?.s('suggested') ?? '';
    // the usual next role is preselected (never a fixed default); a role no longer allowed falls back to it
    final role = _toRole != null && roles.contains(_toRole) ? _toRole! : (roles.contains(suggested) ? suggested : roles.first);
    final staff = _staff(info, role);
    final canOverride = info?['canOverride'] == true;
    final selectedStaff = staff.any((u) => u.s('user') == _toUser.text.trim()) ? _toUser.text.trim() : null;
    final ready = _toParty.text.trim().isNotEmpty && (!_override || _overrideReason.text.trim().isNotEmpty);
    return SectionCard(
      title: s.t('offerHandover'),
      icon: FgIcons.handover,
      trailing: IconButton(tooltip: s.t('cancel'), icon: const Icon(FgIcons.close), onPressed: () => setState(() => _open = false)),
      children: [
        if (rolesInfo.isLoading && info == null) const LinearProgressIndicator(),
        if (info != null && !_override) ...[
          Text(s.t('handoverChainHint'), style: context.tt.bodySmall),
          const SizedBox(height: FgSpace.s2),
        ],
        DropdownButtonFormField<String>(
          key: ValueKey('role-$role-${roles.length}-$_override'),
          initialValue: role,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.t('toRole')),
          items: [
            for (final r in roles)
              DropdownMenuItem(value: r, child: Text(r == suggested ? '${s.status(r)} · ${s.t('toRoleUsual')}' : s.status(r))),
          ],
          onChanged: (v) => setState(() {
            _toRole = v;
            _toUser.clear();
            _toParty.clear();
          }),
        ),
        const SizedBox(height: FgSpace.s3),
        if (staff.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('staff-$role-$selectedStaff'),
            initialValue: selectedStaff,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.t('toPartyStaff'), prefixIcon: const Icon(FgIcons.technician, size: 20)),
            items: [for (final u in staff) DropdownMenuItem(value: u.s('user'), child: Text(u.s('name').isEmpty ? u.s('user') : u.s('name'), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() {
              final u = staff.firstWhere((x) => x.s('user') == v);
              _toUser.text = u.s('user');
              _toParty.text = u.s('name').isEmpty ? u.s('user') : u.s('name');
            }),
          ),
          const SizedBox(height: FgSpace.s3),
        ],
        TextField(
          controller: _toParty,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: s.t('toParty'), prefixIcon: const Icon(FgIcons.driver, size: 20)),
        ),
        const SizedBox(height: FgSpace.s3),
        TextField(controller: _toUser, decoration: InputDecoration(labelText: s.t('toUser'))),
        const SizedBox(height: FgSpace.s2),
        OutlinedButton.icon(onPressed: _busy ? null : _scanBadge, icon: const Icon(FgIcons.qr, size: 18), label: Text(s.t('scanBadge'))),
        if (canOverride) ...[
          const SizedBox(height: FgSpace.s2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _override,
            title: Text(s.t('handoverOverride')),
            subtitle: Text(s.t('handoverOverrideHint'), style: context.tt.bodySmall),
            onChanged: (v) => setState(() => _override = v),
          ),
          if (_override)
            TextField(
              controller: _overrideReason,
              maxLength: 255,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: s.t('handoverOverrideReason')),
            ),
        ],
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
          onPressed: _busy || !ready ? null : () => _offer(role),
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
