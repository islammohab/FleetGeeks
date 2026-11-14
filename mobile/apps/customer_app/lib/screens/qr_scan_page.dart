import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
