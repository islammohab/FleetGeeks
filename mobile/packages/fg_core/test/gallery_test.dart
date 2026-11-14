import 'dart:convert';
import 'dart:io';

import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders shared widgets to PNG files (test/gallery/*.png) with the real fonts, in English and Arabic, light and dark.
/// Run with `flutter test --update-goldens --tags gallery test/gallery_test.dart`; the build publishes the pictures so the
/// look can be reviewed without a phone.
Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final file = File(f);
      if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  await family(FgFonts.latin, [for (final w in weights) 'fonts/Inter-$w.ttf']);
  await family(FgFonts.arabic, [for (final w in weights) 'fonts/IBMPlexSansArabic-$w.ttf']);
  // Lucide icon font from the package cache.
  for (final config in ['.dart_tool/package_config.json', '../../.dart_tool/package_config.json']) {
    final file = File(config);
    if (!file.existsSync()) continue;
    final packages = (jsonDecode(file.readAsStringSync()) as Map)['packages'] as List;
    for (final p in packages) {
      if (p is! Map || p['name'] != 'lucide_icons_flutter') continue;
      final root = Uri.parse('${p['rootUri']}');
      final dir = Directory.fromUri(root.isAbsolute ? root : file.absolute.parent.uri.resolveUri(root));
      if (!dir.existsSync()) continue;
      final fonts = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.ttf')).map((f) => f.path).toList();
      await family('packages/lucide_icons_flutter/Lucide', fonts);
    }
    break;
  }
}

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this.lang);
  final String lang;

  @override
  Locale build() => Locale(lang);
}

Widget _frame(Widget child, {required String lang, required Brightness brightness}) => ProviderScope(
      key: ValueKey('$lang-${brightness.name}'),
      overrides: [localeProvider.overrideWith(() => _FixedLocale(lang))],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: fgTheme(brightness, lang: lang),
        home: Directionality(
          textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(FgSpace.gutter), child: child))),
        ),
      ),
    );

void main() {
  setUpAll(_loadFonts);

  Future<void> shot(WidgetTester tester, String name, Widget Function() build) async {
    for (final lang in ['en', 'ar']) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        tester.view.physicalSize = const Size(1080, 2000);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_frame(build(), lang: lang, brightness: brightness));
        // let real async work (the failing server call of the sign-in) finish before the picture is taken
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('gallery/${name}_${lang}_${brightness.name}.png'));
      }
    }
  }

  testWidgets('order: next step, rows and notices', tags: 'gallery', (tester) async {
    await shot(
      tester,
      'order',
      () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NextStepCard(status: 'InProgress'),
        const SizedBox(height: FgSpace.s3),
        const NextStepCard(status: 'ReadyForHandback'),
        const SizedBox(height: FgSpace.s3),
        const OrderProgress(status: 'QualityCheck', compact: true),
        const SizedBox(height: FgSpace.s3),
        SectionCard(title: 'Vehicle', icon: FgIcons.vehicles, children: const [
          KeyValueRow('Plate', 'PW-1001', tabular: true),
          KeyValueRow('Odometer', '25,120 km', tabular: true),
          KeyValueRow('Complaint', 'Squeak when braking, stronger when the brakes are cold in the morning'),
          KeyValueRow('Workshop', 'Main workshop (PW)'),
        ]),
        const SizedBox(height: FgSpace.s3),
        const FgNotice(tone: FgTone.bad, title: 'The app cannot reach the server', message: '1. Put the phone on the same Wi-Fi as the PC.\n2. On the PC, start Fleet Geeks with START-NETWORK.cmd.\n3. Check the server address above, then tap Try again.'),
        const SizedBox(height: FgSpace.s3),
        const FgNotice(tone: FgTone.attention, message: 'Development sign-in. The list shows the active portal users of the connected D365 company.'),
        const SizedBox(height: FgSpace.s3),
        const FgNotice(tone: FgTone.good, message: 'Vehicle admitted. Service order FG-SO-000123.'),
        const SizedBox(height: FgSpace.s3),
        Wrap(spacing: FgSpace.s2, runSpacing: FgSpace.s2, children: [
          for (final st in ['Booked', 'InProgress', 'AwaitingParts', 'QualityCheck', 'Rework', 'ReadyForHandback', 'Released']) StatusPill.order(st),
        ]),
      ]),
    );
  });

  testWidgets('lists at a very large system font (130 %)', tags: 'gallery', (tester) async {
    await shot(
      tester,
      'lists_large_font',
      () => MediaQuery(
        data: const MediaQueryData(size: Size(360, 2000), textScaler: TextScaler.linear(1.3)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const VehicleCard(plate: 'PW-1001', title: 'TOYOTA Corolla 2024', vehicleClass: 'CAR', status: 'UnderMaintenance', odometer: '25,120 km'),
          const SizedBox(height: FgSpace.s3),
          FgListCard(
            leading: const IconTile(FgIcons.tasks, tone: FgTone.attention),
            title: 'Estimate to approve',
            subtitle: 'PW-1005',
            trailing: StatusPill.order('AwaitingApproval'),
            onTap: () {},
          ),
          const SizedBox(height: FgSpace.s3),
          FgListCard(
            leading: const IconTile(FgIcons.tasks, tone: FgTone.good),
            title: 'FG-SO-000005',
            subtitle: 'PW-1003',
            trailing: StatusPill.order('QualityCheck'),
            onTap: () {},
          ),
          const SizedBox(height: FgSpace.s3),
          Row(children: [
            for (final l in ['Book', 'Inspection', 'Fuel', 'Pool']) ...[
              Expanded(child: FgQuickAction(icon: FgIcons.tasks, label: l, onTap: () {})),
              if (l != 'Pool') const SizedBox(width: FgSpace.s2),
            ],
          ]),
          const SizedBox(height: FgSpace.s3),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () {}, child: const FgFitLabel('Decline'))),
            const SizedBox(width: FgSpace.s2),
            Expanded(child: OutlinedButton(onPressed: () {}, child: const FgFitLabel('Other time'))),
            const SizedBox(width: FgSpace.s2),
            Expanded(child: FilledButton(onPressed: () {}, child: const FgFitLabel('Confirm'))),
          ]),
          const SizedBox(height: FgSpace.s3),
          SectionCard(title: 'Handover history', icon: FgIcons.history, children: [
            FgTimeline(showDate: true, entries: [
              FgTimelineEntry(title: 'Customer → Gate', subtitle: 'HO-000007 · Qurtoba workshop · New Driver 029805 (Test)', time: DateTime(2026, 11, 13, 22, 15), trailing: const StatusPill('Accepted', dense: true), tone: FgTone.good),
              FgTimelineEntry(title: 'Gate → Reception', subtitle: 'HO-000008 · Service advisor (PW)', time: DateTime(2026, 11, 13, 22, 20), trailing: const StatusPill('Accepted', dense: true), tone: FgTone.good),
            ]),
          ]),
        ]),
      ),
    );
  });

  testWidgets('sign-in when the server cannot be reached', tags: 'gallery', (tester) async {
    await shot(tester, 'signin', () => const SizedBox(height: 1700, child: DevSignInScreen(title: 'Fleet Geeks Workshop', portal: 'workshop')));
  });
}
