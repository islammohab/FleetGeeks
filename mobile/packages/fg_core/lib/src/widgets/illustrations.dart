import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../status.dart';
import '../theme.dart';

/// Line illustrations for empty, error and success states (original art, drawn in code so they follow the theme).
enum FgArt { empty, error, offline, done, search, calendar, vehicle }

class FgIllustration extends StatelessWidget {
  const FgIllustration(this.art, {super.key, this.size = 140});
  final FgArt art;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _ArtPainter(art, line: fg.primary, accent: fg.action, wash: fg.primaryBg, paper: fg.surface)),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.art, {required this.line, required this.accent, required this.wash, required this.paper});
  final FgArt art;
  final Color line, accent, wash, paper;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 120;
    canvas.save();
    canvas.scale(u);
    canvas.drawCircle(const Offset(60, 62), 50, Paint()..color = wash);
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final hot = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = paper;

    switch (art) {
      case FgArt.empty:
        final tray = Path()
          ..moveTo(30, 70)
          ..lineTo(40, 45)
          ..lineTo(80, 45)
          ..lineTo(90, 70)
          ..lineTo(90, 88)
          ..quadraticBezierTo(90, 92, 86, 92)
          ..lineTo(34, 92)
          ..quadraticBezierTo(30, 92, 30, 88)
          ..close();
        canvas.drawPath(tray, fill);
        canvas.drawPath(tray, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(30, 70)
            ..lineTo(48, 70)
            ..lineTo(52, 78)
            ..lineTo(68, 78)
            ..lineTo(72, 70)
            ..lineTo(90, 70),
          stroke,
        );
        canvas.drawLine(const Offset(60, 24), const Offset(60, 34), hot);
        canvas.drawLine(const Offset(46, 29), const Offset(51, 37), hot);
        canvas.drawLine(const Offset(74, 29), const Offset(69, 37), hot);
      case FgArt.error:
        final cone = Path()
          ..moveTo(60, 26)
          ..lineTo(80, 86)
          ..lineTo(40, 86)
          ..close();
        canvas.drawPath(cone, fill);
        canvas.drawPath(cone, stroke);
        canvas.drawLine(const Offset(51, 54), const Offset(69, 54), hot..strokeWidth = 5);
        canvas.drawLine(const Offset(46, 70), const Offset(74, 70), hot);
        canvas.drawLine(const Offset(32, 92), const Offset(88, 92), stroke);
      case FgArt.offline:
        final cloud = Path()
          ..moveTo(42, 82)
          ..lineTo(84, 82)
          ..arcToPoint(const Offset(84, 54), radius: const Radius.circular(14), clockwise: false)
          ..arcToPoint(const Offset(46, 50), radius: const Radius.circular(20), clockwise: false)
          ..arcToPoint(const Offset(42, 82), radius: const Radius.circular(16), clockwise: false)
          ..close();
        canvas.drawPath(cloud, fill);
        canvas.drawPath(cloud, stroke);
        canvas.drawLine(const Offset(36, 36), const Offset(88, 96), hot);
      case FgArt.done:
        canvas.drawCircle(const Offset(60, 62), 26, fill);
        canvas.drawCircle(const Offset(60, 62), 26, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(48, 62)
            ..lineTo(56, 70)
            ..lineTo(73, 53),
          stroke..strokeWidth = 4,
        );
        _sparkle(canvas, const Offset(92, 32), hot);
        _sparkle(canvas, const Offset(28, 42), hot);
      case FgArt.search:
        canvas.drawCircle(const Offset(54, 56), 20, fill);
        canvas.drawCircle(const Offset(54, 56), 20, stroke);
        canvas.drawLine(const Offset(69, 71), const Offset(86, 88), stroke..strokeWidth = 5);
        canvas.drawLine(const Offset(46, 56), const Offset(62, 56), hot);
      case FgArt.calendar:
        final body = RRect.fromLTRBR(32, 36, 88, 88, const Radius.circular(8));
        canvas.drawRRect(body, fill);
        canvas.drawRRect(body, stroke);
        canvas.drawLine(const Offset(32, 50), const Offset(88, 50), stroke);
        canvas.drawLine(const Offset(46, 28), const Offset(46, 40), stroke);
        canvas.drawLine(const Offset(74, 28), const Offset(74, 40), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(49, 69)
            ..lineTo(56, 76)
            ..lineTo(71, 61),
          hot..strokeWidth = 4,
        );
      case FgArt.vehicle:
        canvas.save();
        canvas.translate(12, 30);
        canvas.scale(0.6);
        paintVehicle(canvas, FgVehicleKind.car, line: line, accent: accent, paper: paper);
        canvas.restore();
    }
    canvas.restore();
  }

  void _sparkle(Canvas canvas, Offset c, Paint p) {
    canvas.drawLine(c.translate(0, -6), c.translate(0, 6), p);
    canvas.drawLine(c.translate(-6, 0), c.translate(6, 0), p);
  }

  @override
  bool shouldRepaint(_ArtPainter oldDelegate) => oldDelegate.art != art || oldDelegate.line != line || oldDelegate.accent != accent || oldDelegate.wash != wash;
}

