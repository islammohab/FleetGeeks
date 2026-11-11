import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Checklist answers (pass / fail per question); each answer is a separate idempotent command through the outbox.
class ChecklistSheet extends ConsumerStatefulWidget {
  const ChecklistSheet({super.key, required this.orderId, required this.jobLine, required this.template});
  final String orderId;
  final int jobLine;
  final String template;

  @override
  ConsumerState<ChecklistSheet> createState() => _ChecklistSheetState();
}

class _ChecklistSheetState extends ConsumerState<ChecklistSheet> {
  final Map<String, bool> _passed = {};

  Future<void> _save(List<FgRow> list) async {
    final s = ref.read(stringsProvider);
    final outbox = ref.read(outboxProvider.notifier);
    await runCommand(context, ref, () async {
      SubmitResult last = const SubmitResult(SubmitOutcome.sent);
      for (final q in list) {
        final passed = _passed[q.s('id')] ?? true;
        last = await outbox.submit('/workshop/checklists', label: '${s.t('checklist')} ${widget.orderId} / ${widget.jobLine} / ${q.s('id')}', body: {
          'serviceOrderId': widget.orderId,
          'jobLine': widget.jobLine,
          'templateId': widget.template,
          'question': int.parse(q.s('id')),
          'answer': passed ? 'Pass' : 'Fail',
          'value': 0,
          'passed': passed,
        });
      }
      return last;
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final questions = ref.watch(lookupProvider('checklist?template=${Uri.encodeComponent(widget.template)}'));
    final fg = context.fg;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: AsyncBody(
          value: questions,
          builder: (list) {
            final failed = list.where((q) => _passed[q.s('id')] == false).length;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(FgSpace.gutter, 0, FgSpace.gutter, FgSpace.s2),
                child: Row(children: [
                  const IconTile(FgIcons.checklist),
                  const SizedBox(width: FgSpace.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.t('checklist'), style: context.tt.titleLarge),
                      Text('${widget.template} · ${widget.orderId} / ${widget.jobLine}', style: context.tt.bodySmall),
                    ]),
                  ),
                  CountPill(failed, tone: FgTone.bad),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.symmetric(horizontal: FgSpace.gutter), children: [
                  for (final q in list) ...[
                    _Question(
                      number: q.s('id'),
                      label: s.lang == 'ar' && q.s('nameAr').isNotEmpty ? q.s('nameAr') : q.s('name'),
                      passed: _passed[q.s('id')] ?? true,
                      onChanged: (v) {
                        FgHaptics.tap();
                        setState(() => _passed[q.s('id')] = v);
                      },
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

class _Question extends ConsumerWidget {
  const _Question({required this.number, required this.label, required this.passed, required this.onChanged});
  final String number;
  final String label;
  final bool passed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    return Container(
      padding: const EdgeInsets.all(FgSpace.s3),
      decoration: BoxDecoration(
        color: fg.surface,
        borderRadius: FgRadius.brMd,
        border: Border.all(color: passed ? fg.border : fg.danger, width: passed ? 1 : 1.5),
      ),
      child: Row(children: [
        Text(number, style: context.tt.labelMedium?.copyWith(color: fg.textMuted, fontFeatures: FgFonts.tabular)),
        const SizedBox(width: FgSpace.s3),
        Expanded(child: Text(label, style: context.tt.bodyMedium)),
        const SizedBox(width: FgSpace.s2),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: true, icon: const Icon(FgIcons.check, size: 16), tooltip: s.t('passed')),
            ButtonSegment(value: false, icon: const Icon(FgIcons.close, size: 16), tooltip: s.t('qcFail')),
          ],
          selected: {passed},
          onSelectionChanged: (v) => onChanged(v.first),
        ),
      ]),
    );
  }
}
