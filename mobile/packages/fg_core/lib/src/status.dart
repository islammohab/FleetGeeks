/// Pure-Dart status rules shared by both apps (no Flutter import, unit-tested in test/core_test.dart).
library;

/// Semantic tone of a D365 status symbol (design/tokens.json → color.status).
enum FgTone { neutral, info, progress, attention, good, bad }

const Set<String> _good = {
  'Valid', 'Pass', 'Green', 'Sent', 'Available', 'Active', 'Approved', 'Completed', 'QCPassed', 'Released',
  'ReadyForCollection', 'Accepted', 'Issued', 'Confirmed', 'Returned', 'NotDue', 'Paid', 'Delivered', 'ReadyForHandback',
  'WorkAccepted', 'Closed',
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

/// Prompt 2 / 3 (B1): the one status model of a service order, owned by D365 (FGStatusService) and shared with both portals
/// (web/packages/shared/src/flow.ts). The 16 steps in order, as D365 enum symbols of FGServiceOrderStatus. The enum names are
/// kept; the labels changed: Draft = Requested, Booked = Confirmed, InDiagnosis = Diagnosis, ReadyForCollection = Billing cleared.
const List<String> orderSteps = [
  'Draft', 'Booked', 'Arrived', 'Received', 'InDiagnosis', 'AwaitingApproval', 'Approved', 'InProgress', 'AwaitingParts',
  'QualityCheck', 'Rework', 'ReadyForHandback', 'WorkAccepted', 'ReadyForCollection', 'Released', 'Closed',
];

/// Steps shown only when the order reached them (side steps).
const Set<String> orderSideSteps = {'AwaitingParts', 'Rework'};

/// Label suffix of a step: i18n keys `st<Suffix>` (label) and `next<Suffix>` (what happens next).
const Map<String, String> orderStepSuffix = {
  'Draft': 'Requested', 'Booked': 'Confirmed', 'Arrived': 'Arrived', 'Received': 'Received', 'InDiagnosis': 'Diagnosis',
  'AwaitingApproval': 'AwaitingApproval', 'Approved': 'Approved', 'InProgress': 'InProgress', 'AwaitingParts': 'AwaitingParts',
  'QualityCheck': 'QualityCheck', 'Rework': 'Rework', 'ReadyForHandback': 'ReadyForHandback', 'WorkAccepted': 'WorkAccepted',
  'ReadyForCollection': 'BillingCleared', 'Released': 'Released', 'Closed': 'Closed', 'Cancelled': 'Cancelled',
};

/// Position 1-16 of a service order status in the model; 0 for Cancelled / unknown. Appointment symbols (Requested, Held,
/// Confirmed) map to steps 1 and 2.
int orderStepNumber(String status) {
  final alias = switch (status) { 'Requested' || 'Held' => 'Draft', 'Confirmed' => 'Booked', _ => status };
  return orderSteps.indexOf(alias) + 1;
}

/// State of a step: done, current, locked (not reached) or skipped (not needed for this order).
enum FlowState { done, current, locked, skipped }

FlowState _flowState(String s) => switch (s) {
      'done' => FlowState.done,
      'current' => FlowState.current,
      'skipped' => FlowState.skipped,
      _ => FlowState.locked,
    };

/// One step of the order flow (GET /service-orders/{id}/flow, or the `flow` member of the order detail).
class FlowStep {
  const FlowStep({required this.step, required this.status, required this.state, this.at, this.by = ''});
  final int step;
  final String status;
  final FlowState state;
  final DateTime? at;
  final String by;
}

/// The step model of one order from D365: current status and step, the steps with who / when, the actions D365 allows now
/// (the first is the expected next one) and the proposed promise.
class OrderFlow {
  const OrderFlow({required this.status, required this.step, required this.steps, this.allowed = const [], this.next = '', this.proposedPromise});
  final String status;
  final int step;
  final List<FlowStep> steps;
  final List<String> allowed;
  final String next;
  final DateTime? proposedPromise;

  /// Reads the API JSON; null when absent or not a flow object (older API, D365 refused).
  static OrderFlow? fromJson(Object? json) {
    if (json is! Map) return null;
    final steps = <FlowStep>[];
    for (final s in (json['steps'] is List ? json['steps'] as List : const [])) {
      if (s is! Map) continue;
      steps.add(FlowStep(
        step: (s['step'] as num?)?.toInt() ?? 0,
        status: '${s['status'] ?? ''}',
        state: _flowState('${s['state'] ?? ''}'),
        at: _date(s['at']),
        by: '${s['by'] ?? ''}',
      ));
    }
    if (steps.isEmpty && json['status'] == null) return null;
    final actions = json['allowed'] is List
        ? [for (final a in json['allowed'] as List) '$a']
        : '${json['actions'] ?? ''}'.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
    return OrderFlow(
      status: '${json['status'] ?? ''}',
      step: (json['step'] as num?)?.toInt() ?? orderStepNumber('${json['status'] ?? ''}'),
      steps: steps,
      allowed: actions,
      next: '${json['next'] ?? (actions.isEmpty ? '' : actions.first)}',
      proposedPromise: _date(json['proposedPromise']),
    );
  }

  /// D365 allows the action now.
  bool can(String action) => allowed.contains(action);
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  final d = DateTime.tryParse('$v');
  // the empty D365 date (1900-01-01) means "not reached"
  return d == null || d.year <= 1900 ? null : d.toLocal();
}

/// Steps without D365 data (order loaded before the flow): states derived from the status alone.
List<FlowStep> stepsFromStatus(String status) {
  final current = orderStepNumber(status);
  return [
    for (var i = 0; i < orderSteps.length; i++)
      FlowStep(step: i + 1, status: orderSteps[i], state: i + 1 < current ? FlowState.done : (i + 1 == current ? FlowState.current : FlowState.locked)),
  ];
}

/// View of a step on the visible track.
enum TrackView { done, current, upcoming, alert }

/// The track both apps show (same rule as the portals): from D365 when available, otherwise from the status; side steps
/// (awaiting parts, rework) only when reached, skipped steps left out.
List<(FlowStep, TrackView)> trackSteps(OrderFlow? flow, String status) {
  final cancelled = status == 'Cancelled';
  final all = (flow != null && flow.steps.isNotEmpty) ? flow.steps : stepsFromStatus(status);
  return [
    for (final s in all)
      if (s.state != FlowState.skipped && !(s.state == FlowState.locked && orderSideSteps.contains(s.status)))
        (
          s,
          cancelled
              ? TrackView.upcoming
              : switch (s.state) {
                  FlowState.done => TrackView.done,
                  FlowState.current => orderSideSteps.contains(s.status)
                      ? TrackView.alert
                      : (s.status == 'Released' || s.status == 'Closed' ? TrackView.done : TrackView.current),
                  _ => TrackView.upcoming,
                },
        ),
  ];
}

/// An action is offered only when D365 allows it now; without flow data the app falls back to offering it (the API check
/// stays the rule).
bool flowAllows(OrderFlow? flow, String action) => flow == null || (flow.allowed.isEmpty && flow.steps.isEmpty) || flow.can(action);

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