/// Placeholder illustration of a vehicle class (side view), used when a vehicle has no photo.
class VehicleArt extends StatelessWidget {
  const VehicleArt({super.key, required this.kind, this.width = 120, this.background = true});
  final FgVehicleKind kind;
  final double width;
  final bool background;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: width * 0.62,
        decoration: background ? BoxDecoration(color: fg.primaryBg, borderRadius: FgRadius.brMd) : null,
        padding: EdgeInsets.all(width * 0.06),
        child: CustomPaint(painter: _VehiclePainter(kind, line: fg.primary, accent: fg.action, paper: fg.surface)),
      ),
    );
  }
}

class _VehiclePainter extends CustomPainter {
  _VehiclePainter(this.kind, {required this.line, required this.accent, required this.paper});
  final FgVehicleKind kind;
  final Color line, accent, paper;

  @override
  void paint(Canvas canvas, Size size) {
    // Art box is 160 × 92 units.
    final scale = math.min(size.width / 160, size.height / 92);
    canvas.save();
    canvas.translate((size.width - 160 * scale) / 2, (size.height - 92 * scale) / 2);
    canvas.scale(scale);
    paintVehicle(canvas, kind, line: line, accent: accent, paper: paper);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VehiclePainter oldDelegate) => oldDelegate.kind != kind || oldDelegate.line != line || oldDelegate.accent != accent;
}

/// Draws a vehicle of [kind] in a 160 × 92 unit box (side view, facing the end of the line).
void paintVehicle(Canvas canvas, FgVehicleKind kind, {required Color line, required Color accent, required Color paper}) {
  final stroke = Paint()
    ..color = line
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final body = Paint()..color = paper;
  final glass = Paint()..color = line.withValues(alpha: 0.18);
  final hub = Paint()..color = accent;
  final ground = Paint()
    ..color = line.withValues(alpha: 0.35)
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  void shape(Path p) {
    canvas.drawPath(p, body);
    canvas.drawPath(p, stroke);
  }

  void window(Path p) {
    canvas.drawPath(p, glass);
    canvas.drawPath(p, stroke);
  }

  void wheel(double x, double y, double r) {
    canvas.drawCircle(Offset(x, y), r, body);
    canvas.drawCircle(Offset(x, y), r, stroke);
    canvas.drawCircle(Offset(x, y), r * 0.34, hub);
  }

  canvas.drawLine(const Offset(4, 86), const Offset(156, 86), ground);
  switch (kind) {
    case FgVehicleKind.car:
    case FgVehicleKind.suv:
      final suv = kind == FgVehicleKind.suv;
      final roof = suv ? 22.0 : 30.0;
      final belt = suv ? 44.0 : 48.0;
      shape(Path()
        ..moveTo(12, 72)
        ..lineTo(12, belt + 8)
        ..quadraticBezierTo(12, belt + 1, 20, belt)
        ..lineTo(44, belt - 2)
        ..lineTo(60, roof + 2)
        ..quadraticBezierTo(64, roof, 70, roof)
        ..lineTo(106, roof)
        ..quadraticBezierTo(112, roof, 116, roof + 4)
        ..lineTo(130, belt - 2)
        ..lineTo(144, belt)
        ..quadraticBezierTo(150, belt + 2, 150, belt + 9)
        ..lineTo(150, 72)
        ..close());
      window(Path()
        ..moveTo(64, belt - 3)
        ..lineTo(73, roof + 6)
        ..lineTo(104, roof + 6)
        ..lineTo(114, belt - 3)
        ..close());
      canvas.drawLine(Offset(89, roof + 6), Offset(89, belt - 3), stroke);
      wheel(44, 72, 13);
      wheel(122, 72, 13);
    case FgVehicleKind.van:
      shape(Path()
        ..moveTo(12, 72)
        ..lineTo(12, 30)
        ..quadraticBezierTo(12, 20, 24, 20)
        ..lineTo(108, 20)
        ..quadraticBezierTo(116, 20, 122, 27)
        ..lineTo(142, 46)
        ..quadraticBezierTo(150, 48, 150, 58)
        ..lineTo(150, 72)
        ..close());
      window(Path()
        ..moveTo(112, 28)
        ..lineTo(132, 46)
        ..lineTo(112, 46)
        ..close());
      window(Path()..addRRect(RRect.fromLTRBR(24, 28, 64, 46, const Radius.circular(4))));
      window(Path()..addRRect(RRect.fromLTRBR(70, 28, 104, 46, const Radius.circular(4))));
      wheel(42, 72, 13);
      wheel(124, 72, 13);
    case FgVehicleKind.pickup:
      shape(Path()
        ..moveTo(12, 72)
        ..lineTo(12, 48)
        ..lineTo(70, 48)
        ..lineTo(70, 30)
        ..quadraticBezierTo(70, 24, 77, 24)
        ..lineTo(100, 24)
        ..quadraticBezierTo(106, 24, 110, 30)
        ..lineTo(122, 46)
        ..lineTo(144, 48)
        ..quadraticBezierTo(150, 50, 150, 58)
        ..lineTo(150, 72)
        ..close());
      window(Path()
        ..moveTo(78, 31)
        ..lineTo(100, 31)
        ..lineTo(110, 46)
        ..lineTo(78, 46)
        ..close());
      wheel(40, 72, 13);
      wheel(124, 72, 13);
    case FgVehicleKind.truck:
      shape(Path()..addRRect(RRect.fromLTRBR(8, 14, 100, 70, const Radius.circular(5))));
      shape(Path()
        ..moveTo(104, 72)
        ..lineTo(104, 32)
        ..lineTo(126, 32)
        ..quadraticBezierTo(132, 32, 136, 38)
        ..lineTo(150, 54)
        ..lineTo(150, 72)
        ..close());
      window(Path()
        ..moveTo(110, 38)
        ..lineTo(126, 38)
        ..lineTo(136, 50)
        ..lineTo(110, 50)
        ..close());
      wheel(32, 74, 11);
      wheel(60, 74, 11);
      wheel(130, 74, 11);
    case FgVehicleKind.bus:
      shape(Path()..addRRect(RRect.fromLTRBR(8, 18, 152, 72, const Radius.circular(10))));
      for (var x = 18.0; x < 130; x += 24) {
        window(Path()..addRRect(RRect.fromLTRBR(x, 26, x + 18, 44, const Radius.circular(3))));
      }
      window(Path()..addRRect(RRect.fromLTRBR(134, 26, 146, 58, const Radius.circular(3))));
      wheel(38, 72, 12);
      wheel(122, 72, 12);
    case FgVehicleKind.bike:
      canvas.drawPath(
        Path()
          ..moveTo(38, 66)
          ..lineTo(64, 38)
          ..lineTo(98, 38)
          ..lineTo(122, 66)
          ..moveTo(64, 38)
          ..lineTo(80, 66)
          ..lineTo(98, 38)
          ..moveTo(92, 28)
          ..lineTo(108, 28),
        stroke,
      );
      wheel(38, 66, 18);
      wheel(122, 66, 18);
    case FgVehicleKind.equipment:
      shape(Path()..addRRect(RRect.fromLTRBR(36, 38, 108, 70, const Radius.circular(5))));
      canvas.drawPath(
        Path()
          ..moveTo(48, 38)
          ..lineTo(48, 16)
          ..lineTo(90, 16)
          ..lineTo(90, 38)
          ..moveTo(120, 10)
          ..lineTo(120, 76)
          ..moveTo(120, 76)
          ..lineTo(152, 76),
        stroke,
      );
      wheel(56, 74, 10);
      wheel(98, 74, 10);
  }
}

