import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

final workshopsProvider = FutureProvider.autoDispose<List<FgRow>>((ref) async => asRows(await ref.watch(apiProvider).get('/workshops')));

/// Full-screen camera that returns the first QR value it reads (with a scan frame and a haptic on read).
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, required this.title, this.hint});
  final String title;
  final String? hint;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(widget.title, style: context.tt.titleLarge?.copyWith(color: Colors.white)),
        ),
        body: Stack(fit: StackFit.expand, children: [
          MobileScanner(
            onDetect: (capture) {
              final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
              if (_done || value == null || value.isEmpty) return;
              _done = true;
              FgHaptics.scan();
              Navigator.of(context).pop(value);
            },
          ),
          IgnorePointer(child: CustomPaint(painter: _FramePainter(accent: context.fg.action))),
          if (widget.hint != null)
            PositionedDirectional(
              start: FgSpace.s6,
              end: FgSpace.s6,
              bottom: FgSpace.s10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: FgSpace.s4, vertical: FgSpace.s3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: FgRadius.brMd),
                child: Text(widget.hint!, textAlign: TextAlign.center, style: context.tt.bodyMedium?.copyWith(color: Colors.white)),
              ),
            ),
        ]),
      );
}

/// Dimmed surroundings with a clear square and orange corner marks.
class _FramePainter extends CustomPainter {
  _FramePainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.68;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final hole = RRect.fromRectAndRadius(rect, const Radius.circular(FgRadius.xl));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    final corner = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    const len = 36.0;
    for (final (dx, dy) in const [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)]) {
      final x = dx < 0 ? rect.left : rect.right;
      final y = dy < 0 ? rect.top : rect.bottom;
      canvas.drawLine(Offset(x, y), Offset(x - dx * len, y), corner);
      canvas.drawLine(Offset(x, y), Offset(x, y - dy * len), corner);
    }
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.accent != accent;
}

/// Gate: arrival by the booking QR (online only: admission must be decided by D365 at the gate) and release by the
/// release code. Big buttons, then a result card.
class GateScreen extends ConsumerStatefulWidget {
  const GateScreen({super.key});

  @override
  ConsumerState<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends ConsumerState<GateScreen> {
  String? _workshop;
  final _name = TextEditingController();
  final _odometer = TextEditingController();
  final _idLast4 = TextEditingController();
  bool _busy = false;
  String? _message;
  String? _orderId;
  bool _error = false;
  bool _arrival = true;
  FgRow? _photo;
  FgRow? _verification;
  bool _photoBusy = false;
  Object? _photoError;

  @override
  void dispose() {
    _name.dispose();
    _odometer.dispose();
    _idLast4.dispose();
    super.dispose();
  }

  Future<void> _scan(bool arrival) async {
    final s = ref.read(stringsProvider);
    if (_name.text.trim().isEmpty) {
      FgHaptics.warning();
      setState(() {
        _message = '${arrival ? s.t('driverName') : s.t('collector')}?';
        _error = true;
        _orderId = null;
        _arrival = arrival;
        _photo = null;
        _verification = null;
      });
      return;
    }
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => QrScanPage(title: arrival ? s.t('scanQr') : s.t('scanRelease'), hint: s.t(arrival ? 'scanQrHint' : 'scanReleaseHint'))),
    );
    if (code == null || !mounted) return;
    setState(() {
      _busy = true;
      _arrival = arrival;
      _photo = null;
      _verification = null;
      _photoError = null;
    });
    var admitted = false;
    try {
      final api = ref.read(apiProvider);
      final odometer = double.tryParse(_odometer.text) ?? 0;
      if (arrival) {
        final r = asRow(await api.post('/workshop/gate/arrival', body: {'token': code.trim(), 'workshop': _workshop, 'driverName': _name.text.trim(), 'odometer': odometer}));
        final order = asRow(r['order']);
        _message = r.s('outcome') == 'Admitted'
            ? s.t('admitted', [order.s('serviceOrderId')])
            : s.t('alreadyAdmitted', [order.s('serviceOrderId'), s.status(order.s('status'))]);
        _orderId = order.s('serviceOrderId');
        _error = false;
        FgHaptics.success();
        admitted = _orderId!.isNotEmpty;
      } else {
        await api.post('/workshop/gate/release', body: {'token': code.trim(), 'collector': _name.text.trim(), 'idLast4': _idLast4.text.trim(), 'odometer': odometer});
        _message = s.t('released');
        _orderId = null;
        _error = false;
        FgHaptics.success();
      }
    } catch (e) {
      _message = '$e';
      _orderId = null;
      _error = true;
      FgHaptics.warning();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Arrival identity check: front photo -> plate recognition -> match with the booked vehicle.
    if (admitted && mounted) await _takeArrivalPhoto();
  }

