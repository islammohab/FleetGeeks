/// D365 portal user (FGPortalUserTable + FGPortalUserRole) as returned by GET /api/v1/me.
class PortalRole {
  const PortalRole({required this.role, this.approvalLimit = 0, this.currency, this.validFrom, this.validTo});

  factory PortalRole.fromJson(Map<String, dynamic> j) => PortalRole(
        role: '${j['role']}',
        approvalLimit: (j['approvalLimit'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] as String?,
        validFrom: _date(j['validFrom']),
        validTo: _date(j['validTo']),
      );

  final String role;
  final double approvalLimit;
  final String? currency;
  final DateTime? validFrom;
  final DateTime? validTo;

  bool validOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return (validFrom == null || !validFrom!.isAfter(d)) && (validTo == null || !validTo!.isBefore(d));
  }

  static DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');
}

class PortalUser {
  const PortalUser({
    required this.portalUserId,
    required this.userType,
    required this.contactName,
    this.custAccount,
    this.vendAccount,
    this.driverId,
    this.roles = const [],
  });

  factory PortalUser.fromJson(Map<String, dynamic> j) => PortalUser(
        portalUserId: '${j['portalUserId']}',
        userType: '${j['userType']}',
        contactName: '${j['contactName'] ?? j['portalUserId']}',
        custAccount: j['custAccount'] as String?,
        vendAccount: j['vendAccount'] as String?,
        driverId: j['driverId'] as String?,
        roles: ((j['roles'] as List?) ?? const []).map((r) => PortalRole.fromJson(Map<String, dynamic>.from(r as Map))).toList(),
      );

  final String portalUserId;
  final String userType;
  final String contactName;
  final String? custAccount;
  final String? vendAccount;
  final String? driverId;
  final List<PortalRole> roles;

  bool get isWorkshopStaff => userType == 'WorkshopStaff';
  bool get isPartner => userType == 'Partner';
  bool get isCustomerSide => userType == 'Customer' || userType == 'Driver' || userType == 'InternalFleet';

  bool has(List<String> any) {
    final today = DateTime.now();
    return roles.any((r) => any.contains(r.role) && r.validOn(today));
  }
}

/// D365 entity rows keep their PascalCase field names.
typedef FgRow = Map<String, dynamic>;

extension FgRowValues on FgRow {
  String s(String field) => this[field] == null ? '' : '${this[field]}';
  double n(String field) => (this[field] is num) ? (this[field] as num).toDouble() : double.tryParse(s(field)) ?? 0;

  /// D365 empty dates come back as 1900-01-01.
  DateTime? d(String field) {
    final v = s(field);
    if (v.isEmpty || v.startsWith('1900-01-01')) return null;
    return DateTime.tryParse(v)?.toLocal();
  }
}

List<FgRow> asRows(Object? json) => ((json as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
FgRow asRow(Object? json) => Map<String, dynamic>.from((json as Map?) ?? const {});
