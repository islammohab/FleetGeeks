import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'auth.dart';

/// Offline engine (wave 5, brief 27, D-109). Workshop and driver commands are sent at once when the network is up. When it
/// is not, they are stored in a local SQLite outbox and replayed in the original order when the connection returns.
///
/// Every queued command carries: command ID (its Idempotency-Key, so a command that reached the server before the
/// connection dropped is never executed twice), scope (the signed-in user), entity, operation, payload version, created
/// time, dependency (the earlier queued command on the same entity), attempts, last error and state.
///
/// * The request body is encrypted (AES-GCM 256) with a key generated on the device and kept in the platform secure
///   storage (Android Keystore / iOS Keychain); nothing sensitive is stored in clear and no key is in the source.
/// * Expired session (401): commands stay queued for the same user and are sent after sign-in.
/// * Revoked access (403) or a business refusal: the command is marked failed and never retried automatically.
/// * Stale version / conflicting server state (409): the command is marked conflict and waits for the user (open the
///   record, then retry with a new key or discard) - nothing is merged automatically.
/// * A command whose dependency failed or is in conflict is blocked until that one is resolved.
/// * Financial, authorisation and release commands are never queued: they need a connection at the moment of decision.
/// * Sign-out wipes the outbox and destroys the key; signing in as another user drops the previous user's commands.
/// * D-110: photos taken offline are queued too (method UPLOAD): the file is kept encrypted with the same key in the app's
///   private folder, replayed in order with its Idempotency-Key (a repeated upload never creates a second evidence) and
///   deleted after it was sent, discarded or on sign-out.
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
    required this.scope,
    required this.entity,
    required this.operation,
    required this.payloadVersion,
    this.dependsOn,
    this.lastError,
  });

  final int id;
  final String method;
  final String path;

  /// Decrypted JSON body (only in memory).
  final String? body;
  final String key;
  final String label;
  final int attempts;

  /// pending | failed | conflict | blocked
  final String status;
  final DateTime createdAt;
  final String scope;
  final String entity;
  final String operation;
  final int payloadVersion;
  final String? dependsOn;
  final String? lastError;

  bool get failed => status == 'failed';
  bool get conflict => status == 'conflict';
  bool get blocked => status == 'blocked';

  /// Needs a decision of the user (refused, conflict or blocked behind one of those).
  bool get needsReview => status != 'pending';
}

enum SubmitOutcome { sent, queued }

class SubmitResult {
  const SubmitResult(this.outcome, [this.response]);
  final SubmitOutcome outcome;
  final dynamic response;
  bool get queued => outcome == SubmitOutcome.queued;
}

/// Current shape of queued payloads; older rows are still sent (the API accepts both) but recorded with their version.
const outboxPayloadVersion = 2;

/// Commands that must be decided online: estimate / approval decisions, payments, refunds, credit, release.
final _criticalPath = RegExp(r'/(decision|decide|approve|approvals|payments?|refunds?|credit(-override|-notes?)?|release(-override)?|deposit)(/|$)', caseSensitive: false);
bool isCriticalCommand(String path) => _criticalPath.hasMatch(path);

/// Entity of a command: the path without its final verb (for example /workshop/jobs/FG-SO-1/2/start -> /workshop/jobs/FG-SO-1/2).
String outboxEntity(String path) {
  final parts = path.split('?').first.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length > 2 && RegExp(r'^[a-z][a-z-]*$').hasMatch(parts.last)) parts.removeLast();
  return '/${parts.join('/')}';
}

class _Cipher {
  _Cipher(this._storage);
  static const _keyName = 'fg.outbox.key';
  final FlutterSecureStorage _storage;
  final _algorithm = AesGcm.with256bits();
  SecretKey? _key;

  Future<SecretKey> _secret() async {
    if (_key != null) return _key!;
    var stored = await _storage.read(key: _keyName);
    if (stored == null || stored.isEmpty) {
      final random = Random.secure();
      stored = base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
      await _storage.write(key: _keyName, value: stored);
    }
    return _key = SecretKey(base64Decode(stored));
  }

  Future<String> encrypt(String text) async {
    final box = await _algorithm.encrypt(utf8.encode(text), secretKey: await _secret());
    return base64Encode(box.concatenation());
  }