  /// Front photo of the arriving vehicle (POST /workshop/gate/photo); the result card shows the match and, when the
  /// recognition is not sure, the manual verification.
  Future<void> _takeArrivalPhoto() async {
    final orderId = _orderId;
    if (orderId == null || orderId.isEmpty) return;
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.rear, imageQuality: 85, maxWidth: 2000);
    if (shot == null || !mounted) return;
    setState(() {
      _photoBusy = true;
      _photoError = null;
    });
    try {
      final r = asRow(await ref.read(apiProvider).upload('/workshop/gate/photo', filePath: shot.path, contentType: 'image/jpeg', fields: {'serviceOrderId': orderId}));
      if (!mounted) return;
      if (r['result'] == 'Passed') {
        FgHaptics.success();
      } else {
        FgHaptics.warning();
      }
      setState(() {
        _photo = r;
        _verification = null;
      });
    } catch (e) {
      if (mounted) setState(() => _photoError = e);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _verifyManually() async {
    final orderId = _orderId;
    if (orderId == null) return;
    final r = await showModalBottomSheet<FgRow>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ManualVerifySheet(orderId: orderId, photo: _photo),
    );
    if (r != null && mounted) setState(() => _verification = r);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final workshops = ref.watch(workshopsProvider);
    final online = ref.watch(connectivityProvider).value ?? true;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('gate')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      body: AsyncBody(
        value: workshops,
        onRetry: () => ref.invalidate(workshopsProvider),
        builder: (list) {
          _workshop ??= list.isEmpty ? null : list.first.s('WorkshopId');
          return ListView(padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6), children: [
            if (!online) ...[
              FgNotice(tone: FgTone.attention, icon: FgIcons.offline, message: s.t('gateNeedsNetwork')),
              const SizedBox(height: FgSpace.s3),
            ],
            SectionCard(title: s.t('gateDetails'), icon: FgIcons.driver, children: [
              DropdownButtonFormField<String>(
                initialValue: _workshop,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.t('workshop'), prefixIcon: const Icon(FgIcons.workshop, size: 20)),
                items: [for (final w in list) DropdownMenuItem(value: w.s('WorkshopId'), child: Text(w.s('WorkshopName'), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _workshop = v),
              ),
              const SizedBox(height: FgSpace.s3),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: '${s.t('driverName')} / ${s.t('collectorDriverId')}', prefixIcon: const Icon(FgIcons.driver, size: 20)),
              ),
              const SizedBox(height: FgSpace.s3),
              TextField(
                controller: _idLast4,
                maxLength: 4,
                decoration: InputDecoration(labelText: s.t('collectorId4'), counterText: '', prefixIcon: const Icon(FgIcons.driver, size: 20)),
              ),
              const SizedBox(height: FgSpace.s3),
              TextField(
                controller: _odometer,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFeatures: FgFonts.tabular),
                decoration: InputDecoration(labelText: s.t('odometer'), suffixText: 'km', prefixIcon: const Icon(FgIcons.odometer, size: 20)),
              ),
            ]),
            const SizedBox(height: FgSpace.s4),
            FgBigButton(
              icon: FgIcons.admit,
              label: s.t('scanQr'),
              caption: s.t('scanQrCaption'),
              height: 96,
              onPressed: _busy || _workshop == null ? null : () => _scan(true),
            ),
            const SizedBox(height: FgSpace.s3),
            FgBigButton(
              icon: FgIcons.release,
              label: s.t('scanRelease'),
              caption: s.t('scanReleaseCaption'),
              kind: FgButtonKind.primary,
              height: 96,
              onPressed: _busy ? null : () => _scan(false),
            ),
            const SizedBox(height: FgSpace.s4),
            AnimatedSwitcher(
              duration: FgMotion.base,
              child: _busy
                  ? const Padding(key: ValueKey('busy'), padding: EdgeInsets.all(FgSpace.s6), child: Center(child: CircularProgressIndicator()))
                  : _message == null
                      ? const SizedBox.shrink(key: ValueKey('none'))
                      : _ResultCard(
                          key: ValueKey(_message),
                          error: _error,
                          title: _error ? s.t('gateRefused') : s.t(_arrival ? 'gateAdmitted' : 'gateReleased'),
                          message: _message!,
                          onOpen: _orderId == null || _orderId!.isEmpty ? null : () => context.push('/orders/${Uri.encodeComponent(_orderId!)}'),
                          openLabel: s.t('openOrder'),
                        ),
            ),
            if (!_busy && !_error && _arrival && _orderId != null && _orderId!.isNotEmpty) ...[
              const SizedBox(height: FgSpace.s3),
              _ArrivalCheckCard(
                photo: _photo,
                verification: _verification,
                busy: _photoBusy,
                error: _photoError,
                onPhoto: _photoBusy ? null : _takeArrivalPhoto,
                onVerify: _verifyManually,
              ),
            ],
          ]);
        },
      ),
    );
  }
}

