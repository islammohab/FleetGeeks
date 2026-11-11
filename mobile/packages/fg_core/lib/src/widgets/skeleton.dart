import 'package:flutter/material.dart';

import '../theme.dart';

/// Shimmer over skeleton shapes (no extra package): a soft highlight sweeps across its child. Static when the
/// platform asks for reduced motion.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    final base = fg.surface2;
    final highlight = Color.lerp(fg.surface2, fg.surface, 0.7)!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [base, highlight, base],
          stops: const [0.25, 0.5, 0.75],
          transform: _Slide(_controller.value),
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * (2 * t - 1), 0, 0);
}

/// A grey placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = FgRadius.sm});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: context.fg.surface2, borderRadius: BorderRadius.circular(radius)),
      );
}

/// Placeholder of a list card (icon, two lines, pill).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2});
  final int lines;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(FgSpace.s4),
        // No fill: inside a Shimmer every opaque pixel takes the shimmer colour, so only the blocks and the outline paint.
        decoration: BoxDecoration(borderRadius: FgRadius.brLg, border: Border.all(color: context.fg.border, width: 1.5)),
        child: Row(children: [
          const SkeletonBox(width: 48, height: 48, radius: FgRadius.md),
          const SizedBox(width: FgSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SkeletonBox(width: 140, height: 16),
              for (var i = 1; i < lines; i++) ...[
                const SizedBox(height: FgSpace.s2),
                SkeletonBox(width: i.isOdd ? 200 : 110, height: 12),
              ],
            ]),
          ),
          const SizedBox(width: FgSpace.s3),
          const SkeletonBox(width: 64, height: 22, radius: FgRadius.pill),
        ]),
      );
}

/// Loading state of a list screen: shimmering cards. Scrollable so pull-to-refresh keeps working while loading.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.header = false});
  final int count;

  /// Add a hero-sized block first (dashboard, detail screens).
  final bool header;

  @override
  Widget build(BuildContext context) => Shimmer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(FgSpace.gutter),
          children: [
            if (header) ...[
              const SkeletonBox(height: 140, radius: FgRadius.lg),
              const SizedBox(height: FgSpace.s4),
            ],
            for (var i = 0; i < count; i++) ...[
              const SkeletonCard(),
              const SizedBox(height: FgSpace.s3),
            ],
          ],
        ),
      );
}
