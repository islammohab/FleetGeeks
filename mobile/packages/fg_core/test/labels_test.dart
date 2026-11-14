import 'dart:io';

import 'package:fg_core/fg_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every label key written in the code must exist in English and Arabic, so a screen can never show a missing label.
void main() {
  test('every key used with t(...) in the apps and the shared package exists in en and ar', () {
    final roots = [Directory('lib'), Directory('../../apps/workshop_app/lib'), Directory('../../apps/customer_app/lib')];
    final call = RegExp(r"\.t\(\s*'([A-Za-z0-9_.]+)'");
    final missing = <String>{};
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final f in root.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('i18n.dart')) continue;
        for (final m in call.allMatches(f.readAsStringSync())) {
          final key = m.group(1)!;
          if (!en.containsKey(key) || !ar.containsKey(key)) missing.add('$key (${f.path})');
        }
      }
    }
    expect(missing, isEmpty, reason: 'Label keys without a text:\n${missing.join('\n')}');
  });

  test('the workshop next-step card has a text for every step of the model', () {
    for (final step in [...orderSteps, 'Cancelled']) {
      final suffix = orderStepSuffix[step]!;
      expect(en.containsKey('wsNext$suffix') && ar.containsKey('wsNext$suffix'), isTrue, reason: 'wsNext$suffix');
    }
    for (final actor in orderActorKey.values) {
      expect(en.containsKey(actor) && ar.containsKey(actor), isTrue, reason: actor);
    }
  });
}
