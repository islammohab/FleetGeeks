import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'providers.dart';

/// Booking requests waiting for the workshop (Requested) or for the customer's answer (Proposed), soonest first.
final requestedBookingsProvider = FutureProvider.autoDispose<List<FgRow>>(
  (ref) async => asRows(await ref.watch(apiProvider).get('/workshop/bookings/requested')),
);

/// Roles that review booking requests.
const bookingReviewRoles = ['Advisor', 'WorkshopManager', 'Dispatcher'];

/// Advisor review of booking requests: confirm, propose another time, or decline with a reason. Decisions are live
/// (capacity and the customer's notification are decided by D365 at that moment).
class BookingsReviewScreen extends ConsumerWidget {
  const BookingsReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final bookings = ref.watch(requestedBookingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('bookingsToConfirm')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      bottomNavigationBar: OfflineBanner(safeArea: true, onOpenOutbox: () => context.push('/outbox')),
      body: FgRefresh(
        onRefresh: () => ref.refresh(requestedBookingsProvider.future),
        child: AsyncBody(
          value: bookings,
          onRetry: () => ref.invalidate(requestedBookingsProvider),
          builder: (list) {
            final waiting = list.where((b) => b.s('status') == 'Requested').toList();
            final proposed = list.where((b) => b.s('status') != 'Requested').toList();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
              children: [
                if (list.isEmpty) EmptyState(art: FgArt.done, title: s.t('noBookingRequests'), message: s.t('noBookingRequestsHint')),
                if (waiting.isNotEmpty) FgSectionTitle(s.t('toConfirm'), count: waiting.length),
                for (final b in waiting) ...[_RequestCard(booking: b), const SizedBox(height: FgSpace.s3)],
                if (proposed.isNotEmpty) FgSectionTitle(s.t('waitingForCustomer'), count: proposed.length),
                for (final b in proposed) ...[_RequestCard(booking: b), const SizedBox(height: FgSpace.s3)],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.booking});
  final FgRow booking;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;

  String get _id => Uri.encodeComponent(widget.booking.s('appointmentId'));

  Future<void> _decide(String verb, Map<String, Object?> body, String done) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/workshop/bookings/$_id/$verb', idempotencyKey: const Uuid().v4(), body: body);
      if (!mounted) return;
      showDone(context, done);
      ref.invalidate(requestedBookingsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reschedule() async {
    final s = ref.read(stringsProvider);
    final start = widget.booking.d('start') ?? DateTime.now().add(const Duration(days: 1));
    final day = await showDatePicker(context: context, initialDate: start, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180)));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (time == null || !mounted) return;
    final proposed = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    await _decide('reschedule', {'proposedStartUtc': proposed.toUtc().toIso8601String()}, s.t('proposalSent'));
  }

  Future<void> _decline() async {
    final s = ref.read(stringsProvider);
    final reasons = await ref.read(lookupProvider('reasons?type=Decline').future);
    if (!mounted) return;
    final reason = await pickLookup(context, title: s.t('declineReason'), rows: reasons, s: s);
    if (reason == null || !mounted) return;
    await _decide('decline', {'reason': reason}, s.t('bookingDeclinedDone'));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final b = widget.booking;
    final status = b.s('status');
    final requested = status == 'Requested';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FgSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (b.s('plate').isNotEmpty) ...[PlateBadge(b.s('plate')), const SizedBox(width: FgSpace.s2)],
            Expanded(child: Text(b.s('appointmentId'), style: context.tt.labelMedium?.copyWith(fontFeatures: FgFonts.tabular))),
            StatusPill(status, dense: true),
          ]),
          const SizedBox(height: FgSpace.s2),
          KeyValueRow(s.t('date'), '${fmtDate(b.d('start'), s.lang)} · ${promiseText(s, b.d('start'))}', icon: FgIcons.calendar, tabular: true),
          if (b.d('proposedStart') != null) KeyValueRow(s.t('proposedTime'), fmtDate(b.d('proposedStart'), s.lang), icon: FgIcons.proposal, tabular: true),
          KeyValueRow(s.t('vehicle'), b.s('vehicleId'), icon: FgIcons.vehicles),
          if (b.s('customer').isNotEmpty) KeyValueRow(s.t('customer'), b.s('customer'), icon: FgIcons.users),
          KeyValueRow(
            s.t('serviceType'),
            [s.status(b.s('serviceType')), b.s('jobTypeId'), b.s('variantId'), if (b.n('estimatedHours') > 0) s.t('hoursShort', [fmtNum(b.n('estimatedHours'), decimals: 1)])]
                .where((x) => x.isNotEmpty)
                .join(' · '),
            icon: FgIcons.tasks,
          ),
          if (b.n('odometer') > 0) KeyValueRow(s.t('odometer'), fmtKm(b.n('odometer')), icon: FgIcons.odometer, tabular: true),
          if (b.s('complaint').isNotEmpty) ...[
            const SizedBox(height: FgSpace.s1),
            Text(b.s('complaint'), style: context.tt.bodyMedium),
          ],
          if (b['pickup'] == true || b['replacement'] == true) ...[
            const SizedBox(height: FgSpace.s2),
            Wrap(spacing: FgSpace.s2, children: [
              if (b['pickup'] == true) StatusPill('Pickup', label: s.t('pickupRequest'), dense: true),
              if (b['replacement'] == true) StatusPill('Replacement', label: s.t('replacementRequest'), dense: true),
            ]),
          ],
          if (requested) ...[
            const SizedBox(height: FgSpace.s3),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _decline,
                  child: Text(s.t('decline')),
                ),
              ),
              const SizedBox(width: FgSpace.s2),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reschedule,
                  child: Text(s.t('proposeTime')),
                ),
              ),
              const SizedBox(width: FgSpace.s2),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _decide('confirm', const <String, Object?>{}, s.t('bookingConfirmedDone')),
                  child: Text(s.t('confirm')),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
