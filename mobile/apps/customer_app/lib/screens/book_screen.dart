import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'booking_screen.dart';
import 'vehicles_screen.dart';

/// Workshop network for a vehicle: distance (when a location is sent), rating, on-time %, next free slot and whether the
/// workshop reviews requests (GET /workshops/network). Key: (vehicleId, hours).
final workshopNetworkProvider = FutureProvider.autoDispose.family<List<FgRow>, (String, double)>(
  (ref, key) async => asRows(await ref.watch(apiProvider).get('/workshops/network', query: {'vehicleId': key.$1, 'hours': key.$2})),
);

/// Job types ({id, name, nameAr, defaultHours, requiresApproval}) and variants for the e-check-in.
final jobTypesProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async => asRows(await ref.watch(apiProvider).get('/lookups/job-types')));
final jobVariantsProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async => asRows(await ref.watch(apiProvider).get('/lookups/job-variants')));

const _serviceTypes = ['Preventive', 'Corrective', 'Inspection'];
const _durations = [0.5, 1.0, 2.0, 3.0, 4.0, 8.0];
const _channels = ['Portal', 'Push', 'Sms', 'WhatsApp', 'Email'];

String _hoursLabel(Strings s, double h) => s.t('hoursShort', [h == h.roundToDouble() ? h.round() : h]);

/// Booking wizard: Vehicle → Service (job type, variant) → Workshop (network) → Date & time (free slots, a short hold)
/// → E-check-in & request. The workshop confirms the request (or it is confirmed at once in workshops that allow it);
/// only a confirmed booking gets the arrival QR. Booking needs the network (capacity is decided live): no outbox.
class BookScreen extends ConsumerStatefulWidget {
  const BookScreen({super.key, this.vehicleId});
  final String? vehicleId;

