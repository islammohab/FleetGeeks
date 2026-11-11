import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fg_icons.dart';
import '../format.dart';
import '../haptics.dart';
import '../i18n.dart';
import '../outbox.dart';
import '../status.dart';
import '../theme.dart';
import 'buttons.dart';
import 'illustrations.dart';
import 'states.dart';

/// True while the phone has a network (Wi-Fi, mobile data, ethernet …). Only a hint for the UI: the outbox decides
/// by actually calling the API.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
  try {
    yield online(await connectivity.checkConnectivity());
  } catch (_) {
    yield true;
  }
  yield* connectivity.onConnectivityChanged.map(online);
});

/// Strip shown above the bottom navigation (or at the bottom of a pushed screen): offline, or commands waiting /
/// refused. Hidden when online and the outbox is empty.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, this.onOpenOutbox, this.safeArea = false});
  final VoidCallback? onOpenOutbox;

  /// Add the bottom system inset (when the banner is the last thing on the screen).
  final bool safeArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final online = ref.watch(connectivityProvider).value ?? true;
    final items = ref.watch(outboxProvider).value ?? const <OutboxItem>[];
    final failed = items.where((i) => i.failed).length;
    final waiting = items.length - failed;
    final fg = context.fg;

    Widget? content;
    if (!online || waiting > 0 || failed > 0) {
      final tone = failed > 0 ? FgTone.bad : (online ? FgTone.info : FgTone.attention);
      final c = fg.tone(tone);
      final text = !online
          ? (waiting > 0 ? s.t('offlineWaiting', [waiting]) : s.t('offlineBanner'))
          : (failed > 0 ? s.t('outboxRefused', [failed]) : s.t('outboxWaiting', [waiting]));
      content = Material(
        key: ValueKey('$online/$waiting/$failed'),
        color: c.bg,
        child: InkWell(
          onTap: onOpenOutbox,
          child: SafeArea(
            top: false,
            bottom: safeArea,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FgSpace.gutter, vertical: 10),
              child: Row(children: [
                Icon(!online ? FgIcons.offline : (failed > 0 ? FgIcons.danger : FgIcons.outbox), size: 18, color: c.fg),
                const SizedBox(width: FgSpace.s2),
                Expanded(child: Text(text, style: context.tt.labelMedium?.copyWith(color: c.fg, fontWeight: FontWeight.w600))),
                if (onOpenOutbox != null && items.isNotEmpty) Icon(FgIcons.chevronForward, size: 18, color: c.fg),
              ]),
            ),
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: AnimatedSize(
        duration: FgMotion.base,
        curve: FgMotion.easeOut,
        alignment: AlignmentDirectional.bottomCenter,
        child: content ?? const SizedBox(width: double.infinity),
      ),
    );
  }
}

/// App-bar button with the outbox count (orange) or the refused count (red).
class OutboxButton extends ConsumerWidget {
  const OutboxButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final items = ref.watch(outboxProvider).value ?? const <OutboxItem>[];
    final failed = items.where((i) => i.failed).length;
    final online = ref.watch(connectivityProvider).value ?? true;
    return IconButton(
      tooltip: '${s.t('outbox')} (${items.length})',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: items.isNotEmpty,
        backgroundColor: failed > 0 ? context.fg.danger : context.fg.action,
        label: Text('${items.length}', style: const TextStyle(fontFeatures: FgFonts.tabular)),
        child: Icon(online ? FgIcons.outbox : FgIcons.offline),
      ),
    );
  }
}

/// Commands waiting on this device, with retry / discard for refused ones.
class OutboxScreen extends ConsumerWidget {
  const OutboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final items = ref.watch(outboxProvider);
    final online = ref.watch(connectivityProvider).value ?? true;
    final list = items.value ?? const <OutboxItem>[];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('outbox'))),
      bottomNavigationBar: list.where((i) => !i.failed).isEmpty
          ? null
          : FgActionBar(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    FgHaptics.success();
                    await ref.read(outboxProvider.notifier).flush();
                  },
                  icon: const Icon(FgIcons.send, size: 18),
                  label: Text(s.t('sendNow')),
                ),
              ),
            ]),
      body: AsyncBody(
        value: items,
        builder: (rows) => rows.isEmpty
            ? ListView(children: [EmptyState(art: FgArt.done, title: s.t('outboxEmpty'), message: s.t('outboxEmptyText'))])
            : ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
                FgNotice(
                  tone: online ? FgTone.info : FgTone.attention,
                  icon: online ? FgIcons.outbox : FgIcons.offline,
                  message: s.t(online ? 'outboxExplain' : 'offlineBanner'),
                ),
                const SizedBox(height: FgSpace.s3),
                for (final item in rows) ...[
                  _OutboxCard(item: item),
                  const SizedBox(height: FgSpace.s2),
                ],
              ]),
      ),
    );
  }
}

class _OutboxCard extends ConsumerWidget {
  const _OutboxCard({required this.item});
  final OutboxItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = context.fg.tone(item.failed ? FgTone.bad : FgTone.attention);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FgSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brMd),
              child: Icon(item.failed ? FgIcons.danger : FgIcons.waiting, color: c.fg, size: 20),
            ),
            const SizedBox(width: FgSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.label, style: context.tt.titleSmall),
                const SizedBox(height: 2),
                Text(
                  item.failed ? '${s.t('failedCommand')}: ${item.lastError ?? ''}' : '${s.t('waitingSince')} ${fmtDate(item.createdAt.toLocal(), s.lang)}',
                  style: context.tt.bodySmall?.copyWith(color: item.failed ? c.fg : null),
                ),
              ]),
            ),
          ]),
          if (item.failed) ...[
            const SizedBox(height: FgSpace.s3),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                onPressed: () => ref.read(outboxProvider.notifier).discard(item),
                icon: const Icon(FgIcons.delete, size: 18),
                label: Text(s.t('discard')),
              ),
              const SizedBox(width: FgSpace.s2),
              OutlinedButton.icon(
                onPressed: () => ref.read(outboxProvider.notifier).retry(item),
                icon: const Icon(FgIcons.retry, size: 18),
                label: Text(s.t('retry')),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
