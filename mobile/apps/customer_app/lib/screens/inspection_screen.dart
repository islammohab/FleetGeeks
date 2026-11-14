import 'dart:convert';

import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'vehicles_screen.dart';

const _templateCacheKey = 'fg.cache.inspectionTemplate';

/// Checklist of the daily inspection. Cached on the phone so a driver without signal can still inspect; the cached copy
/// is used only when the API is not reachable.
final inspectionTemplateProvider = FutureProvider.autoDispose<(FgRow, bool)>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  try {
    final fresh = asRow(await ref.watch(apiProvider).get('/inspections/template'));
    await storage.write(key: _templateCacheKey, value: jsonEncode(fresh));
    return (fresh, false);
  } on ApiException catch (e) {
    final cached = await storage.read(key: _templateCacheKey);
    if (e.isNetwork && cached != null) return (asRow(jsonDecode(cached)), true);
    rethrow;
  }
});

/// Driver pre-trip inspection: OK / not OK per item with a note. Sent through the outbox, so it also works offline;
/// defects reach the workshop automatically and a failed safety-critical item puts the vehicle on hold.
class InspectionScreen extends ConsumerStatefulWidget {
  const InspectionScreen({super.key});

  @override
  ConsumerState<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends ConsumerState<InspectionScreen> {
  String? _vehicle;
  final _odometer = TextEditingController();
  final Map<int, bool> _passed = {};
  final Map<int, TextEditingController> _notes = {};

  @override
  void dispose() {
    _odometer.dispose();
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _note(int line) => _notes.putIfAbsent(line, TextEditingController.new);

  Future<void> _submit(List<FgRow> questions) async {
    final s = ref.read(stringsProvider);
    if (_vehicle == null) return;
    final answers = [
      for (final q in questions)
        {
          'question': q.s('question'),
          'passed': _passed[q.n('line').round()] ?? true,
          'safetyCritical': q['safetyCritical'] == true,
          'value': 0,
          'note': _note(q.n('line').round()).text.trim(),
        },
    ];
    await runCommand(
      context,
      ref,
      () => ref.read(outboxProvider.notifier).submit('/inspections',
          label: '${s.t('inspection')} $_vehicle',
          body: {'vehicleId': _vehicle, 'odometer': double.tryParse(_odometer.text) ?? 0, 'location': '', 'answers': answers}),
    );
    if (mounted) {
      setState(() {
        _passed.clear();
        for (final c in _notes.values) {
          c.clear();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final vehicles = ref.watch(vehiclesProvider);
    final template = ref.watch(inspectionTemplateProvider);
    final questions = template.value == null ? const <FgRow>[] : asRows(template.value!.$1['questions']);
    final issues = questions.where((q) => _passed[q.n('line').round()] == false).toList();
    final unsafe = issues.any((q) => q['safetyCritical'] == true);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('inspection')), actions: [OutboxButton(onPressed: () => context.push('/outbox'))]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        OfflineBanner(onOpenOutbox: () => context.push('/outbox')),
        FgActionBar(
          top: questions.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(FgSpace.gutter, FgSpace.s3, FgSpace.gutter, 0),
                  child: Row(children: [
                    Icon(issues.isEmpty ? FgIcons.good : (unsafe ? FgIcons.safety : FgIcons.warning),
                        size: 18, color: issues.isEmpty ? context.fg.success : (unsafe ? context.fg.danger : context.fg.warning)),
                    const SizedBox(width: FgSpace.s2),
                    Expanded(
                      child: Text(
                        issues.isEmpty ? s.t('allItemsOk', [questions.length]) : s.t(unsafe ? 'issuesUnsafe' : 'issuesFound', [issues.length]),
                        style: context.tt.labelMedium,
                      ),
                    ),
                  ]),
                ),
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _vehicle == null || questions.isEmpty ? null : () => _submit(questions),
                icon: const Icon(FgIcons.send, size: 18),
                label: Text(s.t('submit')),
              ),
            ),
          ],
        ),
      ]),
      body: AsyncBody(
        value: template,
        onRetry: () => ref.invalidate(inspectionTemplateProvider),
        builder: (data) {
          final (_, fromCache) = data;
          final vs = vehicles.value ?? const <FgRow>[];
          _vehicle ??= vs.isEmpty ? null : vs.first.s('VehicleId');
          return ListView(padding: const EdgeInsets.all(FgSpace.gutter), children: [
            FgNotice(tone: FgTone.info, icon: FgIcons.inspection, message: s.t('inspectionHint')),
            if (fromCache) ...[
              const SizedBox(height: FgSpace.s2),
              FgNotice(tone: FgTone.attention, icon: FgIcons.offline, message: s.t('offlineTemplate')),
            ],
            const SizedBox(height: FgSpace.s4),
            if (vs.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _vehicle,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.t('vehicle'), prefixIcon: const Icon(FgIcons.vehicles, size: 20)),
                items: [for (final v in vs) DropdownMenuItem(value: v.s('VehicleId'), child: Text(vehicleOption(v), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _vehicle = v),
              ),
            const SizedBox(height: FgSpace.s3),
            TextField(
              controller: _odometer,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontFeatures: FgFonts.tabular),
              decoration: InputDecoration(labelText: s.t('odometer'), suffixText: 'km', prefixIcon: const Icon(FgIcons.odometer, size: 20)),
            ),
            const SizedBox(height: FgSpace.s4),
            for (var i = 0; i < questions.length; i++) ...[
              _QuestionCard(
                index: i + 1,
                total: questions.length,
                label: s.lang == 'ar' && questions[i].s('questionAr').isNotEmpty ? questions[i].s('questionAr') : questions[i].s('question'),
                safetyCritical: questions[i]['safetyCritical'] == true,
                ok: _passed[questions[i].n('line').round()] ?? true,
                note: _note(questions[i].n('line').round()),
                onChanged: (v) {
                  FgHaptics.tap();
                  setState(() => _passed[questions[i].n('line').round()] = v);
                },
              ),
              const SizedBox(height: FgSpace.s3),
            ],
          ]);
        },
      ),
    );
  }
}

