import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth.dart';
import '../config.dart';
import '../fg_icons.dart';
import '../haptics.dart';
import '../i18n.dart';
import '../models.dart';
import '../outbox.dart';
import '../status.dart';
import '../theme.dart';
import 'illustrations.dart';
import 'offline.dart';
import 'states.dart';

/// Shows the result of a command: sent, queued for later, or refused (snack bar + haptics).
/// Returns true when the command was sent or queued.
Future<bool> runCommand(BuildContext context, WidgetRef ref, Future<SubmitResult> Function() command, {String? done}) async {
  final s = ref.read(stringsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final danger = context.fg.danger;
  final onDanger = context.isDark ? FgColors.n950 : FgColors.n0;
  final onSnack = context.cs.onInverseSurface;
  try {
    final r = await command();
    FgHaptics.success();
    messenger.showSnackBar(SnackBar(
      content: Row(children: [
        Icon(r.queued ? FgIcons.waiting : FgIcons.good, color: onSnack, size: 18),
        const SizedBox(width: FgSpace.s2),
        Expanded(child: Text(r.queued ? s.t('queued') : (done ?? s.t('saved')))),
      ]),
    ));
    return true;
  } catch (e) {
    FgHaptics.warning();
    messenger.showSnackBar(SnackBar(backgroundColor: danger, content: Text('$e', style: TextStyle(color: onDanger))));
    return false;
  }
}

/// Snack bar for an error of a live (non-outbox) call.
void showError(BuildContext context, Object error) {
  FgHaptics.warning();
  final fg = context.fg;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(backgroundColor: fg.danger, content: Text('$error', style: TextStyle(color: context.isDark ? FgColors.n950 : FgColors.n0))),
  );
}

/// Snack bar for a success of a live call.
void showDone(BuildContext context, String message) {
  FgHaptics.success();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// App bar actions: outbox badge, language, sign-out (used on screens without the "More" tab).
List<Widget> commonActions(BuildContext context, WidgetRef ref, {VoidCallback? openOutbox}) {
  final s = ref.watch(stringsProvider);
  return [
    if (openOutbox != null) OutboxButton(onPressed: openOutbox),
    IconButton(tooltip: s.t('language'), onPressed: () => ref.read(localeProvider.notifier).toggle(), icon: const Icon(FgIcons.language)),
    IconButton(tooltip: s.t('signOut'), onPressed: () => ref.read(authProvider.notifier).signOut(), icon: const Icon(FgIcons.signOut)),
  ];
}

/// Pull-to-refresh with the brand colour and a light haptic.
class FgRefresh extends StatelessWidget {
  const FgRefresh({super.key, required this.onRefresh, required this.child});
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: context.fg.primary,
        backgroundColor: context.fg.surface,
        onRefresh: () async {
          FgHaptics.light();
          await onRefresh();
        },
        child: child,
      );
}

/// Teal gradient header (dashboard greeting, vehicle hero, sign-in).
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.child, this.padding = const EdgeInsets.all(FgSpace.s5), this.radius = FgRadius.xl});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd, colors: [fg.heroStart, fg.heroEnd]),
      ),
      child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: IconTheme.merge(data: const IconThemeData(color: Colors.white), child: child)),
    );
  }
}

/// Round avatar with initials.
class FgAvatar extends StatelessWidget {
  const FgAvatar(this.name, {super.key, this.size = 44, this.onHero = false});
  final String name;
  final double size;

  /// White on teal (inside a [HeroHeader]).
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: onHero ? Colors.white.withValues(alpha: 0.16) : fg.primaryBg,
          border: onHero ? Border.all(color: Colors.white.withValues(alpha: 0.4)) : null,
        ),
        child: Text(
          initialsOf(name),
          style: context.tt.titleSmall?.copyWith(color: onHero ? Colors.white : (context.isDark ? fg.primary : fg.primaryStrong), fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Section heading inside a list, with an optional end action ("See all").
class FgSectionTitle extends StatelessWidget {
  const FgSectionTitle(this.title, {super.key, this.actionLabel, this.onAction, this.count});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(top: FgSpace.s5, bottom: FgSpace.s2),
        child: Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(count == null ? title : '$title ($count)', style: context.tt.titleMedium),
            ),
          ),
          if (actionLabel != null && onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ]),
      );
}

