import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../fg_icons.dart';
import '../i18n.dart';
import '../status.dart';
import '../theme.dart';
import 'illustrations.dart';
import 'skeleton.dart';

/// Error message with the API correlation id (for support).
class ErrorText extends StatelessWidget {
  const ErrorText(this.error, {super.key, this.textAlign = TextAlign.center});
  final Object error;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final ref = error is ApiException ? (error as ApiException).correlationId : null;
    return Text('$error${ref == null ? '' : '\n($ref)'}', style: context.tt.bodyMedium?.copyWith(color: context.fg.danger), textAlign: textAlign);
  }
}

/// Empty list / nothing to do: illustration, title, message and an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.art = FgArt.empty, this.actionLabel, this.onAction, this.compact = false});
  final String title;
  final String? message;
  final FgArt art;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Smaller version for use inside a card.
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: FgSpace.s6, vertical: compact ? FgSpace.s4 : FgSpace.s8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FgIllustration(art, size: compact ? 88 : 140),
          SizedBox(height: compact ? FgSpace.s2 : FgSpace.s4),
          Text(title, textAlign: TextAlign.center, style: compact ? context.tt.titleSmall : context.tt.titleMedium),
          if (message != null) ...[
            const SizedBox(height: FgSpace.s1),
            Text(message!, textAlign: TextAlign.center, style: context.tt.bodySmall),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: FgSpace.s4),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      );
}

/// Error with retry. Network errors get the offline illustration and a calmer message.
class ErrorState extends ConsumerWidget {
  const ErrorState({super.key, required this.error, this.onRetry, this.compact = false});
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final network = error is ApiException && (error as ApiException).isNetwork;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: FgSpace.s6, vertical: compact ? FgSpace.s4 : FgSpace.s8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FgIllustration(network ? FgArt.offline : FgArt.error, size: compact ? 88 : 140),
        const SizedBox(height: FgSpace.s4),
        Text(s.t(network ? 'errorOfflineTitle' : 'errorTitle'), textAlign: TextAlign.center, style: context.tt.titleMedium),
        const SizedBox(height: FgSpace.s1),
        if (network) Text(s.t('errorOfflineText'), textAlign: TextAlign.center, style: context.tt.bodySmall) else ErrorText(error),
        if (onRetry != null) ...[
          const SizedBox(height: FgSpace.s4),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(FgIcons.retry, size: 18), label: Text(s.t('retry'))),
        ],
      ]),
    );
  }
}

/// Loading / error / data of an AsyncValue: skeleton while loading, [ErrorState] with retry on error.
/// [scrollable] keeps loading and error states scrollable so a surrounding pull-to-refresh still works.
class AsyncBody<T> extends ConsumerWidget {
  const AsyncBody({super.key, required this.value, required this.builder, this.onRetry, this.loading, this.scrollable = true});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return value.when(
      data: builder,
      loading: () => Semantics(label: s.t('loading'), child: loading ?? const SkeletonList()),
      error: (e, _) {
        final state = Center(child: ErrorState(error: e, onRetry: onRetry));
        return scrollable ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [state]) : state;
      },
    );
  }
}

/// Inline notice (info / attention / bad / good) with an icon; optional action on the end side.
class FgNotice extends StatelessWidget {
  const FgNotice({super.key, required this.message, this.tone = FgTone.info, this.icon, this.title, this.action});
  final String message;
  final String? title;
  final FgTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.fg.tone(tone);
    return Semantics(
      container: true,
      liveRegion: tone == FgTone.bad || tone == FgTone.attention,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(FgSpace.s3, FgSpace.s3, FgSpace.s3, FgSpace.s3),
        decoration: BoxDecoration(color: c.bg, borderRadius: FgRadius.brMd),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon ?? _toneIcon(tone), color: c.fg, size: 20),
          const SizedBox(width: FgSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) Text(title!, style: context.tt.titleSmall?.copyWith(color: c.fg)),
              Text(message, style: context.tt.bodyMedium?.copyWith(color: c.fg)),
            ]),
          ),
          if (action != null) ...[const SizedBox(width: FgSpace.s2), action!],
        ]),
      ),
    );
  }

  static IconData _toneIcon(FgTone tone) => switch (tone) {
        FgTone.good => FgIcons.good,
        FgTone.bad => FgIcons.danger,
        FgTone.attention => FgIcons.warning,
        _ => FgIcons.info,
      };
}
