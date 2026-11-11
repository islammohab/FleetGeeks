import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fg_icons.dart';
import '../i18n.dart';
import '../theme.dart';

/// Strokes of a signature; turns them into a PNG with [toPngBytes] (PictureRecorder, no plugin).
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  List<List<Offset>> get strokes => List.unmodifiable(_strokes);
  bool get isEmpty => _strokes.every((s) => s.isEmpty);

  void begin(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void extend(Offset p) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(p);
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// PNG of the signature at the pad's size × [pixelRatio], dark ink on white (readable on documents).
  Future<Uint8List?> toPngBytes({double pixelRatio = 2, Color ink = const Color(0xFF162125), Color? background = Colors.white}) async {
    if (isEmpty || _size.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    if (background != null) canvas.drawRect(Offset.zero & _size, Paint()..color = background);
    paintSignature(canvas, _strokes, ink, 3);
    final picture = recorder.endRecording();
    final image = await picture.toImage((_size.width * pixelRatio).ceil(), (_size.height * pixelRatio).ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    return data?.buffer.asUint8List();
  }
}

/// Paints strokes smoothed with quadratic curves through the midpoints.
void paintSignature(Canvas canvas, List<List<Offset>> strokes, Color color, double width) {
  final line = Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  final dot = Paint()..color = color;
  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    if (stroke.length == 1) {
      canvas.drawCircle(stroke.first, width / 2, dot);
      continue;
    }
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (var i = 1; i < stroke.length - 1; i++) {
      final mid = Offset((stroke[i].dx + stroke[i + 1].dx) / 2, (stroke[i].dy + stroke[i + 1].dy) / 2);
      path.quadraticBezierTo(stroke[i].dx, stroke[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(stroke.last.dx, stroke.last.dy);
    canvas.drawPath(path, line);
  }
}

/// Signature area with a baseline, hint, undo and clear. Do not put it inside a vertical scroll view (the scroll
/// would take the strokes); in a bottom sheet use `enableDrag: false`.
class SignaturePad extends ConsumerWidget {
  const SignaturePad({super.key, required this.controller, this.height = 200});
  final SignatureController controller;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    final ink = context.isDark ? FgColors.n50 : FgColors.n900;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        label: s.t('signHere'),
        child: Container(
          height: height,
          decoration: BoxDecoration(color: fg.surface, borderRadius: FgRadius.brMd, border: Border.all(color: context.cs.outline)),
          child: LayoutBuilder(builder: (context, constraints) {
            controller._size = Size(constraints.maxWidth, height);
            Offset clamp(Offset p) => Offset(p.dx.clamp(0.0, constraints.maxWidth), p.dy.clamp(0.0, height));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => controller.begin(clamp(d.localPosition)),
              onPanUpdate: (d) => controller.extend(clamp(d.localPosition)),
              child: CustomPaint(
                painter: _PadPainter(controller, ink: ink, guide: fg.border, hint: s.t('signHere'), hintStyle: context.tt.bodySmall),
                size: Size(constraints.maxWidth, height),
              ),
            );
          }),
        ),
      ),
      const SizedBox(height: FgSpace.s2),
      ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(onPressed: controller.isEmpty ? null : controller.undo, icon: const Icon(FgIcons.undo, size: 18), label: Text(s.t('undo'))),
          const SizedBox(width: FgSpace.s2),
          TextButton.icon(onPressed: controller.isEmpty ? null : controller.clear, icon: const Icon(FgIcons.delete, size: 18), label: Text(s.t('clear'))),
        ]),
      ),
    ]);
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.controller, {required this.ink, required this.guide, required this.hint, this.hintStyle}) : super(repaint: controller);
  final SignatureController controller;
  final Color ink;
  final Color guide;
  final String hint;
  final TextStyle? hintStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * 0.72;
    canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), Paint()
      ..color = guide
      ..strokeWidth = 1.5);
    if (controller.isEmpty) {
      final tp = TextPainter(text: TextSpan(text: hint, style: hintStyle), textDirection: TextDirection.ltr, textAlign: TextAlign.center)
        ..layout(maxWidth: size.width - 48);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, y + 8));
      tp.dispose();
    }
    paintSignature(canvas, controller._strokes, ink, 3);
  }

  @override
  bool shouldRepaint(_PadPainter oldDelegate) => oldDelegate.ink != ink || oldDelegate.guide != guide || oldDelegate.hint != hint;
}