  /// D-110: file contents (queued photos).
  Future<List<int>> encryptBytes(List<int> bytes) async => (await _algorithm.encrypt(bytes, secretKey: await _secret())).concatenation();

  Future<List<int>> decryptBytes(List<int> data) async {
    final box = SecretBox.fromConcatenation(data, nonceLength: _algorithm.nonceLength, macLength: _algorithm.macAlgorithm.macLength);
    return _algorithm.decrypt(box, secretKey: await _secret());
  }

  Future<String?> decrypt(String? data) async {
    if (data == null) return null;
    final box = SecretBox.fromConcatenation(base64Decode(data), nonceLength: _algorithm.nonceLength, macLength: _algorithm.macAlgorithm.macLength);
    return utf8.decode(await _algorithm.decrypt(box, secretKey: await _secret()));
  }

  /// Destroys the key: whatever is left in the database can no longer be read.
  Future<void> destroy() async {
    _key = null;
    await _storage.delete(key: _keyName);
  }
}

class OutboxStore {
  OutboxStore(FlutterSecureStorage secureStorage) : _cipher = _Cipher(secureStorage);
  final _Cipher _cipher;
  Database? _db;

  Future<Database> get db async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'fleetgeeks_outbox.db'),
        version: 2,
        onCreate: (d, v) => d.execute('CREATE TABLE outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, method TEXT NOT NULL, path TEXT NOT NULL, '
            'body TEXT, idem TEXT NOT NULL UNIQUE, label TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, '
            'last_error TEXT, created_at TEXT NOT NULL, scope TEXT NOT NULL DEFAULT \'\', entity TEXT NOT NULL DEFAULT \'\', '
            'operation TEXT NOT NULL DEFAULT \'\', payload_version INTEGER NOT NULL DEFAULT 1, depends_on TEXT, body_enc TEXT)'),
        onUpgrade: (d, from, to) async {
          if (from < 2) {
            for (final column in [
              "scope TEXT NOT NULL DEFAULT ''",
              "entity TEXT NOT NULL DEFAULT ''",
              "operation TEXT NOT NULL DEFAULT ''",
              'payload_version INTEGER NOT NULL DEFAULT 1',
              'depends_on TEXT',
              'body_enc TEXT',
            ]) {
              await d.execute('ALTER TABLE outbox ADD COLUMN $column');
            }
          }
        },
      );

  /// Rows queued by the previous app version keep their clear-text body until this runs once: encrypt and clear it.
  Future<void> encryptLegacy() async {
    final d = await db;
    for (final row in await d.query('outbox', where: 'body IS NOT NULL AND body_enc IS NULL')) {
      await d.update('outbox', {'body_enc': await _cipher.encrypt(row['body']! as String), 'body': null}, where: 'id = ?', whereArgs: [row['id']]);
    }
  }

  Future<void> add({required String method, required String path, Object? body, required String key, required String label, required String scope}) async {
    final d = await db;
    final entity = outboxEntity(path);
    // dependency: the latest command still queued for the same entity
    final previous = await d.query('outbox', columns: ['idem'], where: 'scope = ? AND entity = ?', whereArgs: [scope, entity], orderBy: 'id DESC', limit: 1);
    await d.insert(
      'outbox',
      {
        'method': method,
        'path': path,
        'body': null,
        'body_enc': body == null ? null : await _cipher.encrypt(jsonEncode(body)),
        'idem': key,
        'label': label,
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'scope': scope,
        'entity': entity,
        'operation': '$method ${path.split('?').first.split('/').last}',
        'payload_version': outboxPayloadVersion,
        'depends_on': previous.isEmpty ? null : previous.first['idem'],
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<OutboxItem>> all(String scope) async {
    final rows = await (await db).query('outbox', where: 'scope = ?', whereArgs: [scope], orderBy: 'id');
    return [
      for (final m in rows)
        OutboxItem(
          id: m['id']! as int,
          method: m['method']! as String,
          path: m['path']! as String,
          body: m['body_enc'] != null ? await _cipher.decrypt(m['body_enc'] as String?) : m['body'] as String?,
          key: m['idem']! as String,
          label: m['label']! as String,
          attempts: m['attempts']! as int,
          status: m['status']! as String,
          createdAt: DateTime.parse(m['created_at']! as String),
          scope: m['scope']! as String,
          entity: m['entity']! as String,
          operation: m['operation']! as String,
          payloadVersion: m['payload_version']! as int,
          dependsOn: m['depends_on'] as String?,
          lastError: m['last_error'] as String?,
        ),
    ];
  }

  Future<void> remove(int id) async => (await db).delete('outbox', where: 'id = ?', whereArgs: [id]);

  Future<void> mark(int id, String status, String? error, {bool countAttempt = true}) async => (await db).rawUpdate(
      'UPDATE outbox SET status = ?, last_error = ?, attempts = attempts + ? WHERE id = ?', [status, error, countAttempt ? 1 : 0, id]);

  Future<void> rekey(int id, String key) async => (await db).update('outbox', {'idem': key, 'status': 'pending', 'last_error': null}, where: 'id = ?', whereArgs: [id]);

  /// Legacy rows (no scope) are adopted by the first signed-in user; rows of any other user are deleted.
  Future<void> keepOnly(String scope) async {
    final d = await db;
    await d.update('outbox', {'scope': scope}, where: "scope = ''");
    await d.delete('outbox', where: 'scope <> ?', whereArgs: [scope]);
  }

  /// Sign-out: every queued command and queued file is deleted and the key destroyed.
  Future<void> wipe() async {
    await (await db).delete('outbox');
    final dir = Directory(await filesDir());
    if (await dir.exists()) await dir.delete(recursive: true);
    await _cipher.destroy();
  }

  /// Private folder of queued files.
  Future<String> filesDir() async => p.join(await getDatabasesPath(), 'outbox-files');

  /// Keeps a photo for a queued upload, encrypted; returns its stored path.
  Future<String> keepFile(String sourcePath) async {
    final dir = Directory(await filesDir());
    await dir.create(recursive: true);
    final target = p.join(dir.path, '${const Uuid().v4()}.bin');
    await File(target).writeAsBytes(await _cipher.encryptBytes(await File(sourcePath).readAsBytes()), flush: true);
    return target;
  }

  Future<List<int>> readFile(String storedPath) async => _cipher.decryptBytes(await File(storedPath).readAsBytes());

  Future<void> dropFile(String? storedPath) async {
    if (storedPath == null) return;
    final f = File(storedPath);
    if (await f.exists()) await f.delete();
  }
}

class OutboxNotifier extends AsyncNotifier<List<OutboxItem>> {
  late final OutboxStore _store = OutboxStore(ref.read(secureStorageProvider));
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _flushing = false;
  bool _prepared = false;

  String get _scope => ref.read(authProvider).value?.portalUserId ?? '';

  Future<List<OutboxItem>> _load() async {
    final scope = _scope;
    if (scope.isEmpty) return const [];
    if (!_prepared) {
      await _store.keepOnly(scope);
      await _store.encryptLegacy();
      _prepared = true;
    }
    return _store.all(scope);
  }

  @override
  Future<List<OutboxItem>> build() async {
    ref.watch(authProvider.select((a) => a.value?.portalUserId));
    _prepared = false;
    _subscription ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) unawaited(flush());
    });
    ref.onDispose(() => _subscription?.cancel());
    return _load();
  }

  /// Sends a command now, or keeps it for later when the network is not reachable. Business rejections are thrown;
  /// financial / authorisation / release commands are never queued (the network error is thrown instead).
  Future<SubmitResult> submit(String path, {Object? body, required String label, String method = 'POST', String? key}) async {
    final idempotencyKey = key ?? const Uuid().v4();
    final waiting = (await _load()).isNotEmpty;
    if (!waiting || isCriticalCommand(path)) {
      try {
        final response = await ref.read(apiProvider).send(method, path, body: body ?? const <String, Object?>{}, idempotencyKey: idempotencyKey);
        return SubmitResult(SubmitOutcome.sent, response);
      } on ApiException catch (e) {
        if (!e.isNetwork || isCriticalCommand(path)) rethrow;
      }
    }
    if (_scope.isEmpty) throw ApiException(401, 'Sign in to save this command.');
    // Keep order: once something is waiting, later commands wait behind it.
    await _store.add(method: method, path: path, body: body, key: idempotencyKey, label: label, scope: _scope);
    state = AsyncData(await _load());
    return const SubmitResult(SubmitOutcome.queued);
  }

  /// D-110: uploads a photo now, or keeps it (encrypted) for later when the network is not reachable.
  Future<SubmitResult> submitUpload(String path, {required String filePath, required String contentType, required Map<String, String> fields, required String label}) async {
    final key = const Uuid().v4();
    if ((await _load()).isEmpty) {
      try {
        final response = await ref.read(apiProvider).upload(path, filePath: filePath, contentType: contentType, fields: fields, idempotencyKey: key);
        return SubmitResult(SubmitOutcome.sent, response);
      } on ApiException catch (e) {
        if (!e.isNetwork) rethrow;
      }
    }
    if (_scope.isEmpty) throw ApiException(401, 'Sign in to save this photo.');
    final stored = await _store.keepFile(filePath);
    await _store.add(method: 'UPLOAD', path: path, body: {'file': stored, 'name': p.basename(filePath), 'contentType': contentType, 'fields': fields}, key: key, label: label, scope: _scope);
    state = AsyncData(await _load());
    return const SubmitResult(SubmitOutcome.queued);
  }

  /// Replays waiting commands in order; stops at the first network failure or an expired session.
  Future<int> flush() async {
    if (_flushing || _scope.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final items = await _load();
      final open = {for (final i in items) i.key: i};
      for (final item in items) {
        if (item.status != 'pending' && item.status != 'blocked') continue;
        final dependency = item.dependsOn == null ? null : open[item.dependsOn];
        if (dependency != null && dependency.needsReview) {
          await _store.mark(item.id, 'blocked', dependency.key, countAttempt: false);
          continue;
        }
        if (dependency != null) continue; // still waiting to be sent
        try {
          if (item.method == 'UPLOAD') {
            // D-110: queued photo - decrypted in memory, uploaded with its key, then the stored file is deleted
            final u = Map<String, dynamic>.from(jsonDecode(item.body!) as Map);
            await ref.read(apiProvider).uploadBytes(item.path,
                bytes: await _store.readFile('${u['file']}'), fileName: '${u['name']}', contentType: '${u['contentType']}',
                fields: Map<String, String>.from(u['fields'] as Map), idempotencyKey: item.key);
            await _store.dropFile('${u['file']}');
          } else {
            await ref.read(apiProvider).send(item.method, item.path, body: item.body == null ? null : jsonDecode(item.body!), idempotencyKey: item.key);
          }
          await _store.remove(item.id);
          open.remove(item.key);
          sent++;
        } on ApiException catch (e) {
          if (e.isNetwork) break;
          if (e.status == 401) {
            await _store.mark(item.id, 'pending', e.message, countAttempt: false);
            break; // session expired: the same user signs in again, then the queue continues
          }
          if (e.isConflict) {
            await _store.mark(item.id, 'conflict', e.code == null ? e.message : '${e.code}: ${e.message}');
            open[item.key] = (await _load()).firstWhere((i) => i.id == item.id);
          } else if (e.isRejection) {
            await _store.mark(item.id, 'failed', e.message);
            open[item.key] = (await _load()).firstWhere((i) => i.id == item.id);
          } else {
            await _store.mark(item.id, 'pending', e.message);
            break; // server error: try again on the next connection change or Send now
          }
        }
      }
    } finally {
      _flushing = false;
      state = AsyncData(await _load());
    }
    return sent;
  }

  /// The user reviewed a refused / conflicting command and sends it again: a new key, so it is a new command.
  Future<void> retry(OutboxItem item) async {
    await _store.rekey(item.id, const Uuid().v4());
    await flush();
  }

  Future<void> discard(OutboxItem item) async {
    if (item.method == 'UPLOAD' && item.body != null) await _store.dropFile('${(jsonDecode(item.body!) as Map)['file']}');
    await _store.remove(item.id);
    state = AsyncData(await _load());
    unawaited(flush());
  }

  /// Local-data cleanup on sign-out.
  Future<void> wipe() async {
    await _store.wipe();
    state = const AsyncData([]);
  }
}

final outboxProvider = AsyncNotifierProvider<OutboxNotifier, List<OutboxItem>>(OutboxNotifier.new);
