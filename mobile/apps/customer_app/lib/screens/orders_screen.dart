import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'vehicles_screen.dart';

final ordersProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async => asRows(await ref.watch(apiProvider).get('/service-orders')));

/// VehicleId → plate, from the vehicle list when it is loaded (orders only carry the vehicle id).
Map<String, String> platesOf(WidgetRef ref) => {for (final v in ref.watch(vehiclesProvider).value ?? const <FgRow>[]) v.s('VehicleId'): vehiclePlate(v)};

/// Service order card: status, vehicle, promise countdown and the stage bar.
class OrderCard extends ConsumerWidget {
  const OrderCard({super.key, required this.order, this.plate, this.unread = 0});
  final FgRow order;
  final String? plate;

  /// Unread messages from the workshop on this order.
  final int unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final status = order.s('Status');
    final promise = order.d('CurrentPromise');
    final open = isOrderOpen(status);
    return FgListCard(
      leading: IconTile(FgIcons.status(status), tone: toneOf(status)),
      title: order.s('ServiceOrderId'),
      subtitle: '${plate ?? order.s('VehicleId')} · ${s.status(order.s('ServiceType'))}',
      meta: promise == null || !open ? null : '${s.t('promise')}: ${fmtDate(promise, s.lang)} · ${promiseText(s, promise)}',
      trailing: unread > 0
          ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              StatusPill(status, dense: true),
              const SizedBox(height: FgSpace.s1),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FgIcons.messages, size: 14, color: context.fg.action),
                const SizedBox(width: 2),
                Text('$unread', style: context.tt.labelMedium?.copyWith(color: context.fg.action, fontWeight: FontWeight.w700)),
              ]),
            ])
          : StatusPill(status, dense: true),
      footer: open ? OrderProgress(status: status, compact: true) : null,
      onTap: () => context.push('/orders/${Uri.encodeComponent(order.s('ServiceOrderId'))}'),
    );
  }
}

enum _Show { active, done }

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  _Show _show = _Show.active;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final orders = ref.watch(ordersProvider);
    final plates = platesOf(ref);
    final unread = unreadByOrder(ref.watch(unreadMessagesProvider).value);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('orders')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      body: FgRefresh(
        onRefresh: () {
          ref.invalidate(unreadMessagesProvider);
          return ref.refresh(ordersProvider.future);
        },
        child: AsyncBody(
          value: orders,
          onRetry: () => ref.invalidate(ordersProvider),
          builder: (list) {
            final active = list.where((o) => isOrderOpen(o.s('Status'))).toList();
            final done = list.where((o) => !isOrderOpen(o.s('Status'))).toList();
            final shown = _show == _Show.active ? active : done;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
              children: [
                SegmentedButton<_Show>(
                  segments: [
                    ButtonSegment(value: _Show.active, label: Text('${s.t('active')} (${active.length})'), icon: const Icon(FgIcons.tasks, size: 18)),
                    ButtonSegment(value: _Show.done, label: Text('${s.t('completed')} (${done.length})'), icon: const Icon(FgIcons.finish, size: 18)),
                  ],
                  selected: {_show},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) {
                    FgHaptics.tap();
                    setState(() => _show = v.first);
                  },
                ),
                const SizedBox(height: FgSpace.s3),
                if (shown.isEmpty)
                  EmptyState(
                    art: FgArt.calendar,
                    title: s.t(_show == _Show.active ? 'noActiveOrders' : 'noData'),
                    message: _show == _Show.active ? s.t('noActiveOrdersHint') : null,
                    actionLabel: _show == _Show.active ? s.t('book') : null,
                    onAction: _show == _Show.active ? () => context.go('/book') : null,
                  )
                else
                  for (final o in shown) ...[
                    OrderCard(order: o, plate: plates[o.s('VehicleId')], unread: unread[o.s('ServiceOrderId')] ?? 0),
                    const SizedBox(height: FgSpace.s3),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}