/// Bottom sheet that lets the user pick one D365 lookup row ({id, name, nameAr}); returns its id.
Future<String?> pickLookup(BuildContext context, {required String title, required List<FgRow> rows, required Strings s, bool showId = true}) {
  FgHaptics.light();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: FgSpace.s4), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(FgSpace.gutter, 0, FgSpace.gutter, FgSpace.s2),
            child: Text(title, style: context.tt.titleLarge),
          ),
          if (rows.isEmpty) EmptyState(compact: true, title: s.t('noData')),
          for (final r in rows)
            ListTile(
              title: Text(s.lang == 'ar' && r.s('nameAr').isNotEmpty ? r.s('nameAr') : r.s('name')),
              subtitle: showId ? Text(r.s('id')) : null,
              trailing: const Icon(FgIcons.chevronForward, size: 18),
              onTap: () => Navigator.pop(context, r.s('id')),
            ),
        ]),
      ),
    ),
  );
}

/// Development sign-in with the demo portal users (labelled; the API refuses it outside Development).
class DevSignInScreen extends ConsumerStatefulWidget {
  const DevSignInScreen({super.key, required this.title, required this.users, this.subtitle});
  final String title;
  final String? subtitle;
  final Map<String, String> users;

  @override
  ConsumerState<DevSignInScreen> createState() => _DevSignInScreenState();
}

class _DevSignInScreenState extends ConsumerState<DevSignInScreen> {
  late String _user = widget.users.keys.first;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final auth = ref.watch(authProvider);
    final fg = context.fg;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => ref.read(localeProvider.notifier).toggle(),
              icon: const Icon(FgIcons.language, size: 18),
              label: Text(s.t('language')),
            ),
          ),
          HeroHeader(
            padding: const EdgeInsets.all(FgSpace.s6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FgBrandMark(size: 56),
              const SizedBox(height: FgSpace.s4),
              Text(widget.title, style: context.tt.headlineMedium?.copyWith(color: Colors.white)),
              const SizedBox(height: FgSpace.s1),
              Text(widget.subtitle ?? s.t('signInTagline'), style: context.tt.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
            ]),
          ),
          const SizedBox(height: FgSpace.s4),
          FgNotice(tone: FgTone.attention, title: '${s.t('devSignIn')} · ${FgConfig.environment}', message: s.t('devSignInNote')),
          const SizedBox(height: FgSpace.s4),
          Text(s.t('portalUser'), style: context.tt.titleSmall),
          const SizedBox(height: FgSpace.s2),
          for (final entry in widget.users.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: FgSpace.s2),
              child: Semantics(
                selected: entry.key == _user,
                button: true,
                child: Material(
                  color: entry.key == _user ? fg.primaryBg : fg.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: FgRadius.brLg,
                    side: BorderSide(color: entry.key == _user ? fg.primary : fg.border, width: entry.key == _user ? 2 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      FgHaptics.tap();
                      setState(() => _user = entry.key);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(FgSpace.s3),
                      child: Row(children: [
                        FgAvatar(entry.value, size: 40),
                        const SizedBox(width: FgSpace.s3),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(entry.value, style: context.tt.titleSmall),
                            Text(entry.key, style: context.tt.bodySmall),
                          ]),
                        ),
                        if (entry.key == _user) Icon(FgIcons.good, color: fg.primary),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          if (auth.hasError) Padding(padding: const EdgeInsets.all(FgSpace.s2), child: ErrorText(auth.error!)),
          const SizedBox(height: FgSpace.s3),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: auth.isLoading
                ? null
                : () {
                    FgHaptics.success();
                    ref.read(authProvider.notifier).signInDev(_user);
                  },
            icon: auth.isLoading
                ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg.onAction))
                : const Icon(FgIcons.signIn, size: 20),
            label: Text(s.t('devSignIn')),
          ),
        ]),
      ),
    );
  }
}

/// Splash-like loading screen while the session is restored.
class FgLoadingScreen extends StatelessWidget {
  const FgLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.fg.heroStart,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FgBrandMark(size: 96, tile: false, tileColor: context.fg.heroStart),
            const SizedBox(height: FgSpace.s6),
            const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
          ]),
        ),
      );
}

/// Signed in, but the portal user has no role for this app.
class NoAccessScreen extends ConsumerWidget {
  const NoAccessScreen({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: commonActions(context, ref)),
      body: Center(
        child: EmptyState(
          art: FgArt.error,
          title: s.t('noAccess'),
          message: s.t('noAccessHint'),
          actionLabel: s.t('signOut'),
          onAction: () => ref.read(authProvider.notifier).signOut(),
        ),
      ),
    );
  }
}
