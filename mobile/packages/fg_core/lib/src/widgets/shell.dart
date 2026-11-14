import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth.dart';
import '../config.dart';
import '../fg_icons.dart';
import '../haptics.dart';
import '../i18n.dart';
import '../models.dart';
import '../oidc.dart';
import '../outbox.dart';
import '../server_check.dart';
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
    messenger.showSnackBar(SnackBar(backgroundColor: danger, content: Text(s.error(e), style: TextStyle(color: onDanger))));
    return false;
  }
}

/// Snack bar for an error of a live (non-outbox) call. A step-order refusal (409 StepOrder) carries the "Step order" title.
void showError(BuildContext context, Object error) {
  FgHaptics.warning();
  final fg = context.fg;
  final s = ProviderScope.containerOf(context, listen: false).read(stringsProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(backgroundColor: fg.danger, content: Text(s.error(error), style: TextStyle(color: context.isDark ? FgColors.n950 : FgColors.n0))),
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
    IconButton(tooltip: s.t('signOut'), onPressed: () => signOutChecked(context, ref), icon: const Icon(FgIcons.signOut)),
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

/// Opens a camera that reads a QR code and returns its text (null when cancelled). The apps provide it; without it the
/// server dialog offers typing only.
final serverQrScanProvider = Provider<Future<String?> Function(BuildContext context)?>((ref) => null);

/// D-111 / prompt 3 (C1): the active portal users of the company, read live from D365 for the development sign-in
/// (GET /dev/users?portal=workshop|customer: id, label, type). It works without "Generate demo data" and reloads when the
/// server address changes (the API client depends on it).
final devUsersProvider = FutureProvider.autoDispose.family<List<FgRow>, String>(
  (ref, portal) async => asRows(await ref.watch(apiProvider).get('/dev/users', query: {'portal': portal})).where((u) => u.s('id').isNotEmpty).toList(),
);

/// Development sign-in (labelled; the API refuses it outside Development). The list holds the active portal users of D365
/// for this app ([portal] = workshop or customer); [fallbackUsers] are shown only when the API cannot be reached.
class DevSignInScreen extends ConsumerStatefulWidget {
  const DevSignInScreen({super.key, required this.title, required this.portal, this.fallbackUsers = const {}, this.subtitle});
  final String title;
  final String? subtitle;

  /// workshop (workshop staff and partners) or customer (customers, drivers, internal fleet).
  final String portal;

  /// Used only when the user list cannot be loaded from D365 (API unreachable).
  final Map<String, String> fallbackUsers;

  @override
  ConsumerState<DevSignInScreen> createState() => _DevSignInScreenState();
}

class _DevSignInScreenState extends ConsumerState<DevSignInScreen> {
  String? _user;
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final auth = ref.watch(authProvider);
    final fg = context.fg;
    final loaded = ref.watch(devUsersProvider(widget.portal));
    final live = loaded.value;
    // prompt 3 (C1): the fixed list only when the API cannot be reached; D365 without active users shows that message instead
    final fallback = loaded.hasError;
    final all = <MapEntry<String, String>>[
      // Only the live users of D365: when the server cannot be reached the screen explains how to connect instead of
      // offering a built-in list that could not sign in anyway.
      if (live != null)
        for (final u in live) MapEntry(u.s('id'), u.s('label').isEmpty ? u.s('id') : u.s('label')),
    ];
    final q = _filter.text.trim().toLowerCase();
    final users = q.isEmpty ? all : all.where((e) => e.key.toLowerCase().contains(q) || e.value.toLowerCase().contains(q)).toList();
    final selected = all.any((e) => e.key == _user) ? _user : (all.isEmpty ? null : all.first.key);
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
          _ServerAddressTile(state: fallback ? 'serverStatusDown' : (live != null ? 'serverStatusOk' : 'serverStatusChecking')),
          const SizedBox(height: FgSpace.s4),
          // D-110: production sign-in with the organisation's OpenID Connect provider (system browser, PKCE)
          if (FgOidc.configured) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: auth.isLoading ? null : () => ref.read(authProvider.notifier).signInOidc(),
              icon: const Icon(FgIcons.signIn, size: 20),
              label: Text(s.t('signIn')),
            ),
            if (auth.hasError && !FgConfig.devSignIn) Padding(padding: const EdgeInsets.all(FgSpace.s2), child: ErrorText(auth.error!)),
            const SizedBox(height: FgSpace.s4),
          ],
          if (FgConfig.devSignIn && fallback) ...[
            // One clear message with what to do, instead of several stacked warnings.
            FgNotice(
              tone: FgTone.bad,
              title: s.t('serverHelpTitle'),
              message: '${s.t('serverHelpBody')}\n\n${s.t('serverHelpDetail', [s.error(loaded.error!)])}',
            ),
            const SizedBox(height: FgSpace.s4),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: loaded.isLoading ? null : () => ref.invalidate(devUsersProvider(widget.portal)),
              icon: const Icon(FgIcons.refresh, size: 20),
              label: Text(s.t('retry')),
            ),
          ] else if (FgConfig.devSignIn) ...[
          FgNotice(
            tone: FgTone.attention,
            title: FgConfig.environment == 'Development' ? s.t('devSignIn') : '${s.t('devSignIn')} · ${FgConfig.environment}',
            message: s.t('devSignInNote'),
          ),
          const SizedBox(height: FgSpace.s4),
          Row(children: [
            Expanded(child: Text(s.t('portalUser'), style: context.tt.titleSmall)),
            IconButton(
              tooltip: s.t('refresh'),
              onPressed: () => ref.invalidate(devUsersProvider(widget.portal)),
              icon: const Icon(FgIcons.refresh, size: 20),
            ),
          ]),
          Text(s.t('devUsersLive'), style: context.tt.bodySmall),
          const SizedBox(height: FgSpace.s2),
          if (loaded.isLoading && live == null) const LinearProgressIndicator(),
          if (all.length > 6) ...[
            TextField(
              controller: _filter,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: s.t('devUsersFilter'), prefixIcon: const Icon(FgIcons.search, size: 20)),
            ),
            const SizedBox(height: FgSpace.s2),
          ],
          if (!loaded.isLoading && all.isEmpty) Text(s.t('devUsersNone'), style: context.tt.bodySmall),
          for (final entry in users)
            Padding(
              padding: const EdgeInsets.only(bottom: FgSpace.s2),
              child: Semantics(
                selected: entry.key == selected,
                button: true,
                child: Material(
                  color: entry.key == selected ? fg.primaryBg : fg.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: FgRadius.brLg,
                    side: BorderSide(color: entry.key == selected ? fg.primary : fg.border, width: entry.key == selected ? 2 : 1),
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
                        if (entry.key == selected) Icon(FgIcons.good, color: fg.primary),
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
            onPressed: auth.isLoading || selected == null
                ? null
                : () {
                    FgHaptics.success();
                    ref.read(authProvider.notifier).signInDev(selected);
                  },
            icon: auth.isLoading
                ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg.onAction))
                : const Icon(FgIcons.signIn, size: 20),
            label: Text(s.t('devSignIn')),
          ),
          ],
        ]),
      ),
    );
  }
}

