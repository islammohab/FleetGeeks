import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'checklist_sheet.dart';
import 'providers.dart';

// Technician / QC commands of one job line. All go through the offline outbox (sent now, or kept and replayed in order
// with their Idempotency-Key / command id), exactly as before the redesign.

/// start / pause / finish of a job (`/workshop/jobs/{order}/{line}/{verb}`).
Future<void> jobCommand(BuildContext context, WidgetRef ref, String orderId, String line, String verb, {String? reason}) async {
  final s = ref.read(stringsProvider);
  await runCommand(
    context,
    ref,
    () => ref.read(outboxProvider.notifier).submit(
          '/workshop/jobs/${Uri.encodeComponent(orderId)}/$line/$verb',
          // the tap time travels with the command: replayed after a period offline, the job time is the real one (D-110)
          body: {'commandId': const Uuid().v4(), 'pauseReason': reason, 'capturedAtUtc': DateTime.now().toUtc().toIso8601String()},
          label: '${s.t(verb)} · $orderId / $line',
        ),
  );
  ref.invalidate(orderProvider(orderId));
}

/// Pause needs a D365 pause reason.
Future<void> jobPause(BuildContext context, WidgetRef ref, String orderId, String line) async {
  final s = ref.read(stringsProvider);
  final reasons = await ref.read(lookupProvider('reasons?type=Pause').future);
  if (!context.mounted) return;
  final reason = await pickLookup(context, title: s.t('pauseReason'), rows: reasons, s: s);
  if (reason != null && context.mounted) await jobCommand(context, ref, orderId, line, 'pause', reason: reason);
}

/// QC result; a failed QC needs a coded reason (rework analysis) from D365.
Future<void> jobQc(BuildContext context, WidgetRef ref, String orderId, String line, bool passed) async {
  final s = ref.read(stringsProvider);
  String? failReason;
  if (!passed) {
    final reasons = await ref.read(lookupProvider('reasons?type=QCFailure').future);
    if (!context.mounted) return;
    failReason = await pickLookup(context, title: s.t('failReason'), rows: reasons, s: s);
    if (failReason == null || !context.mounted) return;
  }
  await runCommand(
    context,
    ref,
    () => ref.read(outboxProvider.notifier).submit(
          '/workshop/qc',
          body: {'serviceOrderId': orderId, 'jobLine': int.parse(line), 'passed': passed, 'notes': '', 'failReason': failReason},
          label: '${s.t('qc')} ${passed ? s.t('qcPass') : s.t('qcFail')} · $orderId / $line',
        ),
  );
  ref.invalidate(orderProvider(orderId));
}

/// Checklist answers of a job (one idempotent command per question).
Future<void> openChecklist(BuildContext context, String orderId, int line, String template) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChecklistSheet(orderId: orderId, jobLine: line, template: template),
    );

/// Evidence categories offered by the camera flow (FGEvidenceCategory).
const evidenceCategories = ['Reception', 'Before', 'After', 'Damage', 'Diagnosis', 'QC'];

/// Prompt 2 (4.10) / 3 (B2): number of photos of a category (Before / After) taken for one job line.
int jobPhotoCount(List<FgRow> evidence, String line, String category) =>
    evidence.where((e) => e.s('Category') == category && e.n('JobLineNum').round().toString() == line).length;

/// Camera-first evidence: choose the category (default "Before", as before the redesign), take the photo, upload it.
/// With [jobLine] the photo belongs to that job (a job starts only with a Before photo and finishes only with an After
/// photo when the D365 parameter requires it). Without a network the photo waits in the offline queue (D-110), ahead of
/// the start / finish command queued after it.
Future<void> takeEvidencePhoto(BuildContext context, WidgetRef ref, String orderId, {String? category, String? jobLine}) async {
  final s = ref.read(stringsProvider);
  var chosen = category;
  if (chosen == null) {
    chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _CategorySheet(initial: 'Before', s: s),
    );
    if (chosen == null || !context.mounted) return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final danger = context.fg.danger;
  final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2400);
  if (shot == null) return;
  try {
    // D-110: without a connection the photo is kept (encrypted) in the offline queue and uploaded when the network returns
    final result = await ref.read(outboxProvider.notifier).submitUpload('/evidence', filePath: shot.path, contentType: 'image/jpeg', fields: {
      'serviceOrderId': orderId,
      'category': chosen,
      'customerVisible': 'true',
      'jobLineNum': ?jobLine,
    }, label: '${s.t('photo')} · $orderId${jobLine == null ? '' : ' / $jobLine'}');
    FgHaptics.success();
    messenger.showSnackBar(SnackBar(content: Text(result.outcome == SubmitOutcome.queued ? s.t('photoQueued') : s.t('uploaded'))));
    ref.invalidate(orderProvider(orderId));
  } catch (e) {
    FgHaptics.warning();
    messenger.showSnackBar(SnackBar(backgroundColor: danger, content: Text(s.error(e))));
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.initial, required this.s});
  final String initial;
  final Strings s;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late String _category = widget.initial;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FgSpace.gutter, 0, FgSpace.gutter, FgSpace.s4),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('photo'), style: context.tt.titleLarge),
          const SizedBox(height: FgSpace.s1),
          Text(s.t('photoCategory'), style: context.tt.bodySmall),
          const SizedBox(height: FgSpace.s3),
          Wrap(spacing: FgSpace.s2, runSpacing: FgSpace.s2, children: [
            for (final c in evidenceCategories)
              ChoiceChip(
                label: Text(s.status(c)),
                selected: _category == c,
                onSelected: (_) {
                  FgHaptics.tap();
                  setState(() => _category = c);
                },
              ),
          ]),
          const SizedBox(height: FgSpace.s4),
          FgBigButton(icon: FgIcons.camera, label: s.t('openCamera'), height: 60, onPressed: () => Navigator.pop(context, _category)),
        ]),
      ),
    );
  }
}