/// The Fleet Geeks mark (wheel with gear teeth, the road leaving it, orange hub and lane): same geometry as
/// `mobile/assets/brand/fleetgeeks-mark.svg` (512-unit box).
class FgBrandMark extends StatelessWidget {
  const FgBrandMark({super.key, this.size = 40, this.tile = true, this.markColor = Colors.white, this.accent = FgColors.orange400, this.tileColor = FgColors.teal600});
  final double size;

  /// Draw the rounded teal tile behind the mark (app icon look).
  final bool tile;
  final Color markColor, accent, tileColor;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _MarkPainter(tile: tile, mark: markColor, accent: accent, tileColor: tileColor)),
        ),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.tile, required this.mark, required this.accent, required this.tileColor});
  final bool tile;
  final Color mark, accent, tileColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 512);
    if (tile) {
      canvas.drawRRect(RRect.fromLTRBR(0, 0, 512, 512, const Radius.circular(116)), Paint()..color = tileColor);
    }
    const c = Offset(256, 232);
    final white = Paint()..color = mark;
    final ring = Paint()
      ..color = mark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 40;
    double rad(double deg) => deg * math.pi / 180;
    canvas.drawArc(Rect.fromCircle(center: c, radius: 124), rad(115), rad(310), false, ring);
    for (final r in const <double>[0, 45, 90, 270, 315]) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(rad(r));
      canvas.drawRRect(RRect.fromLTRBR(-20, -172, 20, -140, const Radius.circular(8)), white);
      canvas.restore();
    }
    final road = Paint()
      ..color = mark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(211, 324), const Offset(150, 452), road);
    canvas.drawLine(const Offset(301, 324), const Offset(362, 452), road);
    final lane = Paint()..color = accent;
    canvas.drawRRect(RRect.fromLTRBR(250, 318, 262, 346, const Radius.circular(6)), lane);
    canvas.drawRRect(RRect.fromLTRBR(248, 372, 264, 410, const Radius.circular(8)), lane);
    canvas.drawRRect(RRect.fromLTRBR(246, 434, 266, 480, const Radius.circular(10)), lane);
    canvas.drawCircle(c, 46, lane);
    canvas.drawCircle(c, 16, Paint()..color = tileColor);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.tile != tile || oldDelegate.mark != mark || oldDelegate.accent != accent || oldDelegate.tileColor != tileColor;
}