/// The Fleet Geeks server the app talks to; tap to change it (saved on the phone, so one APK works on any network).
class _ServerAddressTile extends ConsumerWidget {
  const _ServerAddressTile({this.state});

  /// i18n key of the connection state shown under the address (serverStatusOk / Down / Checking).
  final String? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final server = ref.watch(serverAddressProvider);
    final fg = context.fg;
    return Material(
      color: fg.surface,
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: fg.border)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(FgIcons.server),
        title: Text(s.t('serverAddress')),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(server, textDirection: TextDirection.ltr),
          if (state != null)
            Text(
              s.t(state!),
              style: context.tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: switch (state) { 'serverStatusOk' => fg.success, 'serverStatusDown' => fg.danger, _ => fg.textMuted },
              ),
            ),
        ]),
        trailing: const Icon(FgIcons.settings, size: 18),
        onTap: () => _edit(context, ref, server),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, String current) async {
    final s = ref.read(stringsProvider);
    final connected = await showDialog<ServerCheck>(context: context, builder: (ctx) => _ServerDialog(current: current));
    if (connected != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('serverConnected', [connected.company]))));
    }
  }
}

/// D-113: the address is checked before it is saved - the API address or a portal link, on the same Wi-Fi or published.
class _ServerDialog extends ConsumerStatefulWidget {
  const _ServerDialog({required this.current});
  final String current;

  @override
  ConsumerState<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends ConsumerState<_ServerDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.current);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final s = ref.read(stringsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await ref.read(serverAddressProvider.notifier).connect(_ctrl.text);
      if (mounted) Navigator.pop(context, found);
    } on ServerCheckException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = s.t(e.reason == 'empty' ? 'serverEmpty' : (e.reason == 'notFleetGeeks' ? 'serverNotFleetGeeks' : 'serverUnreachable'));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final scan = ref.watch(serverQrScanProvider);
    return AlertDialog(
      title: Text(s.t('serverAddress')),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          autocorrect: false,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            helperText: s.t('serverAddressHint'),
            helperMaxLines: 6,
            suffixIcon: scan == null
                ? null
                : IconButton(
                    tooltip: s.t('serverScanQr'),
                    icon: const Icon(FgIcons.qr),
                    onPressed: _busy
                        ? null
                        : () async {
                            final value = await scan(context);
                            if (value == null || value.trim().isEmpty || !mounted) return;
                            _ctrl.text = value.trim();
                            await _connect();
                          },
                  ),
          ),
          onSubmitted: (_) => _busy ? null : _connect(),
        ),
        // The result is shown in full under the field: a long explanation is never cut off.
        if (_error != null) ...[
          const SizedBox(height: FgSpace.s3),
          FgNotice(message: _error!, tone: FgTone.bad),
        ],
        if (_busy) ...[
          const SizedBox(height: FgSpace.s3),
          Row(children: [
            const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: FgSpace.s2),
            Expanded(child: Text(s.t('serverChecking'))),
          ]),
        ],
        const SizedBox(height: FgSpace.s2),
        // Secondary choice: a quiet link under the field, not a third dialog button.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await ref.read(serverAddressProvider.notifier).set('');
                    if (context.mounted) Navigator.pop(context);
                  },
            child: Text(s.t('serverAddressReset')),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(s.t('cancel'))),
        FilledButton(onPressed: _busy ? null : _connect, child: Text(s.t('serverConnect'))),
      ],
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
          onAction: () => signOutChecked(context, ref),
        ),
      ),
    );
  }
}