  @override
  ConsumerState<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends ConsumerState<BookScreen> {
  late int _step = widget.vehicleId == null ? 0 : 1;
  String? _vehicle;
  String? _workshop;
  String _workshopName = '';
  DateTime _day = DateTime.now().add(const Duration(days: 1));
  double _hours = 1;
  String _type = 'Preventive';
  String? _jobType;
  String? _variant;
  bool _pickup = false;
  bool _replacement = false;
  String _channel = 'Portal';
  final _complaint = TextEditingController();
  final _odometer = TextEditingController();
  List<FgRow>? _slots;
  FgRow? _hold;
  FgRow? _result;
  bool _busy = false;
  Object? _error;

  @override
  void didUpdateWidget(BookScreen old) {
    super.didUpdateWidget(old);
    // Opened again from a vehicle ("Book" on vehicle 360): start over with that vehicle.
    if (widget.vehicleId != null && widget.vehicleId != old.vehicleId) {
      _vehicle = widget.vehicleId;
      _step = 1;
      _workshop = null;
      _reset();
      _result = null;
    }
  }

  @override
  void dispose() {
    _complaint.dispose();
    _odometer.dispose();
    super.dispose();
  }

  void _reset() {
    _slots = null;
    _hold = null;
    _error = null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = e;
      FgHaptics.warning();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findSlots() => _run(() async {
        final day = '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';
        final res = await ref.read(apiProvider).get('/workshops/${Uri.encodeComponent(_workshop!)}/slots', query: {'vehicleId': _vehicle, 'date': day, 'hours': _hours});
        _slots = asRows(res);
        _hold = null;
      });

  Future<void> _holdSlot(FgRow slot) => _run(() async {
        FgHaptics.tap();
        final res = asRow(await ref.read(apiProvider).post('/bookings',
            body: {'vehicleId': _vehicle, 'workshop': _workshop, 'startUtc': slot.s('startUtc'), 'hours': _hours, 'serviceType': _type},
            idempotencyKey: const Uuid().v4()));
        _hold = {...res, 'startLocal': slot.s('startLocal')};
      });

  /// Sends the held slot as a request with the e-check-in (POST /bookings/{id}/request).
  Future<void> _request() => _run(() async {
        final id = _hold!.s('appointmentId');
        final result = asRow(await ref.read(apiProvider).post('/bookings/${Uri.encodeComponent(id)}/request', idempotencyKey: const Uuid().v4(), body: {
          'jobTypeId': _jobType,
          'variantId': _variant,
          'pickup': _pickup,
          'replacement': _replacement,
          'complaint': _complaint.text.trim(),
          'odometer': double.tryParse(_odometer.text.replaceAll(',', '.').trim()) ?? 0,
          'channel': _channel,
        }));
        await ref.read(myBookingsProvider.notifier).remember(id);
        FgHaptics.success();
        _result = {...result, 'appointmentId': result.s('appointmentId').isEmpty ? id : result.s('appointmentId')};
      });

  bool get _canContinue => switch (_step) {
        0 => _vehicle != null,
        1 => true,
        2 => _workshop != null,
        3 => _hold != null,
        _ => false,
      };

  void _go(int step) {
    FgHaptics.tap();
    setState(() {
      _step = step;
      _error = null;
    });
  }

  void _startOver() => setState(() {
        _result = null;
        _reset();
        _complaint.clear();
        _odometer.clear();
        _pickup = false;
        _replacement = false;
        _step = 0;
      });

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    if (_result != null) {
      final r = _result!;
      return r.s('status') == 'Confirmed' && r.s('arrivalToken').isNotEmpty
          ? _Confirmation(confirmed: r, onDone: _startOver)
          : _Requested(result: r, workshopName: _workshopName, onDone: _startOver);
    }

    final vehicles = ref.watch(vehiclesProvider);
    final steps = [s.t('stepVehicle'), s.t('stepService'), s.t('stepWorkshop'), s.t('stepSlot'), s.t('stepCheckIn')];
    final vs = vehicles.value ?? const <FgRow>[];
    _vehicle ??= widget.vehicleId ?? (vs.isEmpty ? null : vs.first.s('VehicleId'));

    final Widget body = switch (_step) {
      0 => _vehicleStep(s, vehicles),
      1 => _serviceStep(s),
      2 => _workshopStep(s),
      3 => _slotStep(s),
      _ => _checkInStep(s, vs),
    };

    return Scaffold(
      appBar: AppBar(title: Text(s.t('book')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      bottomNavigationBar: FgActionBar(
        top: _error == null
            ? null
            : Padding(padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s3, FgSpace.gutter, 0), child: ErrorText(_error!, textAlign: TextAlign.start)),
        children: [
          if (_step > 0) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _go(_step - 1),
              icon: const Icon(FgIcons.arrowBack, size: 18),
              label: Text(s.t('back')),
            ),
            const SizedBox(width: FgSpace.s3),
          ],
          Expanded(
            child: _step < 4
                ? FilledButton.icon(
                    onPressed: _busy || !_canContinue ? null : () => _go(_step + 1),
                    icon: const Icon(FgIcons.arrowForward, size: 18),
                    label: Text(s.t('continue')),
                  )
                : FilledButton.icon(
                    onPressed: _busy || _hold == null ? null : _request,
                    icon: _busy
                        ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.fg.onAction))
                        : const Icon(FgIcons.send, size: 18),
                    label: Text(s.t('sendRequest')),
                  ),
          ),
        ],
      ),
      body: Column(children: [
        FgStepperHeader(steps: steps, current: _step, onStep: _busy ? null : _go),
        Divider(height: 1, color: context.fg.border),
        Expanded(
          child: AnimatedSwitcher(
            duration: FgMotion.base,
            switchInCurve: FgMotion.easeOut,
            child: KeyedSubtree(key: ValueKey(_step), child: body),
          ),
        ),
      ]),
    );
  }

  Widget _selectable({required bool selected, required Widget child, required VoidCallback onTap, String? semantics}) {
    final fg = context.fg;
    return Semantics(
      selected: selected,
      button: true,
      label: semantics,
      child: Material(
        color: selected ? fg.primaryBg : fg.surface,
        shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: selected ? fg.primary : fg.border, width: selected ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            FgHaptics.tap();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(FgSpace.s3),
            child: Row(children: [
              Expanded(child: child),
              const SizedBox(width: FgSpace.s2),
              Icon(selected ? FgIcons.good : FgIcons.neutral, color: selected ? fg.primary : fg.textMuted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _vehicleStep(Strings s, AsyncValue<List<FgRow>> vehicles) => AsyncBody(
        value: vehicles,
        onRetry: () => ref.invalidate(vehiclesProvider),
        builder: (vs) => ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
          const MyBookingsList(),
          if (vs.isEmpty) EmptyState(art: FgArt.vehicle, title: s.t('noVehicles')),
          if (vs.isNotEmpty) ...[
            Text(s.t('chooseVehicle'), style: context.tt.titleMedium),
            const SizedBox(height: FgSpace.s3),
          ],
          for (final v in vs) ...[
            _selectable(
              selected: _vehicle == v.s('VehicleId'),
              semantics: vehicleOption(v),
              onTap: () => setState(() {
                _vehicle = v.s('VehicleId');
                _workshop = null;
                _reset();
              }),
              child: Row(children: [
                VehicleArt(kind: vehicleKindOf(v.s('VehicleClass')), width: 72),
                const SizedBox(width: FgSpace.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    PlateBadge(vehiclePlate(v)),
                    const SizedBox(height: FgSpace.s1),
                    Text(vehicleTitle(v), style: context.tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: FgSpace.s2),
          ],
        ]),
      );

  Widget _serviceStep(Strings s) {
    final jobTypes = ref.watch(jobTypesProvider);
    final variants = ref.watch(jobVariantsProvider).value ?? const <FgRow>[];
    String name(FgRow r) => s.lang == 'ar' && r.s('nameAr').isNotEmpty ? r.s('nameAr') : r.s('name');
    return ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
      Text(s.t('chooseService'), style: context.tt.titleMedium),
      const SizedBox(height: FgSpace.s3),
      for (final t in _serviceTypes) ...[
        _selectable(
          selected: _type == t,
          semantics: s.status(t),
          onTap: () => setState(() {
            _type = t;
            _reset();
          }),
          child: Row(children: [
            IconTile(switch (t) { 'Preventive' => FgIcons.promise, 'Corrective' => FgIcons.tasks, _ => FgIcons.inspection }, tone: FgTone.progress),
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.status(t), style: context.tt.titleSmall),
                Text(s.t('svc$t'), style: context.tt.bodySmall),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: FgSpace.s2),
      ],
      const SizedBox(height: FgSpace.s3),
      switch (jobTypes) {
        AsyncData(:final value) => DropdownButtonFormField<String>(
            initialValue: _jobType,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.t('jobType'), prefixIcon: const Icon(FgIcons.checklist, size: 20)),
            items: [
              DropdownMenuItem<String>(value: null, child: Text(s.t('notSure'))),
              for (final j in value) DropdownMenuItem(value: j.s('id'), child: Text('${j.s('id')} – ${name(j)}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _jobType = v;
              // The job type's standard hours become the suggested duration.
              final hours = value.where((j) => j.s('id') == v).firstOrNull?.n('defaultHours') ?? 0;
              if (hours > 0) {
                _hours = _durations.firstWhere((d) => d >= hours, orElse: () => _durations.last);
                _reset();
              }
            }),
          ),
        AsyncError() => FgNotice(tone: FgTone.attention, message: s.t('jobTypesUnavailable')),
        _ => const LinearProgressIndicator(),
      },
      if (variants.isNotEmpty) ...[
        const SizedBox(height: FgSpace.s3),
        DropdownButtonFormField<String>(
          initialValue: _variant,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.t('jobVariant')),
          items: [
            DropdownMenuItem<String>(value: null, child: Text(s.t('none'))),
            for (final v in variants) DropdownMenuItem(value: v.s('id'), child: Text('${v.s('id')} – ${name(v)}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _variant = v),
        ),
      ],
      const SizedBox(height: FgSpace.s4),
      Text(s.t('duration'), style: context.tt.titleMedium),
      const SizedBox(height: FgSpace.s2),
      Wrap(spacing: FgSpace.s2, runSpacing: FgSpace.s2, children: [
        for (final h in _durations)
          ChoiceChip(
            label: Text(_hoursLabel(s, h)),
            selected: _hours == h,
            onSelected: (_) {
              FgHaptics.tap();
              setState(() {
                _hours = h;
                _reset();
              });
            },
          ),
      ]),
    ]);
  }

  Widget _workshopStep(Strings s) {
    if (_vehicle == null) return ListView(children: [EmptyState(art: FgArt.vehicle, title: s.t('chooseVehicle'))]);
    final network = ref.watch(workshopNetworkProvider((_vehicle!, _hours)));
    return AsyncBody(
      value: network,
      onRetry: () => ref.invalidate(workshopNetworkProvider((_vehicle!, _hours))),
      builder: (shops) => ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
        Text(s.t('chooseWorkshop'), style: context.tt.titleMedium),
        const SizedBox(height: FgSpace.s3),
        if (shops.isEmpty) EmptyState(compact: true, title: s.t('noData')),
        for (final w in shops) ...[
          _selectable(
            selected: _workshop == w.s('workshopId'),
            semantics: w.s('name'),
            onTap: () => setState(() {
              _workshop = w.s('workshopId');
              _workshopName = w.s('name');
              _reset();
            }),
            child: _WorkshopInfo(row: w),
          ),
          const SizedBox(height: FgSpace.s2),
        ],
      ]),
    );
  }

  Widget _slotStep(Strings s) {
    final today = DateTime.now();
    final days = [for (var i = 1; i <= 14; i++) DateTime(today.year, today.month, today.day + i)];
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    return ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
      Row(children: [
        Expanded(child: Text(s.t('chooseDay'), style: context.tt.titleMedium)),
        TextButton.icon(
          icon: const Icon(FgIcons.calendar, size: 18),
          label: Text(s.t('otherDate')),
          onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180)));
            if (picked != null && mounted) {
              setState(() {
                _day = picked;
                _reset();
              });
            }
          },
        ),
      ]),
      const SizedBox(height: FgSpace.s2),
      SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: days.length,
          separatorBuilder: (context, index) => const SizedBox(width: FgSpace.s2),
          itemBuilder: (context, i) {
            final d = days[i];
            final selected = sameDay(d, _day);
            final fg = context.fg;
            return Semantics(
              selected: selected,
              button: true,
              label: fmtDate(d, s.lang, time: false),
              excludeSemantics: true,
              child: Material(
                color: selected ? fg.primary : fg.surface,
                shape: RoundedRectangleBorder(borderRadius: FgRadius.brMd, side: BorderSide(color: selected ? fg.primary : fg.border)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    FgHaptics.tap();
                    setState(() {
                      _day = d;
                      _reset();
                    });
                  },
                  child: SizedBox(
                    width: 60,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(fmtWeekday(d, s.lang), style: context.tt.labelSmall?.copyWith(color: selected ? fg.onPrimary : fg.textMuted)),
                      const SizedBox(height: 2),
                      Text('${d.day}', style: context.tt.titleLarge?.copyWith(color: selected ? fg.onPrimary : fg.text, fontFeatures: FgFonts.tabular)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: FgSpace.s3),
      Text(fmtDate(_day, s.lang, time: false), style: context.tt.bodySmall),
      const SizedBox(height: FgSpace.s3),
      OutlinedButton.icon(
        onPressed: _busy || _vehicle == null || _workshop == null ? null : _findSlots,
        icon: const Icon(FgIcons.search, size: 18),
        label: Text(s.t('findSlots')),
      ),
      if (_busy) const Padding(padding: EdgeInsets.all(FgSpace.s4), child: Center(child: CircularProgressIndicator())),
      if (_slots != null && _slots!.isEmpty) EmptyState(compact: true, art: FgArt.calendar, title: s.t('noSlots'), message: s.t('noSlotsHint')),
      if (_slots != null && _slots!.isNotEmpty) ...[
        const SizedBox(height: FgSpace.s4),
        Text(s.t('freeTimes'), style: context.tt.titleSmall),
        const SizedBox(height: FgSpace.s2),
        Wrap(spacing: FgSpace.s2, runSpacing: FgSpace.s2, children: [
          for (final slot in _slots!)
            ChoiceChip(
              label: Text(slot.s('startLocal').trim(), style: const TextStyle(fontFeatures: FgFonts.tabular)),
              selected: _hold != null && _hold!.s('startLocal') == slot.s('startLocal'),
              onSelected: _busy ? null : (_) => _holdSlot(slot),
            ),
        ]),
      ],
      if (_hold != null) ...[
        const SizedBox(height: FgSpace.s4),
        FgNotice(tone: FgTone.good, icon: FgIcons.time, message: s.t('heldUntil', [fmtDate(_hold!.d('holdExpiresUtc'), s.lang)])),
      ],
    ]);
  }

  Widget _checkInStep(Strings s, List<FgRow> vs) {
    final v = vs.where((x) => x.s('VehicleId') == _vehicle).firstOrNull;
    return ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
      Text(s.t('checkInTitle'), style: context.tt.titleMedium),
      Text(s.t('checkInHint'), style: context.tt.bodySmall),
      const SizedBox(height: FgSpace.s3),
      TextField(
        controller: _complaint,
        minLines: 2,
        maxLines: 4,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: s.t('complaint'), alignLabelWithHint: true),
      ),
      const SizedBox(height: FgSpace.s2),
      TextField(
        controller: _odometer,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontFeatures: FgFonts.tabular),
        decoration: InputDecoration(
          labelText: s.t('odometer'),
          suffixText: 'km',
          prefixIcon: const Icon(FgIcons.odometer, size: 20),
          helperText: v == null ? null : '${s.t('lastReading')}: ${fmtKm(v.n('CurrentOdometer'))}',
        ),
      ),
      const SizedBox(height: FgSpace.s3),
      Card(
        child: Column(children: [
          SwitchListTile(
            value: _pickup,
            onChanged: (x) {
              FgHaptics.tap();
              setState(() => _pickup = x);
            },
            secondary: const IconTile(FgIcons.mobility, size: 40),
            title: Text(s.t('pickupRequest')),
            subtitle: Text(s.t('pickupRequestHint')),
          ),
          const Divider(),
          SwitchListTile(
            value: _replacement,
            onChanged: (x) {
              FgHaptics.tap();
              setState(() => _replacement = x);
            },
            secondary: const IconTile(FgIcons.pool, size: 40),
            title: Text(s.t('replacementRequest')),
            subtitle: Text(s.t('replacementRequestHint')),
          ),
        ]),
      ),
      const SizedBox(height: FgSpace.s4),
      Text(s.t('contactChannel'), style: context.tt.titleSmall),
      const SizedBox(height: FgSpace.s2),
      Wrap(spacing: FgSpace.s2, runSpacing: FgSpace.s2, children: [
        for (final c in _channels)
          ChoiceChip(
            label: Text(s.t('channel$c')),
            selected: _channel == c,
            onSelected: (_) {
              FgHaptics.tap();
              setState(() => _channel = c);
            },
          ),
      ]),
      const SizedBox(height: FgSpace.s4),
      Text(s.t('reviewBooking'), style: context.tt.titleMedium),
      const SizedBox(height: FgSpace.s2),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(FgSpace.s4),
          child: Column(children: [
            KeyValueRow(s.t('vehicle'), v == null ? (_vehicle ?? '') : vehicleOption(v), icon: FgIcons.vehicles),
            KeyValueRow(s.t('serviceType'), s.status(_type), icon: FgIcons.tasks),
            if (_jobType != null) KeyValueRow(s.t('jobType'), [_jobType!, if (_variant != null) _variant!].join(' / '), icon: FgIcons.checklist),
            KeyValueRow(s.t('duration'), _hoursLabel(s, _hours), icon: FgIcons.time, tabular: true),
            KeyValueRow(s.t('workshop'), _workshopName.isEmpty ? (_workshop ?? '') : _workshopName, icon: FgIcons.workshop),
            KeyValueRow(s.t('date'), '${fmtDate(_day, s.lang, time: false)} · ${_hold?.s('startLocal').trim() ?? ''}', icon: FgIcons.calendar, tabular: true),
          ]),
        ),
      ),
      if (_hold != null) ...[
        const SizedBox(height: FgSpace.s3),
        FgNotice(tone: FgTone.attention, icon: FgIcons.time, message: s.t('heldUntil', [fmtDate(_hold!.d('holdExpiresUtc'), s.lang)])),
      ],
      const SizedBox(height: FgSpace.s3),
      Text(s.t('requestHint'), style: context.tt.bodySmall),
    ]);
  }
}

