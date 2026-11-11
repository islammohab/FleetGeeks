import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth.dart';
import '../fg_icons.dart';
import '../i18n.dart';
import '../theme.dart';
import 'skeleton.dart';

/// Bytes of an evidence file (GET /evidence/{id}); D365 decides who may see it.
final evidenceBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>(
  (ref, id) => ref.watch(apiProvider).getBytes('/evidence/${Uri.encodeComponent(id)}'),
);

/// Evidence row of a service order (FGEvidences) that can be shown as an image.
bool isImageEvidence(Map<String, dynamic> row) {
  final type = '${row['ContentType'] ?? ''}';
  final name = '${row['FileName'] ?? ''}'.toLowerCase();
  return type.startsWith('image/') || name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png');
}

/// An evidence image loaded with the user's token; skeleton while loading, icon on error.
class EvidenceImage extends ConsumerWidget {
  const EvidenceImage(this.evidenceId, {super.key, this.fit = BoxFit.cover});
  final String evidenceId;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref.watch(evidenceBytesProvider(evidenceId))) {
        AsyncData(:final value) => Image.memory(value, fit: fit, gaplessPlayback: true, errorBuilder: (context, error, stackTrace) => const _Broken()),
        AsyncError() => const _Broken(),
        _ => const Shimmer(child: SkeletonBox(height: double.infinity, radius: 0)),
      };
}

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.fg.surface2,
        child: Center(child: Icon(FgIcons.photo, color: context.fg.textMuted)),
      );
}

/// A photo for galleries and timelines: [builder] paints it at any fit (evidence, file, memory).
class FgPhoto {
  const FgPhoto({required this.builder, this.label, this.caption, this.category});
  final Widget Function(BoxFit fit) builder;
  final String? label;
  final String? caption;

  /// Evidence category (Before / After / Damage …) – used to pair before / after shots.
  final String? category;
}

/// Rounded thumbnail with an optional label chip.
class PhotoTile extends StatelessWidget {
  const PhotoTile({super.key, required this.photo, this.size = 96, this.onTap});
  final FgPhoto photo;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        image: true,
        label: [photo.label, photo.caption].whereType<String>().join(', '),
        child: ClipRRect(
          borderRadius: FgRadius.brMd,
          child: SizedBox.square(
            dimension: size,
            child: Stack(fit: StackFit.expand, children: [
              photo.builder(BoxFit.cover),
              if (photo.label != null)
                PositionedDirectional(
                  start: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: FgRadius.brSm),
                    child: Text(photo.label!, style: context.tt.labelSmall?.copyWith(color: Colors.white)),
                  ),
                ),
              Material(type: MaterialType.transparency, child: InkWell(onTap: onTap)),
            ]),
          ),
        ),
      );
}

/// Horizontal strip of thumbnails (timeline entries). Fixed height, no ListView (safe inside IntrinsicHeight).
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.photos, this.size = 72});
  final List<FgPhoto> photos;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: size,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < photos.length; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: FgSpace.s2),
                child: PhotoTile(photo: photos[i], size: size, onTap: () => PhotoViewer.open(context, photos, i)),
              ),
          ]),
        ),
      );
}

/// Grid gallery; tap opens the full-screen viewer. Shows a before / after slider when both kinds exist.
class PhotoGallery extends ConsumerWidget {
  const PhotoGallery({super.key, required this.photos});
  final List<FgPhoto> photos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final before = photos.where((p) => p.category == 'Before' || p.category == 'Reception').firstOrNull;
    final after = photos.where((p) => p.category == 'After').firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (before != null && after != null) ...[
        BeforeAfterSlider(before: before.builder(BoxFit.cover), after: after.builder(BoxFit.cover), beforeLabel: s.t('before'), afterLabel: s.t('after')),
        const SizedBox(height: FgSpace.s3),
      ],
      LayoutBuilder(builder: (context, constraints) {
        const gap = FgSpace.s2;
        final columns = constraints.maxWidth > 500 ? 5 : 3;
        final size = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (var i = 0; i < photos.length; i++) PhotoTile(photo: photos[i], size: size, onTap: () => PhotoViewer.open(context, photos, i)),
        ]);
      }),
    ]);
  }
}

/// Full-screen, zoomable photo viewer with swipe between photos.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.photos, this.initial = 0});
  final List<FgPhoto> photos;
  final int initial;

  static Future<void> open(BuildContext context, List<FgPhoto> photos, int index) =>
      Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => PhotoViewer(photos: photos, initial: index)));

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text([photo.label, photo.caption].whereType<String>().join(' · '), style: context.tt.titleSmall?.copyWith(color: Colors.white)),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: FgSpace.s4),
              child: Text('${_index + 1} / ${widget.photos.length}', style: context.tt.labelMedium?.copyWith(color: Colors.white70, fontFeatures: FgFonts.tabular)),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(minScale: 1, maxScale: 5, child: Center(child: widget.photos[i].builder(BoxFit.contain))),
      ),
    );
  }
}

/// Before / after comparison: drag the handle to reveal the "before" photo. Geometry is physical (left = before)
/// in both languages; the labels are translated.
class BeforeAfterSlider extends StatefulWidget {
  const BeforeAfterSlider({super.key, required this.before, required this.after, required this.beforeLabel, required this.afterLabel, this.height = 220});
  final Widget before;
  final Widget after;
  final String beforeLabel;
  final String afterLabel;
  final double height;

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _position = 0.5;

  void _move(double dx, double width) => setState(() => _position = (_position + dx / width).clamp(0.05, 0.95));

  @override
  Widget build(BuildContext context) {
    final label = context.tt.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600);
    Widget chip(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: FgRadius.brSm),
          child: Text(text, style: label),
        );
    return Semantics(
      slider: true,
      value: '${(_position * 100).round()}%',
      label: '${widget.beforeLabel} / ${widget.afterLabel}',
      onIncrease: () => setState(() => _position = (_position + 0.1).clamp(0.05, 0.95)),
      onDecrease: () => setState(() => _position = (_position - 0.1).clamp(0.05, 0.95)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ClipRRect(
          borderRadius: FgRadius.brLg,
          child: SizedBox(
            height: widget.height,
            child: LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => _move(d.delta.dx, width),
                onTapDown: (d) => setState(() => _position = (d.localPosition.dx / width).clamp(0.05, 0.95)),
                child: Stack(fit: StackFit.expand, children: [
                  widget.after,
                  ClipRect(
                    child: Align(alignment: Alignment.centerLeft, widthFactor: _position, child: SizedBox(width: width, child: widget.before)),
                  ),
                  Positioned(
                    left: width * _position - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: Colors.white),
                  ),
                  Positioned(
                    left: width * _position - 20,
                    top: widget.height / 2 - 20,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: FgShadows.md),
                      child: const Icon(FgIcons.compare, color: FgColors.n900, size: 22),
                    ),
                  ),
                  Positioned(left: 8, top: 8, child: chip(widget.beforeLabel)),
                  Positioned(right: 8, top: 8, child: chip(widget.afterLabel)),
                ]),
              );
            }),
          ),
        ),
      ),
    );
  }
}
