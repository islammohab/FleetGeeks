import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'status.dart';

/// The Fleet Geeks icon map (Lucide, regular weight). Screens use only these names, so the icon set can be changed
/// in one place. `*Dir` icons mirror automatically in right-to-left (Arabic).
class FgIcons {
  const FgIcons._();

  // Navigation
  static const home = LucideIcons.house;
  static const vehicles = LucideIcons.car;
  static const book = LucideIcons.calendarPlus;
  static const orders = LucideIcons.clipboardList;
  static const more = LucideIcons.layoutGrid;
  static const board = LucideIcons.squareKanban;
  static const gate = LucideIcons.scanQrCode;
  static const tasks = LucideIcons.wrench;
  static const parts = LucideIcons.package;
  static const mobility = LucideIcons.truck;
  static const outbox = LucideIcons.cloudUpload;

  // Features
  static const inspection = LucideIcons.clipboardCheck;
  static const compliance = LucideIcons.shieldCheck;
  static const fuel = LucideIcons.fuel;
  static const incident = LucideIcons.siren;
  static const pool = LucideIcons.keyRound;
  static const fault = LucideIcons.triangleAlert;
  static const healthCheck = LucideIcons.heartPulse;
  static const damage = LucideIcons.carFront;
  static const checklist = LucideIcons.listChecks;
  static const qc = LucideIcons.badgeCheck;
  static const handover = LucideIcons.handshake;
  static const estimate = LucideIcons.receipt;
  static const promise = LucideIcons.calendarClock;
  static const history = LucideIcons.history;
  static const odometer = LucideIcons.gauge;
  static const workshop = LucideIcons.building2;
  static const location = LucideIcons.mapPin;
  static const driver = LucideIcons.user;
  static const users = LucideIcons.users;
  static const signature = LucideIcons.signature;
  static const qr = LucideIcons.qrCode;
  static const document = LucideIcons.fileText;
  static const timeline = LucideIcons.activity;

  // Actions
  static const camera = LucideIcons.camera;
  static const photo = LucideIcons.image;
  static const gallery = LucideIcons.images;
  static const scan = LucideIcons.scanLine;
  static const start = LucideIcons.play;
  static const pause = LucideIcons.pause;
  static const finish = LucideIcons.circleCheckBig;
  static const check = LucideIcons.check;
  static const close = LucideIcons.x;
  static const add = LucideIcons.plus;
  static const search = LucideIcons.search;
  static const refresh = LucideIcons.refreshCw;
  static const send = LucideIcons.send;
  static const delete = LucideIcons.trash2;
  static const retry = LucideIcons.rotateCcw;
  static const undo = LucideIcons.undo2;
  static const calendar = LucideIcons.calendarDays;
  static const clock = LucideIcons.clock;
  static const time = LucideIcons.timer;
  static const language = LucideIcons.languages;
  static const signOut = LucideIcons.logOut;
  static const signIn = LucideIcons.logIn;
  static const settings = LucideIcons.settings;
  static const info = LucideIcons.info;
  static const route = LucideIcons.route;
  static const release = LucideIcons.logOut;
  static const admit = LucideIcons.logIn;
  static const flashlight = LucideIcons.flashlight;
  static const approve = LucideIcons.thumbsUp;
  static const decline = LucideIcons.thumbsDown;
  static const eye = LucideIcons.eye;
  static const compare = LucideIcons.chevronsLeftRight;

  // Maintenance cycle (bookings, messages, documents, payments, service book)
  static const messages = LucideIcons.messagesSquare;
  static const message = LucideIcons.messageSquare;
  static const payment = LucideIcons.creditCard;
  static const wallet = LucideIcons.wallet;
  static const download = LucideIcons.fileDown;
  static const external = LucideIcons.externalLink;
  static const serviceBook = LucideIcons.bookOpenCheck;
  static const star = LucideIcons.star;
  static const verify = LucideIcons.idCard;
  static const scanPhoto = LucideIcons.scanEye;
  static const proposal = LucideIcons.calendarSync;
  static const declined = LucideIcons.calendarX;
  static const technician = LucideIcons.hardHat;
  static const channel = LucideIcons.bell;
  static const phone = LucideIcons.phone;
  static const deliveryCheck = LucideIcons.clipboardCheck;