/// One workshop of the network: name, place, rating, on-time %, distance, next free slot, review policy.
class _WorkshopInfo extends ConsumerWidget {
  const _WorkshopInfo({required this.row});
  final FgRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    final w = row;
    final next = w.d('nextSlot');
    Widget fact(IconData icon, String text, [Color? color]) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color ?? fg.textMuted),
          const SizedBox(width: 4),
          Text(text, style: context.tt.labelMedium?.copyWith(color: color ?? fg.textMuted, fontFeatures: FgFonts.tabular)),
        ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const IconTile(FgIcons.workshop),
      const SizedBox(width: FgSpace.s3),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(w.s('name').isEmpty ? w.s('workshopId') : w.s('name'), style: context.tt.titleSmall),
          if ([w.s('city'), w.s('address')].any((x) => x.isNotEmpty))
            Text([w.s('city'), w.s('address')].where((x) => x.isNotEmpty).join(' · '), style: context.tt.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: FgSpace.s1),
          Wrap(spacing: FgSpace.s3, runSpacing: 2, children: [
            if (w['distanceKm'] != null) fact(FgIcons.location, '${fmtNum(w.n('distanceKm'), decimals: 1)} km'),
            if (w['rating'] != null) fact(FgIcons.star, '${fmtNum(w.n('rating'), decimals: 1)} (${w.s('ratings')})', fg.warning),
            if (w['onTimePct'] != null) fact(FgIcons.promise, s.t('onTimePct', [fmtNum(w.n('onTimePct'))])),
            fact(FgIcons.calendar, next == null ? s.t('noSlotSoon') : '${s.t('nextFree')}: ${fmtShortDate(next, s.lang)} ${fmtTime(next, s.lang)}', next == null ? null : fg.primary),
          ]),
          const SizedBox(height: FgSpace.s1),
          StatusPill(
            w['reviewRequired'] == true ? 'Requested' : 'Confirmed',
            label: s.t(w['reviewRequired'] == true ? 'workshopReviews' : 'instantConfirmation'),
            dense: true,
          ),
        ]),
      ),
    ]);
  }
}

