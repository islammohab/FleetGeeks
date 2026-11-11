import 'package:fg_core/fg_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Arabic has every English key, no empty text and the same placeholders', () {
    final count = RegExp(r'\{\d\}');
    for (final key in en.keys) {
      expect(ar.containsKey(key), isTrue, reason: key);
      expect(en[key]!.trim(), isNotEmpty, reason: key);
      expect(ar[key]!.trim(), isNotEmpty, reason: key);
      expect(count.allMatches(ar[key]!).length, count.allMatches(en[key]!).length, reason: key);
    }
    expect(ar.length, en.length);
  });

  test('keys built at run time exist (stages, next steps, units, service types, board hints)', () {
    for (final stage in orderStages) {
      expect(en.containsKey('stage$stage'), isTrue, reason: 'stage$stage');
      expect(en.containsKey('next$stage'), isTrue, reason: 'next$stage');
    }
    for (final unit in ['m', 'h', 'd']) {
      expect(en.containsKey('unit_$unit'), isTrue, reason: unit);
    }
    for (final t in ['Preventive', 'Corrective', 'Inspection']) {
      expect(en.containsKey('svc$t'), isTrue, reason: t);
    }
    expect(en.containsKey('atRiskPromisesHint') && en.containsKey('releaseBlockersHint'), isTrue);
  });

  test('status symbols are split into words', () {
    expect(splitWords('ReadyForCollection'), 'Ready For Collection');
    expect(const Strings('ar').status('Released'), 'تم الخروج');
  });

  test('one tone per status symbol', () {
    expect(toneOf('Released'), FgTone.good);
    expect(toneOf('ReadyForCollection'), FgTone.good);
    expect(toneOf('InProgress'), FgTone.progress);
    expect(toneOf('AwaitingApproval'), FgTone.attention);
    expect(toneOf('QCFailed'), FgTone.bad);
    expect(toneOf('SafetyHold'), FgTone.bad);
    expect(toneOf('Authorized'), FgTone.info);
    expect(toneOf('SomethingNew'), FgTone.neutral);
    expect(toneOf(''), FgTone.neutral);
  });

  test('every status tone has a colour pair in light and dark', () {
    for (final tokens in [FgTokens.light, FgTokens.dark]) {
      for (final tone in FgTone.values) {
        final c = tokens.tone(tone);
        expect(c.fg, isNot(c.bg), reason: '$tone');
      }
    }
    expect(statusColor('Released'), FgTokens.light.success);
    expect(statusColor('QCFailed', Brightness.dark), FgTokens.dark.danger);
  });

  test('service order stages are derived from the D365 status', () {
    expect(orderStages.length, 10);
    expect(orderStageIndex('Requested'), 0);
    expect(orderStageIndex('Booked'), 1);
    expect(orderStageIndex('Arrived'), 2);
    expect(orderStageIndex('Received'), 3);
    expect(orderStageIndex('InDiagnosis'), 4);
    expect(orderStageIndex('AwaitingApproval'), 5);
    expect(orderStageIndex('AwaitingParts'), 6);
    expect(orderStageIndex('Rework'), 6);
    expect(orderStageIndex('QualityCheck'), 7);
    expect(orderStageIndex('ReadyForCollection'), 8);
    expect(orderStageIndex('Closed'), 9);
    expect(orderStageIndex('Cancelled'), -1);
    expect(isOrderOpen('InProgress'), isTrue);
    expect(isOrderOpen('Released'), isFalse);
    expect(isOrderOpen('Cancelled'), isFalse);
  });

  test('promise countdown uses minutes, hours or days', () {
    final now = DateTime(2026, 11, 10, 12);
    expect(promiseDelta(now.add(const Duration(minutes: 30)), now), (value: 30, unit: 'm', overdue: false));
    expect(promiseDelta(now.add(const Duration(hours: 5)), now), (value: 5, unit: 'h', overdue: false));
    expect(promiseDelta(now.subtract(const Duration(hours: 3)), now), (value: 3, unit: 'h', overdue: true));
    expect(promiseDelta(now.add(const Duration(days: 4)), now), (value: 4, unit: 'd', overdue: false));
    expect(promiseText(const Strings('en'), now.add(const Duration(hours: 2)), now: now), 'in 2 h');
    expect(promiseText(const Strings('en'), now.subtract(const Duration(days: 3)), now: now), '3 d late');
    expect(promiseText(const Strings('en'), null), '');
  });

  test('numbers keep Western digits and grouping in both languages', () {
    expect(fmtNum(1234567), '1,234,567');
    expect(fmtNum(12.5, decimals: 2), '12.50');
    expect(fmtMoney(1500, 'SAR'), '1,500.00 SAR');
    expect(fmtKm(84213), '84,213 km');
  });

  test('vehicle class ids map to a placeholder illustration', () {
    expect(vehicleKindOf('HGV-18T'), FgVehicleKind.truck);
    expect(vehicleKindOf('LCV'), FgVehicleKind.van);
    expect(vehicleKindOf('City bus'), FgVehicleKind.bus);
    expect(vehicleKindOf('PICKUP'), FgVehicleKind.pickup);
    expect(vehicleKindOf('SUV'), FgVehicleKind.suv);
    expect(vehicleKindOf('FORKLIFT'), FgVehicleKind.equipment);
    expect(vehicleKindOf('SEDAN'), FgVehicleKind.car);
    expect(vehicleKindOf(''), FgVehicleKind.car);
  });

  test('avatar initials', () {
    expect(initialsOf('Sara Al Harbi'), 'SA');
    expect(initialsOf('demo.tech@example.com'), 'DT');
    expect(initialsOf('X'), 'X');
    expect(initialsOf(''), '?');
  });

  test('signature controller records strokes and undo / clear', () {
    final c = SignatureController();
    expect(c.isEmpty, isTrue);
    c.begin(const Offset(1, 1));
    c.extend(const Offset(5, 5));
    c.begin(const Offset(10, 10));
    expect(c.strokes.length, 2);
    c.undo();
    expect(c.strokes.length, 1);
    c.clear();
    expect(c.isEmpty, isTrue);
    c.dispose();
  });

  test('image evidence is recognised by content type or file name', () {
    expect(isImageEvidence({'ContentType': 'image/jpeg'}), isTrue);
    expect(isImageEvidence({'ContentType': '', 'FileName': 'IMG_1.PNG'}), isTrue);
    expect(isImageEvidence({'ContentType': 'application/pdf', 'FileName': 'report.pdf'}), isFalse);
  });

  test('cycle helpers read entity (PascalCase) and API (camelCase) rows', () {
    final FgRow entity = {'Status': 'Proposed', 'ProposedStart': '2026-11-12T08:00:00Z', 'StartDateTime': '1900-01-01T00:00:00Z'};
    final FgRow api = {'status': 'Requested', 'proposedStart': '2026-11-13T09:30:00Z'};
    expect(rowField(entity, 'Status'), 'Proposed');
    expect(rowField(api, 'Status'), 'Requested');
    expect(rowDate(entity, 'ProposedStart'), isNotNull);
    expect(rowDate(api, 'ProposedStart'), isNotNull);
    expect(rowDate(entity, 'StartDateTime'), isNull);
    expect(unreadByOrder({'total': 3, 'orders': [{'serviceOrderId': 'SO-1', 'unread': 2}, {'serviceOrderId': 'SO-2', 'unread': 1}]}), {'SO-1': 2, 'SO-2': 1});
    expect(unreadByOrder(null), isEmpty);
    expect(messagesPath('SO 1'), '/service-orders/SO%201/messages');
  });

  test('order event types get an icon by keyword', () {
    expect(FgIcons.orderEvent('MessagePosted'), FgIcons.message);
    expect(FgIcons.orderEvent('DocumentReady'), FgIcons.document);
    expect(FgIcons.orderEvent('EstimateSent'), FgIcons.estimate);
    expect(FgIcons.orderEvent('SomethingElse'), isNotNull);
  });

  test('role delegation dates are honoured', () {
    final user = PortalUser(portalUserId: 'u', userType: 'Customer', contactName: 'U', roles: [
      PortalRole(role: 'RepairApprover', validTo: DateTime(2000)),
      const PortalRole(role: 'Driver'),
    ]);
    expect(user.has(['RepairApprover']), isFalse);
    expect(user.has(['Driver']), isTrue);
  });

  test('D365 empty dates are null', () {
    final FgRow r = {'D': '1900-01-01T00:00:00Z', 'E': '2026-11-09T10:00:00Z'};
    expect(r.d('D'), isNull);
    expect(r.d('E'), isNotNull);
  });

  test('API URL drops empty query values', () {
    final api = ApiClient(baseUrl: 'http://h', tokenProvider: () async => null);
    expect(api.uri('/workshops/W/slots', {'vehicleId': 'V 1', 'x': '', 'y': null}).toString(), 'http://h/api/v1/workshops/W/slots?vehicleId=V+1');
  });

  test('themes are built from the tokens in light and dark, for both languages', () {
    for (final b in Brightness.values) {
      for (final lang in ['en', 'ar']) {
        final theme = fgTheme(b, lang: lang);
        final tokens = b == Brightness.dark ? FgTokens.dark : FgTokens.light;
        expect(theme.colorScheme.primary, tokens.primary);
        expect(theme.colorScheme.secondary, tokens.action);
        expect(theme.extension<FgTokens>(), isNotNull);
        expect(theme.textTheme.bodyMedium?.fontFamily, lang == 'ar' ? FgFonts.arabic : FgFonts.latin);
      }
    }
  });
}
