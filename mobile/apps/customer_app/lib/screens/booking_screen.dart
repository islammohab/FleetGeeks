import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

/// Booking requests made on this phone (newest first, at most 20). The API has no "my bookings" list, so the app keeps
/// the appointment ids it created; D365 still decides what each one shows (GET /bookings/{id}).
class MyBookings extends AsyncNotifier<List<String>> {
  static const _key = 'fg.myBookings';

  @override
  Future<List<String>> build() async {
    final v = await ref.read(secureStorageProvider).read(key: _key);
    return v == null || v.isEmpty ? <String>[] : v.split(',');
  }

  Future<void> remember(String appointmentId) async {
    if (appointmentId.isEmpty) return;
    final current = state.value ?? await future;
    final list = [appointmentId, ...current.where((x) => x != appointmentId)].take(20).toList();
    state = AsyncData(list);
    await ref.read(secureStorageProvider).write(key: _key, value: list.join(','));
  }

  Future<void> forget(String appointmentId) async {
    final list = (state.value ?? await future).where((x) => x != appointmentId).toList();
    state = AsyncData(list);
    await ref.read(secureStorageProvider).write(key: _key, value: list.join(','));
  }
}

final myBookingsProvider = AsyncNotifierProvider<MyBookings, List<String>>(MyBookings.new);

/// One appointment (FGAppointments row; PascalCase fields).
final bookingProvider = FutureProvider.autoDispose.family<FgRow, String>(
  (ref, id) async => asRow(await ref.watch(apiProvider).get('/bookings/${Uri.encodeComponent(id)}')),
);

/// The one-time arrival QR code for the gate.
class ArrivalQrCard extends ConsumerWidget {
  const ArrivalQrCard({super.key, required this.token, this.expires});
  final String token;
  final DateTime? expires;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Container(
          padding: const EdgeInsets.all(FgSpace.s4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: FgRadius.brXl, boxShadow: FgShadows.card(Theme.of(context).brightness)),
          child: Semantics(
            label: s.t('arrivalQrLabel'),
            image: true,
            child: QrImageView(data: token, size: 240, backgroundColor: Colors.white),
          ),
        ),
      ),
      const SizedBox(height: FgSpace.s4),
      FgNotice(tone: FgTone.info, icon: FgIcons.qr, message: s.t('arrivalQr')),
      if (expires != null) ...[
        const SizedBox(height: FgSpace.s2),
        Text(s.t('qrValidUntil', [fmtDate(expires, s.lang)]), textAlign: TextAlign.center, style: context.tt.bodySmall),
      ],
    ]);
  }
}

