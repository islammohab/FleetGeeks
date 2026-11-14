import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'board_screen.dart';
import 'mobility_screen.dart';

/// Board stages that hold hands-on work, per role (the API has no per-technician list; these are the workshop's
/// vehicles in the work stages).
List<String> workLanes({required bool qc}) => ['inProgress', 'rework', 'received', 'awaitingParts', if (qc) 'qualityCheck'];

/// Tasks tab: vehicles in the work stages (open the order, then the job with big start / pause / finish buttons) and,
/// for gate / advisor / dispatcher roles, the pickups and deliveries.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final user = ref.watch(authProvider).value;
    final mobility = user?.has(['Gate', 'Advisor', 'Dispatcher', 'WorkshopManager']) ?? false;
    final qc = user?.has(['QC']) ?? false;
    final view = mobility ? _view : 0;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tasks')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      body: Column(children: [
        if (mobility)
          Padding(
            padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, icon: const Icon(FgIcons.tasks, size: 18), label: Text(s.t('myJobs'))),
                  ButtonSegment(value: 1, icon: const Icon(FgIcons.mobility, size: 18), label: Text(s.t('mobilityShort'))),
                ],
                selected: {view},
                onSelectionChanged: (v) {
                  FgHaptics.tap();
                  setState(() => _view = v.first);
                },
              ),
            ),
          ),
        Expanded(child: view == 0 ? _WorkList(qc: qc) : const MobilityList()),
      ]),
    );
  }
}

class _WorkList extends ConsumerWidget {
  const _WorkList({required this.qc});
  final bool qc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final queues = ref.watch(queuesProvider);
    return FgRefresh(
      onRefresh: () => ref.refresh(queuesProvider.future),
      child: AsyncBody(
        value: queues,
        onRetry: () => ref.invalidate(queuesProvider),
        builder: (q) {
          final lanes = workLanes(qc: qc);
          final total = lanes.fold<int>(0, (n, lane) => n + asRows(q[lane]).length);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
            children: [
              FgNotice(tone: FgTone.info, icon: FgIcons.tasks, message: s.t('tasksHint')),
              if (total == 0) EmptyState(art: FgArt.done, title: s.t('noTasks')),
              for (final lane in lanes)
                if (asRows(q[lane]).isNotEmpty) ...[
                  FgSectionTitle(s.t(lane), count: asRows(q[lane]).length),
                  for (final r in asRows(q[lane])) ...[
                    BoardCard(row: r, lane: lane),
                    const SizedBox(height: FgSpace.s2),
                  ],
                ],
            ],
          );
        },
      ),
    );
  }
}