/// Tone of an arrival verification result (FGVerifyResult).
FgTone _verifyTone(String result) => switch (result) {
      'Passed' => FgTone.good,
      'Rejected' => FgTone.bad,
      'ManualReview' => FgTone.attention,
      _ => FgTone.neutral,
    };

/// Arrival identity: photo recognition result (read plate vs booked plate, confidence) and manual verification.
class _ArrivalCheckCard extends ConsumerWidget {
  const _ArrivalCheckCard({required this.photo, required this.verification, required this.busy, required this.error, required this.onPhoto, required this.onVerify});
  final FgRow? photo;
  final FgRow? verification;
  final bool busy;
  final Object? error;
  final VoidCallback? onPhoto;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final p = photo;
    final result = verification?.s('result') ?? p?.s('result') ?? '';
    final manual = verification == null && (p?['manualRequired'] == true);
    return SectionCard(
      title: s.t('arrivalCheck'),
      subtitle: s.t('arrivalCheckHint'),
      icon: FgIcons.scanPhoto,
      trailing: result.isEmpty ? null : StatusPill(result, dense: true),
      children: [
        if (busy) const Padding(padding: EdgeInsets.all(FgSpace.s4), child: Center(child: CircularProgressIndicator())),
        if (error != null) ErrorText(error!, textAlign: TextAlign.start),
        if (p != null) ...[
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('readPlate'), style: context.tt.labelSmall),
                const SizedBox(height: 2),
                p.s('readPlate').isEmpty ? Text('—', style: context.tt.titleMedium) : PlateBadge(p.s('readPlate')),
              ]),
            ),
            Icon(result == 'Passed' ? FgIcons.check : FgIcons.compare, color: context.fg.tone(_verifyTone(result)).fg),
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(s.t('expectedPlate'), style: context.tt.labelSmall),
                const SizedBox(height: 2),
                PlateBadge(p.s('expectedPlate')),
              ]),
            ),
          ]),
          const SizedBox(height: FgSpace.s2),
          if (p['confidence'] != null) KeyValueRow(s.t('confidence'), '${fmtNum(p.n('confidence'))} %', tabular: true),
          if (p.s('result') == 'ProviderUnavailable') FgNotice(tone: FgTone.neutral, message: s.t('recognitionUnavailable')),
        ],
        if (verification != null) ...[
          const SizedBox(height: FgSpace.s2),
          FgNotice(tone: _verifyTone(result), message: '${s.t('verifiedManually')}: ${s.status(result)}'),
        ],
        const SizedBox(height: FgSpace.s3),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPhoto,
              icon: const Icon(FgIcons.camera, size: 18),
              label: Text(s.t(p == null ? 'takeArrivalPhoto' : 'retakePhoto')),
            ),
          ),
          if (manual || p == null) ...[
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: manual
                  ? FilledButton.icon(onPressed: onVerify, icon: const Icon(FgIcons.verify, size: 18), label: Text(s.t('verifyManually')))
                  : OutlinedButton.icon(onPressed: onVerify, icon: const Icon(FgIcons.verify, size: 18), label: Text(s.t('verifyManually'))),
            ),
          ],
        ]),
      ],
    );
  }
}

