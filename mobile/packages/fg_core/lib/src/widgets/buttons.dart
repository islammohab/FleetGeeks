import 'package:flutter/material.dart';

import '../fg_icons.dart';
import '../status.dart';
import '../theme.dart';

/// Bottom action bar of a screen (wizard "Continue", "Send now", estimate decision): surface, top border, safe area.
class FgActionBar extends StatelessWidget {
  const FgActionBar({super.key, required this.children, this.top});
  final List<Widget> children;

  /// Optional widget above the buttons (offline banner, total).
  final Widget? top;

  @override
  Widget build(BuildContext context) => Material(
        color: context.fg.surface,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: context.fg.border))),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (top != null) top!,
              Padding(
                padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s3, FgSpace.gutter, FgSpace.s3),
                child: Row(children: children),
              ),
            ]),
          ),
        ),
      );
}

/// Visual weight of a big button.
enum FgButtonKind { action, primary, neutral, danger }

/// Large touch target (72 dp by default) for gloves and gate work: start / pause / finish, scan, admit, release.
class FgBigButton extends StatelessWidget {
  const FgBigButton({super.key, required this.icon, required this.label, required this.onPressed, this.kind = FgButtonKind.action, this.height = 72, this.caption});
  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback? onPressed;
  final FgButtonKind kind;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    final (bg, fore, border) = switch (kind) {
      FgButtonKind.action => (fg.action, fg.onAction, Colors.transparent),
      FgButtonKind.primary => (fg.primary, fg.onPrimary, Colors.transparent),
      FgButtonKind.danger => (fg.dangerBg, fg.danger, fg.danger),
      FgButtonKind.neutral => (fg.surface, context.isDark ? fg.primary : fg.primaryStrong, context.cs.outline),
    };
    final disabled = onPressed == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: caption == null ? label : '$label, $caption',
      excludeSemantics: true,
      child: Material(
        color: disabled ? fg.surface2 : bg,
        shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: disabled ? fg.border : border, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            padding: const EdgeInsets.symmetric(horizontal: FgSpace.s4, vertical: FgSpace.s3),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 28, color: disabled ? fg.textMuted : fore),
              const SizedBox(width: FgSpace.s3),
              Flexible(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: context.tt.titleMedium?.copyWith(color: disabled ? fg.textMuted : fore, fontWeight: FontWeight.w700)),
                  if (caption != null) Text(caption!, style: context.tt.bodySmall?.copyWith(color: (disabled ? fg.textMuted : fore).withValues(alpha: 0.85))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Square quick action (icon + label), used in dashboard rows.
class FgQuickAction extends StatelessWidget {
  const FgQuickAction({super.key, required this.icon, required this.label, required this.onTap, this.tone = FgTone.progress, this.highlight = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final FgTone tone;

  /// Orange call to action (one per row at most).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    final c = highlight ? (fg: fg.onAction, bg: fg.action) : fg.tone(tone);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: fg.surface,
        shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: fg.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: FgSpace.s3, horizontal: FgSpace.s2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brMd),
                child: Icon(icon, color: c.fg, size: 22),
              ),
              const SizedBox(height: FgSpace.s2),
              Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: context.tt.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Menu row of the "More" screens: icon tile, title, optional subtitle and trailing (badge / value), chevron.
class FgMenuTile extends StatelessWidget {
  const FgMenuTile({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.tone = FgTone.progress, this.destructive = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final FgTone tone;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.fg.tone(destructive ? FgTone.bad : tone);
    return ListTile(
      onTap: onTap,
      minTileHeight: 60,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brMd),
        child: Icon(icon, color: c.fg, size: 20),
      ),
      title: Text(title, style: context.tt.titleSmall?.copyWith(color: destructive ? context.fg.danger : null)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (trailing != null) trailing!,
        if (onTap != null && !destructive) ...[const SizedBox(width: FgSpace.s1), Icon(FgIcons.chevronForward, size: 18, color: context.fg.textMuted)],
      ]),
    );
  }
}
