import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bookings_review_screen.dart';

/// "More" tab of the workshop app: profile and roles, mobility, outbox, language, sign-out.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final user = ref.watch(authProvider).value;
    final outbox = ref.watch(outboxProvider).value ?? const <OutboxItem>[];
    final failed = outbox.where((i) => i.failed).length;
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
            FgMenuTile(icon: FgIcons.signOut, title: s.t('signOut'), destructive: true, onTap: () => ref.read(authProvider.notifier).signOut()),
          ]),
        ),
        const SizedBox(height: FgSpace.s6),
        Center(
          child: Column(children: [
            const FgBrandMark(size: 36, tileColor: FgColors.n900),
            const SizedBox(height: FgSpace.s2),
            Text('${s.t('appWorkshop')} · ${FgConfig.environment}', style: context.tt.bodySmall),
            Text(FgConfig.apiBase, style: context.tt.labelSmall),
          ]),
        ),
      ]),
    );
  }
}