  /// Icon of a D365 order event type (FGOrderEventType) by keyword, so new event types still get a sensible icon.
  static IconData orderEvent(String type) {
    final t = type.toLowerCase();
    bool has(String w) => t.contains(w);
    if (has('message')) return message;
    if (has('document') || has('report') || has('note')) return document;
    if (has('pay') || has('invoice')) return wallet;
    if (has('photo') || has('evidence')) return camera;
    if (has('estimate') || has('approv') || has('declin')) return estimate;
    if (has('qc') || has('quality')) return qc;
    if (has('handover') || has('custody') || has('sign')) return handover;
    if (has('arriv') || has('receiv') || has('gate')) return LucideIcons.logIn;
    if (has('release') || has('deliver')) return LucideIcons.logOut;
    if (has('ready')) return LucideIcons.flag;
    if (has('promise') || has('delay')) return promise;
    if (has('book') || has('confirm') || has('propos')) return LucideIcons.calendarCheck;
    if (has('job') || has('work') || has('start') || has('finish') || has('pause')) return tasks;
    if (has('part')) return parts;
    if (has('check')) return checklist;
    return LucideIcons.circleDot;
  }

  // Directional (mirror in RTL)
  static const chevronForward = LucideIcons.chevronRightDir;
  static const chevronBack = LucideIcons.chevronLeftDir;
  static const arrowForward = LucideIcons.arrowRightDir;
  static const arrowBack = LucideIcons.arrowLeftDir;

  // Connectivity
  static const offline = LucideIcons.cloudOff;
  static const synced = LucideIcons.cloudCheck;
  static const waiting = LucideIcons.hourglass;

  // Status / tone
  static const good = LucideIcons.circleCheck;
  static const bad = LucideIcons.circleX;
  static const attention = LucideIcons.circleAlert;
  static const progress = LucideIcons.circleDot;
  static const neutral = LucideIcons.circleDashed;
  static const warning = LucideIcons.triangleAlert;
  static const danger = LucideIcons.octagonAlert;
  static const safety = LucideIcons.shieldAlert;

  /// Icon of a status symbol: specific symbols first, otherwise the icon of its tone.
  static IconData status(String symbol) => switch (symbol) {
        'InProgress' || 'InRepair' => LucideIcons.wrench,
        'Paused' => LucideIcons.circlePause,
        'AwaitingParts' || 'Backordered' => LucideIcons.packageX,
        'AwaitingApproval' || 'Submitted' || 'Offered' => LucideIcons.hourglass,
        'QualityCheck' || 'QCPassed' => LucideIcons.badgeCheck,
        'ReadyForCollection' => LucideIcons.flag,
        'Released' || 'Returned' => LucideIcons.logOut,
        'Arrived' || 'Received' => LucideIcons.logIn,
        'Booked' || 'Confirmed' || 'Reserved' => LucideIcons.calendarCheck,
        'Requested' || 'Proposed' || 'Held' => LucideIcons.calendarClock,
        'InDiagnosis' || 'Inspection' => LucideIcons.stethoscope,
        'SafetyHold' || 'Unsafe' => LucideIcons.shieldAlert,
        'UnderMaintenance' => LucideIcons.construction,
        'CheckedOut' => LucideIcons.keyRound,
        'Assigned' || 'OnTheWay' => LucideIcons.truck,
        'Expired' || 'Overdue' => LucideIcons.calendarX,
        'DueSoon' || 'Due' => LucideIcons.calendarClock,
        'Issued' => LucideIcons.packageCheck,
        _ => switch (toneOf(symbol)) {
            FgTone.good => good,
            FgTone.bad => bad,
            FgTone.attention => attention,
            FgTone.progress => progress,
            FgTone.info => info,
            FgTone.neutral => neutral,
          },
      };

  /// Icon of a vehicle kind (class placeholder).
  static IconData vehicleKind(FgVehicleKind kind) => switch (kind) {
        FgVehicleKind.car => LucideIcons.carFront,
        FgVehicleKind.suv => LucideIcons.car,
        FgVehicleKind.van => LucideIcons.van,
        FgVehicleKind.pickup => LucideIcons.truck,
        FgVehicleKind.truck => LucideIcons.truck,
        FgVehicleKind.bus => LucideIcons.bus,
        FgVehicleKind.bike => LucideIcons.bike,
        FgVehicleKind.equipment => LucideIcons.forklift,
      };

  static IconData vehicleClass(String vehicleClass) => vehicleKind(vehicleKindOf(vehicleClass));

  /// Icon of a timeline / activity event kind.
  static IconData event(String kind) => switch (kind) {
        'arrived' => LucideIcons.logIn,
        'estimate' => estimate,
        'decision' => LucideIcons.squareCheckBig,
        'handover' => handover,
        'photo' => camera,
        'promise' => promise,
        'qc' => qc,
        'ready' => LucideIcons.flag,
        'released' => LucideIcons.logOut,
        'job' => tasks,
        'healthCheck' => healthCheck,
        'damage' => damage,
        'fuel' => fuel,
        'incident' => incident,
        'mobility' => mobility,
        'Pickup' => LucideIcons.truck,
        'Delivery' => LucideIcons.truck,
        'Replacement' => LucideIcons.keyRound,
        'Roadside' => LucideIcons.siren,
        _ => LucideIcons.circleDot,
      };
}