/// Request sent, waiting for the workshop (no QR yet).
class _Requested extends ConsumerWidget {
  const _Requested({required this.result, required this.workshopName, required this.onDone});
  final FgRow result;
  final String workshopName;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final id = result.s('appointmentId');
    return Scaffold(
      appBar: AppBar(title: Text(s.t('bookingWaiting'))),
      bottomNavigationBar: FgActionBar(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => context.push('/bookings/${Uri.encodeComponent(id)}'),
            child: Text(s.t('openBooking')),
          ),
        ),
        const SizedBox(width: FgSpace.s3),
        Expanded(child: FilledButton(onPressed: onDone, child: Text(s.t('done')))),
      ]),
      body: ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
        const Center(child: FgIllustration(FgArt.calendar, size: 120)),
        const SizedBox(height: FgSpace.s3),
        Text(s.t('requestSent'), textAlign: TextAlign.center, style: context.tt.headlineSmall),
        const SizedBox(height: FgSpace.s1),
        Text(
          [id, if (result.s('serviceOrderId').isNotEmpty) '${s.t('order')} ${result.s('serviceOrderId')}'].join(' · '),
          textAlign: TextAlign.center,
          style: context.tt.bodySmall?.copyWith(fontFeatures: FgFonts.tabular),
        ),
        const SizedBox(height: FgSpace.s5),
        FgNotice(
          tone: FgTone.attention,
          icon: FgIcons.waiting,
          title: s.t('bookingWaiting'),
          message: s.t('bookingWaitingText') + (workshopName.isEmpty ? '' : ' ($workshopName)'),
        ),
      ]),
    );
  }
}

