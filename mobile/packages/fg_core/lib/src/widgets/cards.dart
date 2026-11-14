import 'package:flutter/material.dart';

import '../fg_icons.dart';
import '../status.dart';
import '../theme.dart';
import 'illustrations.dart';
import 'status_pill.dart';

/// Rounded tile with an icon in tone colours (leading of list cards, quick actions).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.tone = FgTone.progress, this.size = 44});
  final IconData icon;
  final FgTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.fg.tone(tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brMd),
      child: Icon(icon, color: c.fg, size: size * 0.5),
    );
  }
}

/// A titled card section (replaces the old `Section`).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children, this.icon, this.trailing, this.padding, this.subtitle});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding ?? const EdgeInsets.all(FgSpace.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 20, color: context.fg.primary), const SizedBox(width: FgSpace.s2)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: Text(title, style: context.tt.titleMedium)),
                  if (subtitle != null) Text(subtitle!, style: context.tt.bodySmall),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: FgSpace.s3),
            ...children,
          ]),
        ),
      );
}

/// Key figure with an icon (dashboard, board header). Numbers use tabular figures.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.tone = FgTone.progress, this.caption, this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final FgTone tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fg.tone(tone);
    return Semantics(
      button: onTap != null,
      label: '$label: $value${caption == null ? '' : ', $caption'}',
      excludeSemantics: true,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(FgSpace.s4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(FgSpace.s2),
                  decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brSm),
                  child: Icon(icon, size: 18, color: c.fg),
                ),
                const Spacer(),
                if (onTap != null) Icon(FgIcons.chevronForward, size: 18, color: context.fg.textMuted),
              ]),
              const SizedBox(height: FgSpace.s3),
              Text(value, style: context.tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: FgFonts.tabular)),
              const SizedBox(height: 2),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.fg.textMuted)),
              if (caption != null) ...[
                const SizedBox(height: FgSpace.s1),
                Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelSmall?.copyWith(color: c.fg)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Grid of stat cards, two per row on phones, four on wide screens.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 4 : 2;
        const gap = FgSpace.s3;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in children) SizedBox(width: width, child: c)]);
      });
}

/// Label / value line for detail cards. Values can be tabular (numbers, codes).
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.icon, this.tabular = false, this.valueWidget});
  final String label;
  final String value;
  final IconData? icon;
  final bool tabular;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, size: 18, color: context.fg.textMuted), const SizedBox(width: FgSpace.s2)],
          Expanded(flex: 2, child: Text(label, style: context.tt.bodyMedium?.copyWith(color: context.fg.textMuted))),
          const SizedBox(width: FgSpace.s3),
          Expanded(
            flex: 3,
            child: valueWidget ??
                Text(
                  value.isEmpty ? '—' : value,
                  textAlign: TextAlign.end,
                  style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500, fontFeatures: tabular ? FgFonts.tabular : null),
                ),
          ),
        ]),
      );
}

/// Number plate look: bordered, tabular, always left-to-right (plates are not translated).
class PlateBadge extends StatelessWidget {
  const PlateBadge(this.plate, {super.key, this.large = false});
  final String plate;
  final bool large;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: large ? FgSpace.s3 : FgSpace.s2, vertical: large ? 6 : 3),
          decoration: BoxDecoration(
            color: context.isDark ? context.fg.surface2 : Colors.white,
            borderRadius: FgRadius.brSm,
            border: Border.all(color: context.fg.text.withValues(alpha: 0.7), width: 1.5),
          ),
          child: Text(
            plate,
            style: (large ? context.tt.titleMedium : context.tt.labelLarge)?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1, fontFeatures: FgFonts.tabular),
          ),
        ),
      );
}

/// Generic tappable list card: leading icon tile, title, subtitle lines, trailing widget (status pill), chevron.
class FgListCard extends StatelessWidget {
  const FgListCard({super.key, required this.title, this.subtitle, this.meta, this.leading, this.trailing, this.onTap, this.footer});
  final String title;
  final String? subtitle;

  /// Third, muted line (dates, references).
  final String? meta;
  final Widget? leading;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(FgSpace.s4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (leading != null) ...[leading!, const SizedBox(width: FgSpace.s3)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: context.tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: context.tt.bodyMedium?.copyWith(color: context.fg.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    if (meta != null && meta!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meta!, style: context.tt.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ]),
                ),
                if (trailing != null) ...[const SizedBox(width: FgSpace.s2), trailing!],
                if (onTap != null) ...[
                  const SizedBox(width: FgSpace.s1),
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(FgIcons.chevronForward, size: 18, color: context.fg.textMuted)),
                ],
              ]),
              if (footer != null) ...[const SizedBox(height: FgSpace.s3), footer!],
            ]),
          ),
        ),
      );
}

/// Vehicle card: class illustration (no photo yet), plate, make / model, status, odometer and next due.
class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.plate,
    required this.title,
    this.vehicleClass = '',
    this.status = '',
    this.odometer,
    this.nextDue,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final String plate;
  final String title;
  final String vehicleClass;
  final String status;
  final String? odometer;
  final String? nextDue;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(FgSpace.s3),
            child: Row(children: [
              VehicleArt(kind: vehicleKindOf(vehicleClass), width: 96),
              const SizedBox(width: FgSpace.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: PlateBadge(plate)),
                    const Spacer(),
                    StatusPill(status, dense: true),
                  ]),
                  const SizedBox(height: 6),
                  Text(title, style: context.tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: context.tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (odometer != null || nextDue != null) ...[
                    const SizedBox(height: FgSpace.s1),
                    Wrap(spacing: FgSpace.s3, runSpacing: 2, children: [
                      if (odometer != null) _Meta(icon: FgIcons.odometer, text: odometer!),
                      if (nextDue != null) _Meta(icon: FgIcons.promise, text: nextDue!),
                    ]),
                  ],
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: FgSpace.s2), trailing!],
            ]),
          ),
        ),
      );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: context.fg.textMuted),
        const SizedBox(width: 4),
        Text(text, style: context.tt.labelMedium?.copyWith(color: context.fg.textMuted, fontFeatures: FgFonts.tabular)),
      ]);
}
