import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';
import 'format.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// D-110 (brief 28): deep links. A notification (in-app list today; push once FCM is configured, blocker B-06) or a portal
/// link (`https://<portal>/orders/...` with Android app links, or `fleetgeeks://orders/...`) opens the matching screen of the
/// app. Only known screens are opened; anything else goes to the home screen. The record is still loaded through the API,
/// which checks the user's scope - a link never grants access.
class FgDeepLinks {
  const FgDeepLinks._();

  static final _patterns = <RegExp>[
    RegExp(r'^/orders/[A-Za-z0-9._-]+(/messages)?$'),
    RegExp(r'^/bookings/[A-Za-z0-9._-]+$'),
    RegExp(r'^/vehicles/[A-Za-z0-9._-]+$'),
    RegExp(r'^/(orders|vehicles|book|more|compliance|inspection|fault|usage|pool|outbox|notifications)$'),
    RegExp(r'^/$'),
  ];

  /// The app route of an incoming link, or null when it is not a screen of the app.
  static String? route(Uri uri) {
    var path = uri.path.isEmpty ? '/' : uri.path;
    // custom scheme: fleetgeeks://orders/X -> host "orders", path "/X"
    if (uri.scheme == 'fleetgeeks' && uri.host.isNotEmpty) path = '/${uri.host}${uri.path}';
    if (path.length > 1 && path.endsWith('/')) path = path.substring(0, path.length - 1);
    if (!_patterns.any((p) => p.hasMatch(path))) return null;
    final query = uri.queryParameters.isEmpty ? '' : '?${Uri(queryParameters: uri.queryParameters).query}';
    return '$path$query';
  }

  /// The app route of a notification's record (D365 RefTable / RefId).
  static String? forRecord(String refTable, String refId) {
    final id = Uri.encodeComponent(refId);
    if (refId.isEmpty) return null;
    return switch (refTable) {
      'FGServiceOrder' || 'FGEstimate' || 'FGHandover' || 'FGSlaClock' => refTable == 'FGServiceOrder' ? '/orders/$id' : null,
      'FGAppointment' => '/bookings/$id',
      'FGVehicle' || 'FGPMObligation' || 'FGComplianceDocument' => '/vehicles/$id',
      _ => null,
    };
  }
}

/// Portal notifications of the signed-in user; a tap opens the record.
final notificationsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.read(apiProvider).get('/notifications') as List;
  return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key, required this.open});

  /// Navigates to an app route (go_router's context.push in the apps).
  final void Function(BuildContext context, String route) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final rows = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('notifications'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(notificationsProvider.future),
        child: rows.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(FgSpace.gutter), child: ErrorText(e))]),
          data: (list) => list.isEmpty
              ? ListView(children: [EmptyState(title: s.t('noNotifications'))])
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final n = list[i];
                    final route = FgDeepLinks.forRecord('${n['RefTable'] ?? ''}', '${n['RefId'] ?? ''}');
                    return ListTile(
                      title: Text('${n['Subject'] ?? ''}'),
                      subtitle: Text('${n['Body'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis),
                      trailing: Text(fmtDate(DateTime.tryParse('${n['SentDateTime'] ?? ''}')?.toLocal(), s.lang), style: context.tt.bodySmall),
                      onTap: route == null ? null : () => open(context, route),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
