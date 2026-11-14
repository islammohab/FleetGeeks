import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

final poolBookingsProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async => asRows(await ref.watch(apiProvider).get('/pool/bookings')));
final poolDriversProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async => asRows(await ref.watch(apiProvider).get('/drivers')));

/// Pool vehicles: find a free vehicle for a period and book it (online, so the availability is current); check-out
/// and check-in with the odometer go through the outbox (they work without signal at the car park).
class PoolScreen extends ConsumerStatefulWidget {
  const PoolScreen({super.key});

  @override
  ConsumerState<PoolScreen> createState() => _PoolScreenState();
}

class _PoolScreenState extends ConsumerState<PoolScreen> {
  DateTime _from = DateTime.now().add(const Duration(days: 1)).copyWith(hour: 8, minute: 0, second: 0, millisecond: 0, microsecond: 0);
  DateTime _to = DateTime.now().add(const Duration(days: 1)).copyWith(hour: 17, minute: 0, second: 0, millisecond: 0, microsecond: 0);
  String? _driver;
  List<FgRow>? _free;
  bool _busy = false;

  Future<DateTime?> _pick(DateTime initial) async {
    final day = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (day == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).get('/pool/availability', query: {'fromUtc': _from.toUtc().toIso8601String(), 'toUtc': _to.toUtc().toIso8601String()});
      if (!mounted) return;
      FgHaptics.light();
      setState(() => _free = asRows(r));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _book(FgRow vehicle) async {
    final s = ref.read(stringsProvider);
    try {
      final r = asRow(await ref.read(apiProvider).post('/pool/bookings', idempotencyKey: const Uuid().v4(), body: {
        'vehicleId': vehicle.s('vehicleId'),
        'driverId': _driver,
        'fromUtc': _from.toUtc().toIso8601String(),
        'toUtc': _to.toUtc().toIso8601String(),
        'purpose': '',
      }));
      if (!mounted) return;
      showDone(context, s.t('poolBooked', [r.s('bookingId')]));
      setState(() => _free = null);
      ref.invalidate(poolBookingsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _step(FgRow booking, String verb) async {
    final s = ref.read(stringsProvider);
    double odometer = 0;
    if (verb != 'cancel') {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(verb == 'check-out' ? FgIcons.pool : FgIcons.release),
          title: Text(s.t(verb == 'check-out' ? 'checkOut' : 'checkIn')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontFeatures: FgFonts.tabular),
            decoration: InputDecoration(labelText: s.t('odometer'), suffixText: 'km'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('save'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      odometer = double.tryParse(controller.text.trim()) ?? 0;
    }
    if (!mounted) return;
    await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit('/pool/bookings/${Uri.encodeComponent(booking.s('BookingId'))}/$verb',
          label: '${s.t(verb == 'cancel' ? 'cancel' : verb == 'check-out' ? 'checkOut' : 'checkIn')} ${booking.s('BookingId')}',
          body: verb == 'cancel' ? const <String, Object?>{} : {'odometer': odometer}),
    );
    ref.invalidate(poolBookingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final drivers = ref.watch(poolDriversProvider).value ?? const <FgRow>[];
    final bookings = ref.watch(poolBookingsProvider);
    _driver ??= drivers.isEmpty ? null : drivers.first.s('id');

    Widget when(String label, DateTime value, VoidCallback onTap) => Expanded(
          child: Material(
            color: context.fg.surface2,
            borderRadius: FgRadius.brMd,
            child: InkWell(
              borderRadius: FgRadius.brMd,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(FgSpace.s3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: context.tt.labelSmall),
                  const SizedBox(height: 2),
                  Text(fmtShortDate(value, s.lang), style: context.tt.titleSmall),
                  Text(fmtTime(value, s.lang), style: context.tt.bodySmall?.copyWith(fontFeatures: FgFonts.tabular)),
                ]),
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.t('pool')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      bottomNavigationBar: OfflineBanner(safeArea: true, onOpenOutbox: () => context.push('/outbox')),
      body: FgRefresh(
        onRefresh: () => ref.refresh(poolBookingsProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6),
          children: [
            SectionCard(title: s.t('findVehicles'), icon: FgIcons.search, children: [
              Row(children: [
                when(s.t('from'), _from, () async {
                  final d = await _pick(_from);
                  if (d == null || !mounted) return;
                  setState(() {
                    _from = d;
                    _free = null;
                    if (!_to.isAfter(d)) _to = d.add(const Duration(hours: 4));
                  });
                }),
                Padding(padding: const EdgeInsets.symmetric(horizontal: FgSpace.s2), child: Icon(FgIcons.arrowForward, size: 18, color: context.fg.textMuted)),
                when(s.t('to'), _to, () async {
                  final d = await _pick(_to);
                  if (d == null || !mounted || !d.isAfter(_from)) return;
                  setState(() {
                    _to = d;
                    _free = null;
                  });
                }),
              ]),
              if (drivers.length > 1) ...[
                const SizedBox(height: FgSpace.s3),
                DropdownButtonFormField<String>(
                  initialValue: _driver,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s.t('driver'), prefixIcon: const Icon(FgIcons.driver, size: 20)),
                  items: [for (final d in drivers) DropdownMenuItem(value: d.s('id'), child: Text(d.s('name')))],
                  onChanged: (v) => setState(() => _driver = v),
                ),
              ],
              const SizedBox(height: FgSpace.s3),
              FilledButton.icon(
                onPressed: _busy ? null : _search,
                icon: _busy
                    ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.fg.onAction))
                    : const Icon(FgIcons.search, size: 18),
                label: Text(s.t('findVehicles')),
              ),
              if (_free != null && _free!.isEmpty) EmptyState(compact: true, art: FgArt.search, title: s.t('noPoolVehicles')),
              for (final v in _free ?? const <FgRow>[]) ...[
                const SizedBox(height: FgSpace.s3),
                VehicleCard(
                  plate: v.s('plate'),
                  title: '${v.s('make')} ${v.s('model')}',
                  vehicleClass: v.s('vehicleClass'),
                  status: 'Available',
                  trailing: FilledButton(onPressed: _driver == null ? null : () => _book(v), child: Text(s.t('bookShort'))),
                ),
              ],
            ]),
            FgSectionTitle(s.t('myBookings')),
            ...switch (bookings) {
              AsyncData(:final value) => [
                  if (value.isEmpty) EmptyState(compact: true, art: FgArt.calendar, title: s.t('noBookings')),
                  for (final b in value) ...[
                    FgListCard(
                      leading: IconTile(FgIcons.status(b.s('Status')), tone: toneOf(b.s('Status'))),
                      title: '${b.s('BookingId')} · ${b.s('VehicleId')}',
                      subtitle: '${fmtDate(b.d('FromDateTime'), s.lang)} – ${fmtDate(b.d('ToDateTime'), s.lang)}',
                      trailing: StatusPill(b.s('Status'), dense: true),
                      footer: b.s('Status') == 'Booked' || b.s('Status') == 'CheckedOut'
                          ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              if (b.s('Status') == 'Booked') ...[
                                TextButton.icon(onPressed: () => _step(b, 'cancel'), icon: const Icon(FgIcons.close, size: 18), label: Text(s.t('cancel'))),
                                const SizedBox(width: FgSpace.s2),
                                FilledButton.icon(onPressed: () => _step(b, 'check-out'), icon: const Icon(FgIcons.pool, size: 18), label: Text(s.t('checkOut'))),
                              ],
                              if (b.s('Status') == 'CheckedOut')
                                FilledButton.icon(onPressed: () => _step(b, 'check-in'), icon: const Icon(FgIcons.release, size: 18), label: Text(s.t('checkIn'))),
                            ])
                          : null,
                    ),
                    const SizedBox(height: FgSpace.s3),
                  ],
                ],
              AsyncError(:final error) => [ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(poolBookingsProvider))],
              _ => [const Shimmer(child: Column(children: [SkeletonCard(), SizedBox(height: FgSpace.s3), SkeletonCard()]))],
            },
          ],
        ),
      ),
    );
  }
}
