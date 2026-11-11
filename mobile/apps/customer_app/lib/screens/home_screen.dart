import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'compliance_screen.dart';
import 'orders_screen.dart';
import 'vehicles_screen.dart';

/// One "needs your action" row.
class _Action {
  const _Action({required this.title, required this.subtitle, required this.icon, required this.tone, required this.onTap, this.status = ''});
  final String title;
  final String subtitle;
  final IconData icon;
  final FgTone tone;
  final VoidCallback onTap;
  final String status;
}

/// Customer home: greeting, key figures from the existing lists (vehicles, service orders, compliance), quick
/// actions, what needs the user's action and the latest service orders.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final user = ref.watch(authProvider).value;
    final vehicles = ref.watch(vehiclesProvider);
    final orders = ref.watch(ordersProvider);
    final compliance = ref.watch(complianceProvider);
    final outbox = ref.watch(outboxProvider).value ?? const <OutboxItem>[];
    final plates = platesOf(ref);
    final unread = unreadByOrder(ref.watch(unreadMessagesProvider).value);

    final vs = vehicles.value;
    final os = orders.value;
    final docs = compliance.value;
    final open = os?.where((o) => isOrderOpen(o.s('Status'))).toList();
    final awaiting = os?.where((o) => o.s('Status') == 'AwaitingApproval').toList() ?? const <FgRow>[];
    final ready = os?.where((o) => o.s('Status') == 'ReadyForCollection').toList() ?? const <FgRow>[];
    final expiring = docs?.where((d) => d.s('Status') == 'Expired' || d.s('Status') == 'DueSoon').toList() ?? const <FgRow>[];
    final failed = outbox.where((i) => i.failed).length;
    String count(List<Object?>? list) => list == null ? '—' : fmtNum(list.length);

    final actions = <_Action>[
      for (final entry in unread.entries)
        if (entry.value > 0)
          _Action(
            title: s.t('actionMessages', [entry.key]),
            subtitle: s.t('unreadMessages', [entry.value]),
            icon: FgIcons.messages,
            tone: FgTone.attention,
            onTap: () => context.push('/orders/${Uri.encodeComponent(entry.key)}/messages'),
          ),
      for (final o in awaiting)
        _Action(
          title: s.t('actionApprove', [o.s('ServiceOrderId')]),
          subtitle: plates[o.s('VehicleId')] ?? o.s('VehicleId'),
          icon: FgIcons.estimate,
          tone: FgTone.attention,
          status: o.s('Status'),
          onTap: () => context.push('/orders/${Uri.encodeComponent(o.s('ServiceOrderId'))}'),
        ),
      for (final o in ready)
        _Action(
          title: s.t('actionCollect', [o.s('ServiceOrderId')]),
          subtitle: plates[o.s('VehicleId')] ?? o.s('VehicleId'),
          icon: FgIcons.event('ready'),
          tone: FgTone.good,
          status: o.s('Status'),
          onTap: () => context.push('/orders/${Uri.encodeComponent(o.s('ServiceOrderId'))}'),
        ),
      for (final d in expiring)
        _Action(
          title: s.lang == 'ar' && d.s('TypeNameAr').isNotEmpty ? d.s('TypeNameAr') : d.s('TypeName'),
          subtitle: '${d.s('Subject')} · ${s.t('expires')} ${fmtDate(d.d('ExpiryDate'), s.lang, time: false)}',
          icon: FgIcons.compliance,
          tone: d.s('Status') == 'Expired' ? FgTone.bad : FgTone.attention,
          status: d.s('Status'),
          onTap: () => context.push('/compliance'),
        ),
      if (failed > 0)
        _Action(
          title: s.t('outboxRefused', [failed]),
          subtitle: s.t('outboxRefusedHint'),
          icon: FgIcons.danger,
          tone: FgTone.bad,
          onTap: () => context.push('/outbox'),
        ),
    ];

    final hour = DateTime.now().hour;
    final greeting = s.t(hour < 12 ? 'goodMorning' : (hour < 18 ? 'goodAfternoon' : 'goodEvening'));
    final inWorkshop = vs?.where((v) => v.s('Availability') != 'Available' && v.s('Availability').isNotEmpty).length;
    final recent = (os ?? const <FgRow>[]).take(3).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: FgSpace.s4,
        title: Row(children: [
          const FgBrandMark(size: 30),
          const SizedBox(width: FgSpace.s2),
          Flexible(child: Text(s.t('appCustomer'), overflow: TextOverflow.ellipsis)),
        ]),
        actions: [OutboxButton(onPressed: () => context.push('/outbox'))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fault-home',
        onPressed: () => context.push('/fault'),
        icon: const Icon(FgIcons.fault),
        label: Text(s.t('reportFault')),
      ),
      body: FgRefresh(
        onRefresh: () async {
          ref.invalidate(vehiclesProvider);
          ref.invalidate(ordersProvider);
          ref.invalidate(complianceProvider);
          ref.invalidate(unreadMessagesProvider);
          await Future.wait<Object?>([
            ref.read(vehiclesProvider.future),
            ref.read(ordersProvider.future),
          ]).catchError((Object _) => <Object?>[]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, 96),
          children: [
            HeroHeader(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(greeting, style: context.tt.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                    Text(user?.contactName ?? '', style: context.tt.headlineSmall?.copyWith(color: Colors.white)),
                    const SizedBox(height: FgSpace.s2),
                    Text(
                      vs == null ? s.t('loading') : s.t('fleetSummary', [vs.length, inWorkshop ?? 0]),
                      style: context.tt.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ]),
                ),
                FgAvatar(user?.contactName ?? '?', size: 52, onHero: true),
              ]),
            ),
            const SizedBox(height: FgSpace.s4),
            StatGrid(children: [
              StatCard(
                label: s.t('vehicles'),
                value: count(vs),
                icon: FgIcons.vehicles,
                caption: vs == null ? null : '${fmtNum(vs.where((v) => v.s('Availability') == 'Available').length)} ${s.status('Available')}',
                onTap: () => context.go('/vehicles'),
              ),
              StatCard(
                label: s.t('openOrders'),
                value: count(open),
                icon: FgIcons.orders,
                caption: ready.isEmpty ? null : '${ready.length} ${s.status('ReadyForCollection')}',
                tone: ready.isEmpty ? FgTone.progress : FgTone.good,
                onTap: () => context.go('/orders'),
              ),
              StatCard(
                label: s.t('awaitingApproval'),
                value: os == null ? '—' : fmtNum(awaiting.length),
                icon: FgIcons.estimate,
                tone: awaiting.isEmpty ? FgTone.neutral : FgTone.attention,
                onTap: () => context.go('/orders'),
              ),
              StatCard(
                label: s.t('complianceExpiring'),
                value: compliance.hasError ? '—' : (docs == null ? '—' : fmtNum(expiring.length)),
                icon: FgIcons.compliance,
                tone: expiring.any((d) => d.s('Status') == 'Expired') ? FgTone.bad : (expiring.isEmpty ? FgTone.good : FgTone.attention),
                onTap: () => context.push('/compliance'),
              ),
            ]),
            FgSectionTitle(s.t('quickActions')),
            Row(children: [
              Expanded(child: FgQuickAction(icon: FgIcons.book, label: s.t('bookShort'), highlight: true, onTap: () => context.go('/book'))),
              const SizedBox(width: FgSpace.s2),
              Expanded(child: FgQuickAction(icon: FgIcons.inspection, label: s.t('inspectionShort'), onTap: () => context.push('/inspection'))),
              const SizedBox(width: FgSpace.s2),
              Expanded(child: FgQuickAction(icon: FgIcons.fuel, label: s.t('usageShort'), onTap: () => context.push('/usage'))),
              const SizedBox(width: FgSpace.s2),
              Expanded(child: FgQuickAction(icon: FgIcons.pool, label: s.t('poolShort'), onTap: () => context.push('/pool'))),
            ]),
            FgSectionTitle(s.t('needsAction'), count: os == null ? null : actions.length),
            if (os == null && orders.isLoading)
              const Shimmer(child: Column(children: [SkeletonCard(), SizedBox(height: FgSpace.s3), SkeletonCard()]))
            else if (orders.hasError)
              ErrorState(error: orders.error!, compact: true, onRetry: () => ref.invalidate(ordersProvider))
            else if (actions.isEmpty)
              Card(child: EmptyState(compact: true, art: FgArt.done, title: s.t('allCaughtUp'), message: s.t('allCaughtUpText')))
            else
              for (final a in actions) ...[
                FgListCard(
                  leading: IconTile(a.icon, tone: a.tone),
                  title: a.title,
                  subtitle: a.subtitle,
                  trailing: a.status.isEmpty ? null : StatusPill(a.status, dense: true),
                  onTap: a.onTap,
                ),
                const SizedBox(height: FgSpace.s2),
              ],
            if (recent.isNotEmpty) ...[
              FgSectionTitle(s.t('recentOrders'), actionLabel: s.t('seeAll'), onAction: () => context.go('/orders')),
              for (final o in recent) ...[
                OrderCard(order: o, plate: plates[o.s('VehicleId')]),
                const SizedBox(height: FgSpace.s3),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
