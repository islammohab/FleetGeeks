import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'auth.dart';

/// Offline engine. Workshop commands (job start / pause / finish, checklist answers, QC, handover responses) are sent
/// at once when the network is up. When it is not, they are stored in a local SQLite outbox with their Idempotency-Key
/// (and job command id), and replayed in the original order when the connection returns. Because every command carries
/// its key, a command that reached the server before the connection dropped is never executed twice.
/// A command the server refuses (business rule) stops being retried and is shown to the user to review or discard.
class OutboxItem {
  OutboxItem({
    required this.id,
    required this.method,
    required this.path,
    required this.body,
    required this.key,
    required this.label,
    required this.attempts,
    required this.status,
    required this.createdAt,
    this.lastError,
  });

  factory OutboxItem.fromDb(Map<String, Object?> m) => OutboxItem(
        id: m['id']! as int,
        method: m['method']! as String,
        path: m['path']! as String,
        body: m['body'] as String?,
        key: m['idem']! as String,
        label: m['label']! as String,
        attempts: m['attempts']! as int,
        status: m['status']! as String,
        createdAt: DateTime.parse(m['created_at']! as String),
        lastError: m['last_error'] as String?,
      );

  final int id;
  final String method;
  final String path;
  final String? body;
  final String key;
  final String label;
  final int attempts;
  final String status; // pending | failed
  final DateTime createdAt;
  final String? lastError;

  bool get failed => status == 'failed';
}

enum SubmitOutcome { sent, queued }

class SubmitResult {
  const SubmitResult(this.outcome, [this.response]);
  final SubmitOutcome outcome;
  final dynamic response;
  bool get queued => outcome == SubmitOutcome.queued;
}

class OutboxStore {
  Database? _db;

  Future<Database> get db async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'fleetgeeks_outbox.db'),
        version: 1,
        onCreate: (d, v) => d.execute('CREATE TABLE outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, method TEXT NOT NULL, path TEXT NOT NULL, '
            'body TEXT, idem TEXT NOT NULL UNIQUE, label TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, '
            'last_error TEXT, created_at TEXT NOT NULL)'),
      );

  Future<void> add(String method, String path, Object? body, String key, String label) async {
    await (await db).insert(
      'outbox',
      {'method': method, 'path': path, 'body': body == null ? null : jsonEncode(body), 'idem': key, 'label': label, 'status': 'pending', 'created_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<OutboxItem>> all() async => (await (await db).query('outbox', orderBy: 'id')).map(OutboxItem.fromDb).toList();

  Future<void> remove(int id) async => (await db).delete('outbox', where: 'id = ?', whereArgs: [id]);

  Future<void> mark(int id, String status, String? error) async =>
      (await db).rawUpdate('UPDATE outbox SET status = ?, last_error = ?, attempts = attempts + 1 WHERE id = ?', [status, error, id]);
}

class OutboxNotifier extends AsyncNotifier<List<OutboxItem>> {
  final _store = OutboxStore();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _flushing = false;

  @override
  Future<List<OutboxItem>> build() async {
    _subscription ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) unawaited(flush());
    });
    ref.onDispose(() => _subscription?.cancel());
    return _store.all();
  }

  /// Sends a command now, or keeps it for later when the network is not reachable. Business rejections are thrown.
  Future<SubmitResult> submit(String path, {Object? body, required String label, String method = 'POST', String? key}) async {
    final idempotencyKey = key ?? const Uuid().v4();
    final pending = (await _store.all()).where((i) => !i.failed).isNotEmpty;
    if (!pending) {
      try {
        final response = await ref.read(apiProvider).send(method, path, body: body ?? const <String, Object?>{}, idempotencyKey: idempotencyKey);
        return SubmitResult(SubmitOutcome.sent, response);
      } on ApiException catch (e) {
        if (!e.isNetwork) rethrow;
      }
    }
    // Keep order: once something is waiting, later commands wait behind it.
    await _store.add(method, path, body, idempotencyKey, label);
    state = AsyncData(await _store.all());
    return const SubmitResult(SubmitOutcome.queued);
  }

  /// Replays waiting commands in order; stops at the first network failure.
  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      for (final item in await _store.all()) {
        if (item.failed) continue;
        try {
          await ref.read(apiProvider).send(item.method, item.path, body: item.body == null ? null : jsonDecode(item.body!), idempotencyKey: item.key);
          await _store.remove(item.id);
          sent++;
        } on ApiException catch (e) {
          if (e.isNetwork) break;
          await _store.mark(item.id, 'failed', e.message);
        }
      }
    } finally {
      _flushing = false;
      state = AsyncData(await _store.all());
    }
    return sent;
  }

  Future<void> retry(OutboxItem item) async {
    await _store.mark(item.id, 'pending', null);
    await flush();
  }

  Future<void> discard(OutboxItem item) async {
    await _store.remove(item.id);
    state = AsyncData(await _store.all());
  }
}

final outboxProvider = AsyncNotifierProvider<OutboxNotifier, List<OutboxItem>>(OutboxNotifier.new);
