import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

const _ratings = ['Green', 'Amber', 'Red'];

/// Vehicle health check: green / amber / red per item with a note and, for amber / red, the recommended job.
/// Ratings and sending go through the outbox (work continues without signal).
class HealthCheckSheet extends ConsumerStatefulWidget {
  const HealthCheckSheet({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<HealthCheckSheet> createState() => _HealthCheckSheetState();
}

class _HealthCheckSheetState extends ConsumerState<HealthCheckSheet> {
  final Map<int, String> _rating = {};
  final Map<int, String> _job = {};
  final Map<int, TextEditingController> _notes = {};
  bool _starting = false;

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _note(int line, String initial) => _notes.putIfAbsent(line, () => TextEditingController(text: initial));

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await ref.read(apiProvider).post('/workshop/service-orders/${Uri.encodeComponent(widget.orderId)}/health-check');
      FgHaptics.success();
      ref.invalidate(orderProvider(widget.orderId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final detail = ref.watch(orderProvider(widget.orderId));
    final jobTypes = ref.watch(lookupProvider('job-types')).value ?? const <FgRow>[];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: AsyncBody(
          value: detail,
          builder: (d) {
            final checks = asRows(d['healthChecks']);
            final draft = checks.where((c) => c.s('Status') == 'Draft').firstOrNull;
            if (draft == null) {
              return ListView(padding: const EdgeInsets.symmetric(horizontal: FgSpace.gutter), children: [
                _title(context, s.t('healthCheck'), null),
                const SizedBox(height: FgSpace.s3),
                for (final c in checks)
                  FgListCard(
                    leading: const IconTile(FgIcons.healthCheck),
                    title: c.s('HealthCheckId'),
                    subtitle: '${c.s('RedCount')} × ${s.status('Red')} · ${c.s('AmberCount')} × ${s.status('Amber')}',
                    trailing: StatusPill(c.s('Status'), dense: true),
                  ),
                if (checks.isEmpty) EmptyState(compact: true, art: FgArt.empty, title: s.t('noHealthCheck')),
                const SizedBox(height: FgSpace.s4),
                FgBigButton(icon: FgIcons.healthCheck, label: s.t('startHealthCheck'), height: 60, onPressed: _starting ? null : _start),
              ]);
            }
            final id = draft.s('HealthCheckId');
            final lines = asRows(draft['lines']);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: FgSpace.gutter), child: _title(context, '${s.t('healthCheck')} $id', s.t('healthCheckHint'))),
              const SizedBox(height: FgSpace.s2),
              Expanded(
                child: ListView(padding: const EdgeInsets.symmetric(horizontal: FgSpace.gutter), children: [
                  for (final l in lines) ...[
                    _line(context, s, id, l, jobTypes),
                    const SizedBox(height: FgSpace.s3),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(FgSpace.gutter),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () async {
                    await runCommand(context, ref,
                        () => ref.read(outboxProvider.notifier).submit('/workshop/health-checks/${Uri.encodeComponent(id)}/send', label: '${s.t('sendHealthCheck')} $id'));
                    ref.invalidate(orderProvider(widget.orderId));
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(FgIcons.send, size: 18),
                  label: Text(s.t('sendHealthCheck')),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String title, String? hint) => Row(children: [
        const IconTile(FgIcons.healthCheck),
        const SizedBox(width: FgSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.tt.titleLarge),
            if (hint != null) Text(hint, style: context.tt.bodySmall),
          ]),
        ),
      ]);

  Widget _line(BuildContext context, Strings s, String id, FgRow l, List<FgRow> jobTypes) {
    final fg = context.fg;
    final line = l.n('LineNum').round();
    final rating = _rating[line] ?? (l.s('Rating') == 'NotChecked' ? '' : l.s('Rating'));
    final job = _job[line] ?? l.s('RecommendedJobType');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FgSpace.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.s('Question'), style: context.tt.titleSmall),
          const SizedBox(height: FgSpace.s2),
          Row(children: [
            for (final r in _ratings) ...[
              Expanded(
                child: _RagButton(
                  label: s.status(r),
                  tone: r == 'Green' ? FgTone.good : (r == 'Amber' ? FgTone.attention : FgTone.bad),
                  selected: rating == r,
                  onTap: () {
                    FgHaptics.tap();
                    setState(() => _rating[line] = rating == r ? '' : r);
                  },
                ),
              ),
              if (r != 'Red') const SizedBox(width: FgSpace.s2),
            ],
          ]),
          const SizedBox(height: FgSpace.s2),
          TextField(controller: _note(line, l.s('Note')), decoration: InputDecoration(labelText: s.t('note'))),
          if (rating == 'Amber' || rating == 'Red') ...[
            const SizedBox(height: FgSpace.s2),
            DropdownButtonFormField<String>(
              initialValue: job.isEmpty ? null : job,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.t('recommendedJob')),
              items: [
                for (final j in jobTypes)
                  DropdownMenuItem(
                    value: j.s('id'),
                    child: Text('${j.s('id')} – ${s.lang == 'ar' && j.s('nameAr').isNotEmpty ? j.s('nameAr') : j.s('name')}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _job[line] = v ?? ''),
            ),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: Icon(FgIcons.check, size: 18, color: rating.isEmpty ? fg.textMuted : null),
              onPressed: rating.isEmpty
                  ? null
                  : () => runCommand(
                        context,
                        ref,
                        () => ref.read(outboxProvider.notifier).submit('/workshop/health-checks/${Uri.encodeComponent(id)}/lines/$line',
                            label: '${s.t('healthCheck')} $id / $line: ${s.status(rating)}',
                            body: {'rating': rating, 'value': 0, 'note': _note(line, '').text.trim(), 'jobTypeId': rating == 'Green' ? '' : job}),
                      ),
              label: Text(s.t('save')),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RagButton extends StatelessWidget {
  const _RagButton({required this.label, required this.tone, required this.selected, required this.onTap});
  final String label;
  final FgTone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    final c = fg.tone(tone);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.bg : fg.surface,
        shape: RoundedRectangleBorder(borderRadius: FgRadius.brMd, side: BorderSide(color: selected ? c.fg : context.cs.outline, width: selected ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge?.copyWith(color: selected ? c.fg : fg.text))),
            ]),
          ),
        ),
      ),
    );
  }
}