/// Booking detail: status of the request; the workshop's alternative time (accept / decline); the arrival QR once
/// confirmed (POST /bookings/{id}/qr).
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.appointmentId});
  final String appointmentId;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  bool _busy = false;
  FgRow? _qr;
  Object? _qrError;
  bool _qrRequested = false;

  String get _id => Uri.encodeComponent(widget.appointmentId);

  Future<void> _answer(bool accept) async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/bookings/$_id/${accept ? 'accept-proposal' : 'decline-proposal'}', idempotencyKey: const Uuid().v4());
      if (!mounted) return;
      showDone(context, s.t(accept ? 'proposalAccepted' : 'proposalDeclined'));
      ref.invalidate(bookingProvider(widget.appointmentId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// D-108: the driver reports arrival at the gate; the booking moves to the gate's "Driver at the gate" lane.
  Future<void> _arrived() async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/bookings/$_id/arrived', idempotencyKey: const Uuid().v4());
      if (!mounted) return;
      showDone(context, s.t('iHaveArrivedDone'));
      ref.invalidate(bookingProvider(widget.appointmentId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "I have arrived" from 12 hours before the booked time (the workshop refuses earlier taps with the opening time).
  List<Widget> _arrival(Strings s, FgRow b) {
    final atGate = rowDate(b, 'AtGateDateTime');
    if (atGate != null && atGate.year > 1900) {
      return [FgNotice(tone: FgTone.good, icon: FgIcons.event('arrived'), message: s.t('atGateSince', [fmtDate(atGate, s.lang)])), const SizedBox(height: FgSpace.s3)];
    }
    final start = rowDate(b, 'StartDateTime');
    final opens = start?.subtract(const Duration(hours: 12));
    if (opens != null && opens.isAfter(DateTime.now())) {
      return [FgNotice(tone: FgTone.neutral, message: s.t('arrivalOpensAt', [fmtDate(opens, s.lang)])), const SizedBox(height: FgSpace.s3)];
    }
    return [
      Text(s.t('iHaveArrivedHint'), style: context.tt.bodySmall),
      const SizedBox(height: FgSpace.s2),
      FilledButton.icon(onPressed: _busy ? null : _arrived, icon: Icon(FgIcons.event('arrived'), size: 18), label: Text(s.t('iHaveArrived'))),
      const SizedBox(height: FgSpace.s3),
    ];
  }

  Future<void> _loadQr() async {
    setState(() {
      _qrRequested = true;
      _qrError = null;
    });
    try {
      final r = asRow(await ref.read(apiProvider).post('/bookings/$_id/qr'));
      if (mounted) setState(() => _qr = r);
    } catch (e) {
      if (mounted) setState(() => _qrError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final booking = ref.watch(bookingProvider(widget.appointmentId));
    return Scaffold(
      appBar: AppBar(title: Text(widget.appointmentId), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      body: FgRefresh(
        onRefresh: () => ref.refresh(bookingProvider(widget.appointmentId).future),
        child: AsyncBody(
          value: booking,
          loading: const SkeletonList(header: true, count: 2),
          onRetry: () => ref.invalidate(bookingProvider(widget.appointmentId)),
          builder: (b) {
            final status = rowField(b, 'Status');
            final orderId = rowField(b, 'ServiceOrderId');
            if (status == 'Confirmed' && !_qrRequested) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_qrRequested) _loadQr();
              });
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(FgSpace.s4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        IconTile(FgIcons.status(status), tone: toneOf(status)),
                        const SizedBox(width: FgSpace.s3),
                        Expanded(child: Text(s.t('bookingRequest'), style: context.tt.titleMedium)),
                        StatusPill(status),
                      ]),
                      const SizedBox(height: FgSpace.s3),
                      KeyValueRow(s.t('vehicle'), rowField(b, 'VehicleId'), icon: FgIcons.vehicles),
                      KeyValueRow(s.t('workshop'), rowField(b, 'Workshop'), icon: FgIcons.workshop),
                      KeyValueRow(s.t('date'), fmtDate(rowDate(b, 'StartDateTime') ?? rowDate(b, 'Start'), s.lang), icon: FgIcons.calendar, tabular: true),
                      if (rowField(b, 'ServiceType').isNotEmpty) KeyValueRow(s.t('serviceType'), s.status(rowField(b, 'ServiceType')), icon: FgIcons.tasks),
                      if (rowField(b, 'JobTypeId').isNotEmpty) KeyValueRow(s.t('jobType'), rowField(b, 'JobTypeId'), icon: FgIcons.checklist),
                      if (rowField(b, 'DriverName').isNotEmpty) KeyValueRow(s.t('bookingDriver'), rowField(b, 'DriverName'), icon: FgIcons.vehicles),
                      if (orderId.isNotEmpty)
                        KeyValueRow(
                          s.t('order'),
                          orderId,
                          icon: FgIcons.orders,
                          valueWidget: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(onPressed: () => context.push('/orders/${Uri.encodeComponent(orderId)}'), child: Text(orderId)),
                          ),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: FgSpace.s3),
                ...switch (status) {
                  'Requested' || 'Held' => [FgNotice(tone: FgTone.attention, icon: FgIcons.waiting, title: s.t('bookingWaiting'), message: s.t('bookingWaitingText'))],
                  'Proposed' => [_proposal(s, b)],
                  'Confirmed' => [
                      ..._arrival(s, b),
                      if (_qr != null && _qr!.s('arrivalToken').isNotEmpty)
                        ArrivalQrCard(token: _qr!.s('arrivalToken'), expires: _qr!.d('expires'))
                      else if (_qrError != null)
                        ErrorState(error: _qrError!, compact: true, onRetry: _loadQr)
                      else
                        const Padding(padding: EdgeInsets.all(FgSpace.s6), child: Center(child: CircularProgressIndicator())),
                    ],
                  'Declined' => [
                      FgNotice(
                        tone: FgTone.bad,
                        icon: FgIcons.declined,
                        title: s.t('bookingDeclined'),
                        message: rowField(b, 'ReviewReason').isEmpty ? s.t('bookingDeclinedText') : '${s.t('reason')}: ${rowField(b, 'ReviewReason')}',
                      ),
                      const SizedBox(height: FgSpace.s3),
                      FilledButton.icon(onPressed: () => context.go('/book'), icon: const Icon(FgIcons.book, size: 18), label: Text(s.t('bookAgain'))),
                    ],
                  'Arrived' => [FgNotice(tone: FgTone.good, icon: FgIcons.event('arrived'), message: s.t('bookingArrived'))],
                  _ => [FgNotice(tone: FgTone.neutral, message: s.status(status))],
                },
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _proposal(Strings s, FgRow b) {
    final fg = context.fg;
    final proposed = rowDate(b, 'ProposedStart');
    return Card(
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: fg.action, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(FgSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const IconTile(FgIcons.proposal, tone: FgTone.attention),
            const SizedBox(width: FgSpace.s3),
            Expanded(child: Text(s.t('proposalTitle'), style: context.tt.titleMedium)),
          ]),
          const SizedBox(height: FgSpace.s3),
          Text(fmtDate(proposed, s.lang), style: context.tt.headlineSmall?.copyWith(fontFeatures: FgFonts.tabular)),
          if (rowField(b, 'ReviewReason').isNotEmpty) Text('${s.t('reason')}: ${rowField(b, 'ReviewReason')}', style: context.tt.bodySmall),
          const SizedBox(height: FgSpace.s4),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _answer(false),
                icon: const Icon(FgIcons.close, size: 18),
                label: Text(s.t('decline')),
              ),
            ),
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _answer(true),
                icon: const Icon(FgIcons.check, size: 18),
                label: Text(s.t('accept')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// "Your booking requests" (ids remembered on this phone) with their live status.
class MyBookingsList extends ConsumerWidget {
  const MyBookingsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final ids = ref.watch(myBookingsProvider).value ?? const <String>[];
    if (ids.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FgSectionTitle(s.t('myBookingRequests'), count: ids.length),
      for (final id in ids.take(5)) ...[
        _BookingTile(appointmentId: id),
        const SizedBox(height: FgSpace.s2),
      ],
    ]);
  }
}

class _BookingTile extends ConsumerWidget {
  const _BookingTile({required this.appointmentId});
  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final b = ref.watch(bookingProvider(appointmentId));
    final row = b.value;
    final status = row == null ? '' : rowField(row, 'Status');
    return FgListCard(
      leading: IconTile(status.isEmpty ? FgIcons.calendar : FgIcons.status(status), tone: status.isEmpty ? FgTone.neutral : toneOf(status)),
      title: appointmentId,
      subtitle: row == null ? (b.hasError ? s.t('errorTitle') : s.t('loading')) : '${rowField(row, 'VehicleId')} · ${fmtDate(rowDate(row, 'StartDateTime'), s.lang)}',
      trailing: status.isEmpty ? null : StatusPill(status, dense: true),
      onTap: () => context.push('/bookings/${Uri.encodeComponent(appointmentId)}'),
    );
  }
}
