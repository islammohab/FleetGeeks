import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';
import 'models.dart';

/// Maintenance-cycle reads shared by both apps (API: CycleEndpoints). D365 scopes every call to the portal user.
String _enc(String id) => Uri.encodeComponent(id);

/// Events of a service order, oldest first: {at, type, text, textAr, refTable, refId, evidence, actor}.
final orderTimelineProvider = FutureProvider.autoDispose.family<List<FgRow>, String>(
  (ref, id) async => asRows(await ref.watch(apiProvider).get('/service-orders/${_enc(id)}/timeline')),
);

/// Jobs with planned times and who is working now: {status, promise, technicianWorking, jobs: [...]}.
final orderProgressProvider = FutureProvider.autoDispose.family<FgRow, String>(
  (ref, id) async => asRow(await ref.watch(apiProvider).get('/service-orders/${_enc(id)}/progress')),
);

/// Checklist results incl. delivery items and QC outcomes: {deliveryDone, results: [...], qc: [...]}.
final orderChecklistsProvider = FutureProvider.autoDispose.family<FgRow, String>(
  (ref, id) async => asRow(await ref.watch(apiProvider).get('/service-orders/${_enc(id)}/checklists')),
);

/// PDF documents of a service order: {evidenceId, documentType, fileName, capturedBy, at}.
final orderDocumentsProvider = FutureProvider.autoDispose.family<List<FgRow>, String>(
  (ref, id) async => asRows(await ref.watch(apiProvider).get('/service-orders/${_enc(id)}/documents')),
);

/// Message thread of a service order, oldest first.
final orderMessagesProvider = FutureProvider.autoDispose.family<List<FgRow>, String>(
  (ref, id) async => asRows(await ref.watch(apiProvider).get('/service-orders/${_enc(id)}/messages')),
);

/// Unread messages for the signed-in side: {total, orders: [{serviceOrderId, unread}]}.
final unreadMessagesProvider = FutureProvider.autoDispose<FgRow>((ref) async => asRow(await ref.watch(apiProvider).get('/messages/unread')));

/// Unread count per service order from [unreadMessagesProvider].
Map<String, int> unreadByOrder(FgRow? unread) =>
    {for (final o in asRows(unread?['orders'])) o.s('serviceOrderId'): o.n('unread').round()};

/// Outbox path of a message post (also used to show queued messages in the thread).
String messagesPath(String orderId) => '/service-orders/${_enc(orderId)}/messages';

/// A field of a row that may come as an OData entity (PascalCase) or as an API object (camelCase).
String rowField(FgRow row, String name) {
  final camel = name.isEmpty ? name : name[0].toLowerCase() + name.substring(1);
  final pascal = name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
  final v = row.s(pascal);
  return v.isNotEmpty ? v : row.s(camel);
}

/// Date field in either casing; D365 empty dates (1900-01-01) are null.
DateTime? rowDate(FgRow row, String name) {
  final camel = name[0].toLowerCase() + name.substring(1);
  final pascal = name[0].toUpperCase() + name.substring(1);
  return row.d(pascal) ?? row.d(camel);
}
