import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fg_icons.dart';
import '../format.dart';
import '../i18n.dart';
import '../status.dart';
import '../theme.dart';
import 'photos.dart';

/// State of a timeline entry: done (filled dot), current (ring + label), upcoming (muted).
enum FgStep { done, current, upcoming }

class FgTimelineEntry {
  const FgTimelineEntry({
    required this.title,
    this.subtitle,
    this.time,
    this.icon,
    this.tone = FgTone.progress,
    this.step = FgStep.done,
    this.photos = const [],
    this.onTap,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final DateTime? time;
  final IconData? icon;
  final FgTone tone;
  final FgStep step;
  final List<FgPhoto> photos;
  final VoidCallback? onTap;
  final Widget? trailing;
}

/// Vertical timeline with timestamps and photo strips. Direction-aware (the rail sits on the start side).
class FgTimeline extends ConsumerWidget {
  const FgTimeline({super.key, required this.entries, this.showDate = true});
  final List<FgTimelineEntry> entries;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < entries.length; i++)
        Builder(builder: (context) {
          final e = entries[i];
          final last = i == entries.length - 1;
          final c = fg.tone(e.step == FgStep.upcoming ? FgTone.neutral : e.tone);
          final lineColor = e.step == FgStep.done ? fg.primary.withValues(alpha: 0.5) : fg.border;
          final dot = switch (e.step) {
            FgStep.done => Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: c.bg, shape: BoxShape.circle),
                child: Icon(e.icon ?? FgIcons.check, size: 15, color: c.fg),
              ),
            FgStep.current => Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: fg.surface, shape: BoxShape.circle, border: Border.all(color: fg.action, width: 3)),
                child: Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(color: fg.action, shape: BoxShape.circle))),
              ),
            FgStep.upcoming => Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                child: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: fg.border, width: 2))),
              ),
          };
          final body = Padding(
            padding: EdgeInsetsDirectional.only(start: FgSpace.s3, bottom: last ? 0 : FgSpace.s4, top: 3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(
                    e.title,
                    style: context.tt.titleSmall?.copyWith(
                      color: e.step == FgStep.upcoming ? fg.textMuted : fg.text,
                      fontWeight: e.step == FgStep.current ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                if (e.time != null)
                  Text(
                    showDate ? fmtDate(e.time, s.lang) : fmtTime(e.time, s.lang),
                    style: context.tt.labelSmall?.copyWith(fontFeatures: FgFonts.tabular),
                  ),
                if (e.trailing != null) ...[const SizedBox(width: FgSpace.s2), e.trailing!],
              ]),
              if (e.subtitle != null && e.subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(e.subtitle!, style: context.tt.bodySmall),
              ],
              if (e.photos.isNotEmpty) ...[
                const SizedBox(height: FgSpace.s2),
                PhotoStrip(photos: e.photos),
              ],
            ]),
          );
          return Semantics(
            container: true,
            label: [
              e.title,
              if (e.step == FgStep.current) s.t('currentStep'),
              if (e.time != null) fmtDate(e.time, s.lang),
            ].join(', '),
            child: InkWell(
              onTap: e.onTap,
              borderRadius: FgRadius.brMd,
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    width: 28,
                    child: Column(children: [
                      dot,
                      if (!last) Expanded(child: Center(child: Container(width: 2, color: lineColor))),
                    ]),
                  ),
                  Expanded(child: body),
                ]),
              ),
            ),
          );
        }),
    ]);
  }
}

/// The ten-stage service order tracker (Requested → … → Released) with known timestamps and "what happens next".
class OrderProgress extends ConsumerWidget {
  const OrderProgress({super.key, required this.status, this.times = const {}, this.compact = false});

  /// Service order status symbol (D365).
  final String status;

  /// Known timestamps per stage key of [orderStages] (for example Arrived → ArrivedDateTime).
  final Map<String, DateTime?> times;

  /// Only the bar and the current stage (list cards).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    final index = orderStageIndex(status);
    final cancelled = status == 'Cancelled';
    final bar = Semantics(
      label: index < 0 ? s.status(status) : s.t('stepOf', [index + 1, orderStages.length]),
      child: Row(children: [
        for (var i = 0; i < orderStages.length; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: FgMotion.base,
              height: 6,
              decoration: BoxDecoration(
                color: cancelled ? fg.border : (i < index ? fg.primary : (i == index ? fg.action : fg.surface2)),
                borderRadius: FgRadius.brPill,
              ),
            ),
          ),
          if (i < orderStages.length - 1) const SizedBox(width: 3),
        ],
      ]),
    );
    if (compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        bar,
        const SizedBox(height: 6),
        Text(
          index < 0 ? s.status(status) : s.t('stage${orderStages[index]}'),
          style: context.tt.labelMedium?.copyWith(color: cancelled ? fg.textMuted : fg.primary, fontWeight: FontWeight.w600),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      bar,
      const SizedBox(height: FgSpace.s4),
      if (cancelled)
        Text(s.status(status), style: context.tt.titleSmall?.copyWith(color: fg.textMuted))
      else
        FgTimeline(entries: [
          for (var i = 0; i < orderStages.length; i++)
            FgTimelineEntry(
              title: s.t('stage${orderStages[i]}'),
              subtitle: i == index ? s.t('next${orderStages[i]}') : null,
              time: times[orderStages[i]],
              step: i < index ? FgStep.done : (i == index ? FgStep.current : FgStep.upcoming),
              tone: FgTone.progress,
            ),
        ]),
    ]);
  }
}
