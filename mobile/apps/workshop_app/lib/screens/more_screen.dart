import 'dart:convert';

import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bookings_review_screen.dart';

/// Shows the caller's handover badge (GET /workshop/me/badge: QR PNG, name, custody role, workshop).
Future<void> _showBadge(BuildContext context, WidgetRef ref) async {
  final s = ref.read(stringsProvider);
  try {
    final b = asRow(await ref.read(apiProvider).get('/workshop/me/badge'));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('myBadge')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(FgSpace.s3),
            child: Image.memory(base64Decode(b.s('qrPng')), width: 220, height: 220, filterQuality: FilterQuality.none),
          ),
          const SizedBox(height: FgSpace.s3),
          Text(b.s('name'), style: context.tt.titleMedium),
          Text([s.status(b.s('custodyRole')), b.s('workshop')].where((x) => x.isNotEmpty).join(' · '), style: context.tt.bodySmall),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.t('done')))],
      ),
    );
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// "More" tab of the workshop app: profile and roles, mobility, outbox, language, sign-out.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final user = ref.watch(authProvider).value;
    final outbox = ref.watch(outboxProvider).value ?? const <OutboxItem>[];
    final failed = outbox.where((i) => i.needsReview).length;
    final mobility = user?.has(['Gate', 'Advisor', 'Dispatcher', 'WorkshopManager']) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('more'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s2, FgSpace.gutter, FgSpace.s6), children: [
        HeroHeader(
          child: Row(children: [
            FgAvatar(user?.contactName ?? '?', size: 56, onHero: true),
            const SizedBox(width: FgSpace.s4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.contactName ?? '', style: context.tt.titleLarge?.copyWith(color: Colors.white)),
                Text(s.t('appWorkshop'), style: context.tt.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                if (user != null && user.roles.isNotEmpty) ...[
                  const SizedBox(height: FgSpace.s2),
                  Wrap(spacing: FgSpace.s1, runSpacing: FgSpace.s1, children: [
                    for (final r in user.roles)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: FgSpace.s2, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: FgRadius.brPill),
                        child: Text(s.status(r.role), style: context.tt.labelSmall?.copyWith(color: Colors.white)),
                      ),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
        FgSectionTitle(s.t('workshop')),
        Card(
          child: Column(children: [
            if (user?.has(bookingReviewRoles) ?? false)
              FgMenuTile(icon: FgIcons.proposal, title: s.t('bookingsToConfirm'), onTap: () => context.push('/bookings')),
            if (mobility) FgMenuTile(icon: FgIcons.mobility, title: s.t('mobility'), onTap: () => context.push('/mobility')),
            // prompt 2 (4.7): personal handover badge (signed QR) another user scans on the handover form
            FgMenuTile(icon: FgIcons.qr, title: s.t('myBadge'), subtitle: s.t('myBadgeHint'), onTap: () => _showBadge(context, ref)),
            FgMenuTile(
              icon: FgIcons.outbox,
              title: s.t('outbox'),
              tone: failed > 0 ? FgTone.bad : FgTone.progress,
              trailing: outbox.isEmpty ? null : CountPill(outbox.length, tone: failed > 0 ? FgTone.bad : FgTone.attention),
              onTap: () => context.push('/outbox'),
            ),
          ]),
        ),
        FgSectionTitle(s.t('app')),
        Card(
          child: Column(children: [
            FgMenuTile(
              icon: FgIcons.language,
              title: s.t('languageMenu'),
              subtitle: s.t('language'),
              onTap: () {
                FgHaptics.tap();
                ref.read(localeProvider.notifier).toggle();
              },
            ),
            FgMenuTile(icon: FgIcons.signOut, title: s.t('signOut'), destructive: true, onTap: () => signOutChecked(context, ref)),
          ]),
        ),
        const SizedBox(height: FgSpace.s6),
        Center(
          child: Column(children: [
            const FgBrandMark(size: 36, tileColor: FgColors.n900),
            const SizedBox(height: FgSpace.s2),
            Text('${s.t('appWorkshop')} · ${FgConfig.environment}', style: context.tt.bodySmall),
            Text(ref.watch(serverAddressProvider), style: context.tt.labelSmall),
          ]),
        ),
      ]),
    );
  }
}
