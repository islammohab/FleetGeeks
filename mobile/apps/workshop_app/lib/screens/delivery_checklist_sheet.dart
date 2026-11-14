import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Delivery checklist before the vehicle goes back to the customer (advisor): questions from the DELIVERY checklist
/// template, pass / fail with a note per item, sent in one command through the outbox
/// (POST /workshop/service-orders/{id}/delivery-checklist).
class DeliveryChecklistSheet extends ConsumerStatefulWidget {
  const DeliveryChecklistSheet({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<DeliveryChecklistSheet> createState() => _DeliveryChecklistSheetState();
}

class _DeliveryChecklistSheetState extends ConsumerState<DeliveryChecklistSheet> {
  final Map<String, bool> _passed = {};
  final Map<String, TextEditingController> _notes = {};

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _note(String id) => _notes.putIfAbsent(id, TextEditingController.new);

  Future<void> _save(List<FgRow> questions) async {
    final s = ref.read(stringsProvider);
    final ok = await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit(
            '/workshop/service-orders/${Uri.encodeComponent(widget.orderId)}/delivery-checklist',
            label: '${s.t('deliveryChecklist')} · ${widget.orderId}',
            body: {
              'answers': [
                for (final q in questions)
                  {
                    'question': int.tryParse(q.s('id')) ?? 0,
                    'passed': _passed[q.s('id')] ?? true,
                    'note': _note(q.s('id')).text.trim(),
                  },
              ],
            },
          ),
    );
    ref.invalidate(orderChecklistsProvider(widget.orderId));
    ref.invalidate(orderProvider(widget.orderId));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    final questions = ref.watch(lookupProvider('checklist?template=DELIVERY'));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: AsyncBody(
          value: questions,
          onRetry: () => ref.invalidate(lookupProvider('checklist?template=DELIVERY')),
          builder: (list) {
            final failed = list.where((q) => _passed[q.s('id')] == false).length;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(FgSpace.gutter, 0, FgSpace.gutter, FgSpace.s2),
                child: Row(children: [
                  const IconTile(FgIcons.deliveryCheck),
                  const SizedBox(width: FgSpace.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.t('deliveryChecklist'), style: context.tt.titleLarge),
                      Text(widget.orderId, style: context.tt.bodySmall),
                    ]),
                  ),
                  CountPill(failed, tone: FgTone.bad),
                ]),
              ),
              Expanded(
                child: list.isEmpty
                    ? ListView(children: [EmptyState(compact: true, title: s.t('noDeliveryChecklist'))])
                    : ListView(padding: const EdgeInsets.symmetric(horizontal: FgSpace.gutter), children: [
                        for (final q in list) ...[
                          Container(
                            padding: const EdgeInsets.all(FgSpace.s3),
                            decoration: BoxDecoration(
                              color: fg.surface,
                              borderRadius: FgRadius.brMd,
                              border: Border.all(color: (_passed[q.s('id')] ?? true) ? fg.border : fg.danger, width: (_passed[q.s('id')] ?? true) ? 1 : 1.5),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                Expanded(child: Text(s.lang == 'ar' && q.s('nameAr').isNotEmpty ? q.s('nameAr') : q.s('name'), style: context.tt.bodyMedium)),
                                const SizedBox(width: FgSpace.s2),
                                SegmentedButton<bool>(
                                  showSelectedIcon: false,
                                  segments: [
                                    ButtonSegment(value: true, icon: const Icon(FgIcons.check, size: 16), tooltip: s.t('passed')),
                                    ButtonSegment(value: false, icon: const Icon(FgIcons.close, size: 16), tooltip: s.t('qcFail')),
                                  ],
                                  selected: {_passed[q.s('id')] ?? true},
                                  onSelectionChanged: (v) {
                                    FgHaptics.tap();
                                    setState(() => _passed[q.s('id')] = v.first);
                                  },
                                ),
                              ]),
                              if (_passed[q.s('id')] == false)
                                TextField(controller: _note(q.s('id')), decoration: InputDecoration(labelText: s.t('note'))),
                            ]),
                          ),
                          const SizedBox(height: FgSpace.s2),
                        ],
                      ]),
              ),
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: fg.border))),
                padding: const EdgeInsets.all(FgSpace.gutter),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: list.isEmpty ? null : () => _save(list),
                  icon: const Icon(FgIcons.check, size: 18),
                  label: Text(s.t('save')),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
