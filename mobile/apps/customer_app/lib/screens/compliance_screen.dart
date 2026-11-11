import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final complianceProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async {
  final rows = asRows(await ref.watch(apiProvider).get('/compliance'));
  const order = {'Expired': 0, 'DueSoon': 1, 'Valid': 2};
  rows.sort((a, b) => (order[a.s('Status')] ?? 3).compareTo(order[b.s('Status')] ?? 3));
  return rows;
});

/// Registrations, inspections, insurance and licences of the fleet, expired and due first.
class ComplianceScreen extends ConsumerWidget {
  const ComplianceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final docs = ref.watch(complianceProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('compliance')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      bottomNavigationBar: OfflineBanner(safeArea: true, onOpenOutbox: () => context.push('/outbox')),
      body: FgRefresh(
        onRefresh: () => ref.refresh(complianceProvider.future),
        child: AsyncBody(
          value: docs,
          onRetry: () => ref.invalidate(complianceProvider),
          builder: (list) {
            int count(String status) => list.where((d) => d.s('Status') == status).length;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
              children: [
                if (list.isEmpty)
                  EmptyState(art: FgArt.done, title: s.t('noDocuments'))
                else ...[
                  Row(children: [
                    for (final (status, tone) in const [('Expired', FgTone.bad), ('DueSoon', FgTone.attention), ('Valid', FgTone.good)]) ...[
                      Expanded(child: _Count(label: s.status(status), value: count(status), tone: tone)),
                      if (status != 'Valid') const SizedBox(width: FgSpace.s2),
                    ],
                  ]),
                  const SizedBox(height: FgSpace.s4),
                  for (final d in list) ...[
                    FgListCard(
                      leading: IconTile(FgIcons.status(d.s('Status')), tone: toneOf(d.s('Status'))),
                      title: s.lang == 'ar' && d.s('TypeNameAr').isNotEmpty ? d.s('TypeNameAr') : d.s('TypeName'),
                      subtitle: [d.s('Subject'), d.s('DocumentNumber')].where((x) => x.isNotEmpty).join(' · '),
                      meta: d.d('ExpiryDate') == null
                          ? null
                          : '${s.t('expires')}: ${fmtDate(d.d('ExpiryDate'), s.lang, time: false)} · ${promiseText(s, d.d('ExpiryDate'))}',
                      trailing: StatusPill(d.s('Status'), dense: true),
                    ),
                    const SizedBox(height: FgSpace.s3),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.tone});
  final String label;
  final int value;
  final FgTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.fg.tone(value == 0 ? FgTone.neutral : tone);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: FgSpace.s3, horizontal: FgSpace.s2),
        decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brMd),
        child: Column(children: [
          Text('$value', style: context.tt.headlineSmall?.copyWith(color: c.fg, fontWeight: FontWeight.w700, fontFeatures: FgFonts.tabular)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelMedium?.copyWith(color: c.fg)),
        ]),
      ),
    );
  }
}