class _QuestionCard extends ConsumerWidget {
  const _QuestionCard({required this.index, required this.total, required this.label, required this.safetyCritical, required this.ok, required this.note, required this.onChanged});
  final int index;
  final int total;
  final String label;
  final bool safetyCritical;
  final bool ok;
  final TextEditingController note;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fg = context.fg;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: ok ? fg.border : fg.danger, width: ok ? 1 : 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(FgSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$index/$total', style: context.tt.labelMedium?.copyWith(color: fg.textMuted, fontFeatures: FgFonts.tabular)),
            const SizedBox(width: FgSpace.s3),
            Expanded(child: Text(label, style: context.tt.titleSmall)),
            if (safetyCritical)
              Tooltip(message: s.t('safetyCritical'), child: Icon(FgIcons.safety, color: fg.danger, size: 20)),
          ]),
          const SizedBox(height: FgSpace.s3),
          Row(children: [
            Expanded(child: _Answer(label: s.t('ok'), icon: FgIcons.good, selected: ok, good: true, onTap: () => onChanged(true))),
            const SizedBox(width: FgSpace.s3),
            Expanded(child: _Answer(label: s.t('notOk'), icon: FgIcons.bad, selected: !ok, good: false, onTap: () => onChanged(false))),
          ]),
          if (!ok) ...[
            const SizedBox(height: FgSpace.s3),
            TextField(controller: note, decoration: InputDecoration(labelText: s.t('note'))),
          ],
        ]),
      ),
    );
  }
}

/// Big two-way answer button (OK green / Not OK red when selected).
class _Answer extends StatelessWidget {
  const _Answer({required this.label, required this.icon, required this.selected, required this.good, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final bool good;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = context.fg;
    final c = fg.tone(good ? FgTone.good : FgTone.bad);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.bg : fg.surface,
        shape: RoundedRectangleBorder(borderRadius: FgRadius.brMd, side: BorderSide(color: selected ? c.fg : context.cs.outline, width: selected ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: selected ? c.fg : fg.textMuted),
              const SizedBox(width: FgSpace.s2),
              Text(label, style: context.tt.labelLarge?.copyWith(color: selected ? c.fg : fg.text)),
            ]),
          ),
        ),
      ),
    );
  }
}
