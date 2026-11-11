import 'package:fg_core/fg_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service order detail (order, jobs, handovers, evidence, health checks, damage …).
final orderProvider = FutureProvider.autoDispose.family<FgRow, String>(
  (ref, id) async => asRow(await ref.watch(apiProvider).get('/service-orders/${Uri.encodeComponent(id)}')),
);

/// D365 lookups (reason codes, checklist questions, job types) as {id, name, nameAr}.
final lookupProvider = FutureProvider.autoDispose.family<List<FgRow>, String>(
  (ref, query) async => asRows(await ref.watch(apiProvider).get('/lookups/$query')),
);