/// Booking confirmed at once: one-time arrival QR for the gate, and the service order it created.
class _Confirmation extends ConsumerWidget {
  const _Confirmation({required this.confirmed, required this.onDone});
  final FgRow confirmed;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = confirmed;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('bookingConfirmed'))),
      bottomNavigationBar: FgActionBar(children: [
        if (c.s('serviceOrderId').isNotEmpty) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: () => context.push('/orders/${Uri.encodeComponent(c.s('serviceOrderId'))}'),
              child: Text(s.t('viewOrder')),
            ),
          ),
          const SizedBox(width: FgSpace.s3),
        ],
        Expanded(child: FilledButton(onPressed: onDone, child: Text(s.t('done')))),
      ]),
      body: ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
        const Center(child: FgIllustration(FgArt.done, size: 120)),
        const SizedBox(height: FgSpace.s3),
        Text(s.t('bookingConfirmed'), textAlign: TextAlign.center, style: context.tt.headlineSmall),
        const SizedBox(height: FgSpace.s1),
        Text('${c.s('appointmentId')} · ${s.t('order')} ${c.s('serviceOrderId')}', textAlign: TextAlign.center, style: context.tt.bodySmall?.copyWith(fontFeatures: FgFonts.tabular)),
        const SizedBox(height: FgSpace.s5),
        ArrivalQrCard(token: c.s('arrivalToken')),
      ]),
    );
  }
}
