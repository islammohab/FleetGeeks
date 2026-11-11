import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fg_icons.dart';
import '../i18n.dart';
import '../status.dart';
import '../theme.dart';

/// Status of any Fleet Geeks record: icon + colour from one mapping ([toneOf], [FgIcons.status]) and the
/// translated label. Colour is never the only signal (icon and text carry it too).
class StatusPill extends ConsumerWidget {
  const StatusPill(this.symbol, {super.key, this.label, this.dense = false});
  final String symbol;

  /// Overrides the translated status label.
  final String? label;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (symbol.isEmpty) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final c = context.fg.tone(toneOf(symbol));
    final text = label ?? s.status(symbol);
    return Semantics(
      label: '${s.t('status')}: $text',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? FgSpace.s2 : 10, vertical: dense ? 2 : FgSpace.s1),
        decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brPill),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(FgIcons.status(symbol), size: dense ? 12 : 14, color: c.fg),
          const SizedBox(width: FgSpace.s1),
          // No Flexible here: the pill is often a non-flex child of a Row, where its width is unbounded.
          Text(
            text,
            maxLines: 1,
            style: (dense ? context.tt.labelSmall : context.tt.labelMedium)?.copyWith(color: c.fg, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}

/// Small count pill (lane counters, tab badges).
class CountPill extends StatelessWidget {
  const CountPill(this.count, {super.key, this.tone = FgTone.progress});
  final int count;
  final FgTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.fg.tone(count == 0 ? FgTone.neutral : tone);
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: FgSpace.s2, vertical: 2),
      decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brPill),
      child: Text('$count', textAlign: TextAlign.center, style: context.tt.labelMedium?.copyWith(color: c.fg, fontWeight: FontWeight.w700, fontFeatures: FgFonts.tabular)),
    );
  }
}
