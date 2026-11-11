import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fg_icons.dart';
import '../i18n.dart';
import '../theme.dart';

/// Progress header of a wizard: numbered steps joined by a line, the current step's name below.
/// Earlier steps can be tapped to go back ([onStep]); later steps cannot be skipped.
class FgStepperHeader extends ConsumerWidget {
  const FgStepperHeader({super.key, required this.steps, required this.current, this.onStep});
  final List<String> steps;
  final int current;
  final ValueChanged<int>? onStep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    return Container(
      color: fg.surface,
      padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s3, FgSpace.gutter, FgSpace.s3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            _Dot(
              index: i,
              done: i < current,
              active: i == current,
              label: steps[i],
              onTap: onStep != null && i < current ? () => onStep!(i) : null,
            ),
            if (i < steps.length - 1)
              Expanded(
                child: AnimatedContainer(
                  duration: FgMotion.base,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: FgSpace.s1),
                  color: i < current ? fg.primary : fg.border,
                ),
              ),
          ],
        ]),
        const SizedBox(height: FgSpace.s2),
        Semantics(
          liveRegion: true,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${s.t('stepOf', [current + 1, steps.length])} · ', style: context.tt.labelMedium?.copyWith(color: fg.textMuted)),
              TextSpan(text: steps[current], style: context.tt.titleSmall),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.index, required this.done, required this.active, required this.label, this.onTap});
  final int index;
  final bool done;
  final bool active;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    final bg = done ? fg.primary : (active ? fg.action : fg.surface2);
    final fgColor = done ? fg.onPrimary : (active ? fg.onAction : fg.textMuted);
    final dot = AnimatedContainer(
      duration: FgMotion.base,
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: done
          ? Icon(FgIcons.check, size: 16, color: fgColor)
          : Text('${index + 1}', style: context.tt.labelMedium?.copyWith(color: fgColor, fontWeight: FontWeight.w700, fontFeatures: FgFonts.tabular)),
    );
    return Semantics(
      button: onTap != null,
      selected: active,
      label: label,
      child: onTap == null
          ? dot
          : InkResponse(onTap: onTap, radius: 24, child: Padding(padding: const EdgeInsets.all(10), child: dot)),
    );
  }
}