/// Manual identity check at the gate (POST /workshop/gate/verify): plate read by eye, VIN, or an override reason.
class _ManualVerifySheet extends ConsumerStatefulWidget {
  const _ManualVerifySheet({required this.orderId, this.photo});
  final String orderId;
  final FgRow? photo;

  @override
  ConsumerState<_ManualVerifySheet> createState() => _ManualVerifySheetState();
}

class _ManualVerifySheetState extends ConsumerState<_ManualVerifySheet> {
  String _method = 'Plate';
  late final _plate = TextEditingController(text: widget.photo?.s('readPlate') ?? '');
  final _vin = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _plate.dispose();
    _vin.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = asRow(await ref.read(apiProvider).post('/workshop/gate/verify', body: {
        'serviceOrderId': widget.orderId,
        'method': _method,
        'readPlate': _method == 'Plate' ? _plate.text.trim() : '',
        'confidence': _method == 'Plate' ? 100 : 0,
        'readVin': _method == 'VIN' ? _vin.text.trim().toUpperCase() : '',
        'overrideReason': _method == 'Manual' ? _reason.text.trim() : '',
        'evidenceRef': widget.photo?.s('evidenceId') ?? '',
      }));
      FgHaptics.success();
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      FgHaptics.warning();
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final ready = switch (_method) {
      'Plate' => _plate.text.trim().isNotEmpty,
      'VIN' => _vin.text.trim().length >= 11,
      _ => _reason.text.trim().isNotEmpty,
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(FgSpace.gutter, 0, FgSpace.gutter, FgSpace.s4 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.t('verifyManually'), style: context.tt.titleLarge),
            Text(s.t('verifyManuallyHint'), style: context.tt.bodySmall),
            const SizedBox(height: FgSpace.s3),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'Plate', label: Text(s.t('plate'))),
                ButtonSegment(value: 'VIN', label: const Text('VIN')),
                ButtonSegment(value: 'Manual', label: Text(s.t('override'))),
              ],
              selected: {_method},
              onSelectionChanged: (v) {
                FgHaptics.tap();
                setState(() => _method = v.first);
              },
            ),
            const SizedBox(height: FgSpace.s3),
            if (_method == 'Plate')
              TextField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: s.t('plateOnVehicle'), prefixIcon: const Icon(FgIcons.vehicles, size: 20)),
              ),
            if (_method == 'VIN')
              TextField(
                controller: _vin,
                maxLength: 17,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'VIN'),
              ),
            if (_method == 'Manual')
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: s.t('overrideReason'), alignLabelWithHint: true),
              ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: FgSpace.s2), child: ErrorText(_error!, textAlign: TextAlign.start)),
            const SizedBox(height: FgSpace.s4),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy || !ready ? null : _submit,
              icon: _busy
                  ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.fg.onAction))
                  : const Icon(FgIcons.verify, size: 18),
              label: Text(s.t('verifyNow')),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({super.key, required this.error, required this.title, required this.message, required this.onOpen, required this.openLabel});
  final bool error;
  final String title;
  final String message;
  final VoidCallback? onOpen;
  final String openLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.fg.tone(error ? FgTone.bad : FgTone.good);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(FgSpace.s4),
        decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brLg, border: Border.all(color: c.fg, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(error ? FgIcons.bad : FgIcons.good, color: c.fg, size: 40),
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.tt.titleLarge?.copyWith(color: c.fg)),
                const SizedBox(height: 2),
                Text(message, style: context.tt.bodyMedium?.copyWith(color: c.fg)),
              ]),
            ),
          ]),
          if (onOpen != null) ...[
            const SizedBox(height: FgSpace.s3),
            OutlinedButton.icon(onPressed: onOpen, icon: const Icon(FgIcons.arrowForward, size: 18), label: Text(openLabel)),
          ],
        ]),
      ),
    );
  }
}
