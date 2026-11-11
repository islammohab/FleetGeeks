/// Pure-Dart status rules shared by both apps (no Flutter import, unit-tested in test/core_test.dart).
library;

/// Semantic tone of a D365 status symbol (design/tokens.json → color.status).
enum FgTone { neutral, info, progress, attention, good, bad }

const Set<String> _good = {
  'Valid', 'Pass', 'Green', 'Sent', 'Available', 'Active', 'Approved', 'Completed', 'QCPassed', 'Released',
  'ReadyForCollection', 'Accepted', 'Issued', 'Confirmed', 'Returned', 'NotDue', 'Paid', 'Delivered',
};
const Set<String> _progress = {
  'InProgress', 'InDiagnosis', 'Received', 'Arrived', 'Booked', 'Reserved', 'Submitted', 'CheckedOut', 'Assigned',
  'InRepair', 'QualityCheck', 'OnTheWay', 'Open',
};
const Set<String> _attention = {
  'Defects', 'Amber', 'Pending', 'AwaitingApproval', 'AwaitingParts', 'Paused', 'Backordered', 'Offered', 'Due',
  'DueSoon', 'Requested', 'Proposed', 'Held', 'UnderMaintenance', 'HighConsumption', 'Medium', 'High', 'Draft',
};
const Set<String> _bad = {
  'Unsafe', 'Red', 'SafetyHold', 'Declined', 'Rejected', 'QCFailed', 'Rework', 'Overdue', 'Expired', 'NoShow',
  'OdometerRollback', 'OverTank', 'Critical', 'Accident', 'Theft', 'Vandalism',
};
const Set<String> _info = {
  'Authorized', 'Preventive', 'Corrective', 'Inspection', 'Low', 'Pickup', 'Delivery', 'Replacement', 'Roadside',
  'TrafficFine', 'Toll', 'Breakdown',
};

/// One mapping for every Fleet Geeks status symbol; unknown symbols are neutral.
FgTone toneOf(String symbol) {
  if (_good.contains(symbol)) return FgTone.good;
  if (_bad.contains(symbol)) return FgTone.bad;
  if (_attention.contains(symbol)) return FgTone.attention;
  if (_progress.contains(symbol)) return FgTone.progress;
  if (_info.contains(symbol)) return FgTone.info;
  return FgTone.neutral;
}

/// The ten customer-facing stages of a service order, in order. Labels: i18n keys `stage<Key>`.
const List<String> orderStages = [
  'Requested', 'Confirmed', 'Arrived', 'Received', 'Diagnosis', 'AwaitingApproval', 'InProgress', 'QualityCheck',
  'Ready', 'Released',
];

/// Index in [orderStages] for a service order (or appointment) status; -1 for Cancelled / unknown.
int orderStageIndex(String status) => switch (status) {
      'Draft' || 'Requested' || 'Held' => 0,
      'Booked' || 'Confirmed' => 1,
      'Arrived' => 2,
      'Received' => 3,
      'InDiagnosis' => 4,
      'AwaitingApproval' => 5,
      'InProgress' || 'AwaitingParts' || 'Rework' => 6,
      'QualityCheck' => 7,
      'ReadyForCollection' => 8,
      'Released' || 'Closed' => 9,
      _ => -1,
    };

/// Open = still in the workshop flow (not released, closed or cancelled).
bool isOrderOpen(String status) => !const {'Released', 'Closed', 'Cancelled'}.contains(status);

/// Distance from now to a promise: minutes under an hour, hours under two days, otherwise days.
/// [overdue] is true when the promise has passed.
({int value, String unit, bool overdue}) promiseDelta(DateTime promise, DateTime now) {
  final diff = promise.difference(now);
  final overdue = diff.isNegative;
  final minutes = diff.inMinutes.abs();
  if (minutes < 60) return (value: minutes, unit: 'm', overdue: overdue);
  final hours = (minutes / 60).floor();
  if (hours < 48) return (value: hours, unit: 'h', overdue: overdue);
  return (value: (hours / 24).floor(), unit: 'd', overdue: overdue);
}

/// Initials for an avatar ("Sara Al Harbi" → "SA", "demo.tech@example.com" → "DT").
String initialsOf(String name) {
  final words = name.split(RegExp(r'[\s._@-]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, words.first.length < 2 ? words.first.length : 2).toUpperCase();
  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

/// Kind of placeholder illustration for a vehicle class id (free text master in D365, e.g. "LCV", "HGV-18T", "SEDAN").
enum FgVehicleKind { car, suv, van, pickup, truck, bus, bike, equipment }

FgVehicleKind vehicleKindOf(String vehicleClass) {
  final c = vehicleClass.toUpperCase();
  bool any(List<String> words) => words.any(c.contains);
  if (any(['BUS', 'COACH'])) return FgVehicleKind.bus;
  if (any(['HGV', 'TRUCK', 'LORRY', 'TRACTOR', 'TRAILER', 'HEAVY', 'TIPPER', 'TANKER'])) return FgVehicleKind.truck;
  if (any(['PICK'])) return FgVehicleKind.pickup;
  if (any(['VAN', 'LCV', 'MPV'])) return FgVehicleKind.van;
  if (any(['SUV', '4X4', 'JEEP', 'CROSS'])) return FgVehicleKind.suv;
  if (any(['BIKE', 'MOTO', 'SCOOTER'])) return FgVehicleKind.bike;
  if (any(['FORK', 'EQUIP', 'PLANT', 'LOADER', 'CRANE', 'GENSET'])) return FgVehicleKind.equipment;
  return FgVehicleKind.car;
}
