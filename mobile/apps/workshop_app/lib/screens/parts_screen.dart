import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'board_screen.dart';

/// Stores: reserved / back-ordered part lines; issue posts the standard inventory movement journal in D365.
class PartsScreen extends ConsumerStatefulWidget {
  const PartsScreen({super.key});

  @override
  ConsumerState<PartsScreen> createState() => _PartsScreenState();
}

class _PartsScreenState extends ConsumerState<PartsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final queues = ref.watch(queuesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('parts')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      body: FgRefresh(
        onRefresh: () => ref.refresh(queuesProvider.future),
        child: AsyncBody(
          value: queues,
          onRetry: () => ref.invalidate(queuesProvider),
          builder: (q) {
            final parts = asRows(q['parts']);
            final query = _search.text.trim().toLowerCase();
            final shown = parts.where((p) => query.isEmpty || '${p.s('ItemId')} ${p.s('ServiceOrderId')}'.toLowerCase().contains(query)).toList();
            final toIssue = parts.where((p) => p.s('Status') != 'Backordered').length;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
              children: [
                if (parts.isEmpty)
                  EmptyState(art: FgArt.done, title: s.t('noParts'), message: s.t('noPartsHint'))
                else ...[
                  StatGrid(children: [
                    StatCard(label: s.t('toIssue'), value: fmtNum(toIssue), icon: FgIcons.parts, tone: toIssue > 0 ? FgTone.attention : FgTone.neutral),
                    StatCard(label: s.status('Backordered'), value: fmtNum(parts.length - toIssue), icon: FgIcons.status('Backordered'), tone: FgTone.bad),
                  ]),
                  const SizedBox(height: FgSpace.s3),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: s.t('searchParts'), prefixIcon: const Icon(FgIcons.search, size: 20)),
                  ),
                  const SizedBox(height: FgSpace.s3),
                  if (shown.isEmpty) EmptyState(compact: true, art: FgArt.search, title: s.t('noMatches')),
                  for (final p in shown) ...[
                    FgListCard(
                      leading: IconTile(FgIcons.status(p.s('Status')), tone: toneOf(p.s('Status'))),
                      title: '${p.s('ItemId')} × ${fmtNum(p.n('Quantity'), decimals: p.n('Quantity') == p.n('Quantity').roundToDouble() ? 0 : 2)}',
                      subtitle: '${p.s('ServiceOrderId')} / ${p.s('JobLineNum')}',
                      meta: '${p.s('InventSiteId')} / ${p.s('InventLocationId')}',
                      trailing: p.s('Status') == 'Backordered'
                          ? StatusPill(p.s('Status'), dense: true)
                          : FilledButton(
                              onPressed: () async {
                                await runCommand(
                                  context,
                                  ref,
                                  () => ref.read(outboxProvider.notifier).submit(
                                        '/workshop/parts/${Uri.encodeComponent(p.s('ServiceOrderId'))}/${p.s('LineNum')}/issue',
                                        label: '${s.t('issue')} ${p.s('ItemId')} · ${p.s('ServiceOrderId')}',
                                      ),
                                );
                                ref.invalidate(queuesProvider);
                              },
                              child: Text(s.t('issue')),
                            ),
                    ),
                    const SizedBox(height: FgSpace.s2),
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
