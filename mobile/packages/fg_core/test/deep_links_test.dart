import 'package:fg_core/fg_core.dart';
import 'package:flutter_test/flutter_test.dart';

// D-110: deep links open only known screens of the app; anything else goes home.
void main() {
  test('portal and custom-scheme links map to app routes', () {
    expect(FgDeepLinks.route(Uri.parse('https://portal.example.com/orders/FG-SO-001')), '/orders/FG-SO-001');
    expect(FgDeepLinks.route(Uri.parse('fleetgeeks://orders/FG-SO-001/messages')), '/orders/FG-SO-001/messages');
    expect(FgDeepLinks.route(Uri.parse('https://portal.example.com/bookings/AP-1')), '/bookings/AP-1');
    expect(FgDeepLinks.route(Uri.parse('https://portal.example.com/book?vehicle=V1')), '/book?vehicle=V1');
  });

  test('unknown or unsafe paths are refused', () {
    expect(FgDeepLinks.route(Uri.parse('https://portal.example.com/admin')), isNull);
    expect(FgDeepLinks.route(Uri.parse('https://portal.example.com/orders/../../etc')), isNull);
    expect(FgDeepLinks.route(Uri.parse('fleetgeeks://evil/payload')), isNull);
  });

  test('notification records map to screens', () {
    expect(FgDeepLinks.forRecord('FGServiceOrder', 'FG-SO-001'), '/orders/FG-SO-001');
    expect(FgDeepLinks.forRecord('FGAppointment', 'AP-1'), '/bookings/AP-1');
    expect(FgDeepLinks.forRecord('FGVehicle', 'V1'), '/vehicles/V1');
    expect(FgDeepLinks.forRecord('FGComplaint', 'C-1'), isNull);
    expect(FgDeepLinks.forRecord('FGServiceOrder', ''), isNull);
  });
}