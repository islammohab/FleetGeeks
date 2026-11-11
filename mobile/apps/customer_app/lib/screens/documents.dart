import 'dart:io';

import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

/// Downloads a PDF with the user's token into the app's temporary folder and opens it with the phone's PDF viewer.
Future<void> openPdf(BuildContext context, WidgetRef ref, String path, String fileName, {Map<String, Object?>? query}) async {
  final s = ref.read(stringsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final danger = context.fg.danger;
  final onDanger = context.isDark ? FgColors.n950 : FgColors.n0;
  FgHaptics.light();
  messenger.showSnackBar(SnackBar(content: Text(s.t('downloading')), duration: const Duration(seconds: 2)));
  try {
    final bytes = await ref.read(apiProvider).getBytes(path, query: query);
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}fg-docs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}${safe.toLowerCase().endsWith('.pdf') ? safe : '$safe.pdf'}');
    await file.writeAsBytes(bytes, flush: true);
    final result = await OpenFilex.open(file.path, type: 'application/pdf');
    if (result.type != ResultType.done) {
      messenger.showSnackBar(SnackBar(content: Text(result.type == ResultType.noAppToOpen ? s.t('noPdfViewer') : result.message)));
    }
  } catch (e) {
    FgHaptics.warning();
    messenger.showSnackBar(SnackBar(backgroundColor: danger, content: Text('$e', style: TextStyle(color: onDanger))));
  }
}

/// Starts a payment for a service order (POST /service-orders/{id}/payments). With a payment link the phone's browser
/// opens it (the provider's webhook confirms the payment, never the browser); without one the API's message tells the
/// customer to pay at the counter or on account.
Future<void> startPayment(BuildContext context, WidgetRef ref, String orderId) async {
  final s = ref.read(stringsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final danger = context.fg.danger;
  final onDanger = context.isDark ? FgColors.n950 : FgColors.n0;
  try {
    final r = asRow(await ref.read(apiProvider).post('/service-orders/${Uri.encodeComponent(orderId)}/payments', idempotencyKey: const Uuid().v4(), body: const <String, Object?>{}));
    final url = Uri.tryParse(r.s('url'));
    if (r.s('url').isNotEmpty && url != null) {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) messenger.showSnackBar(SnackBar(content: Text(s.t('cannotOpenLink'))));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(FgIcons.wallet),
        title: Text(s.t('payment')),
        content: Text(r.s('message').isEmpty ? s.t('payAtCounter') : r.s('message')),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.t('done')))],
      ),
    );
  } catch (e) {
    FgHaptics.warning();
    messenger.showSnackBar(SnackBar(backgroundColor: danger, content: Text('$e', style: TextStyle(color: onDanger))));
  }
}
