import 'package:fg_core/fg_core.dart';
import 'package:flutter_test/flutter_test.dart';

// D-109: rules of the offline queue that do not need a device (the database and the secure storage do).
void main() {
  test('financial, authorisation and release commands are never queued offline', () {
    for (final path in [
      '/estimates/EST-1/decision',
      '/workshop/approvals/APR-1/decide',
      '/service-orders/FG-SO-1/payments',
      '/payments/PAY-1/refunds',
      '/workshop/gate/release',
      '/approve/abc',
      '/workshop/gate/release-override',
      '/workshop/service-orders/FG-SO-1/credit-override',
      '/payments/PAY-1/credit-notes',
    ]) {
      expect(isCriticalCommand(path), isTrue, reason: path);
    }
    for (final path in ['/workshop/jobs/FG-SO-1/2/start', '/workshop/checklists', '/faults', '/fuel', '/vehicles/VEH-1/readings', '/workshop/handovers']) {
      expect(isCriticalCommand(path), isFalse, reason: path);
    }
  });

  test('the entity of a command is its path without the final verb, so commands on one record depend on each other', () {
    expect(outboxEntity('/workshop/jobs/FG-SO-1/2/start'), '/workshop/jobs/FG-SO-1/2');
    expect(outboxEntity('/workshop/jobs/FG-SO-1/2/pause'), '/workshop/jobs/FG-SO-1/2');
    expect(outboxEntity('/workshop/health-checks/HC-1/lines/3'), '/workshop/health-checks/HC-1/lines/3');
    expect(outboxEntity('/faults'), '/faults');
    expect(outboxEntity('/pool/bookings/PB-1/check-in?x=1'), '/pool/bookings/PB-1');
  });

  test('the queue knows its payload version', () {
    expect(outboxPayloadVersion, greaterThanOrEqualTo(2));
  });
}
