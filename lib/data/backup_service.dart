import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../core/database/app_database.dart';

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}

class BackupSummary {
  final DateTime createdAt;
  final int schemaVersion;
  final int customers;
  final int contracts;
  final int payments;
  final int installments;
  const BackupSummary(this.createdAt, this.schemaVersion, this.customers,
      this.contracts, this.payments, this.installments);
}

class OpenedBackup {
  final BackupSummary summary;
  final Map<String, dynamic> data;
  OpenedBackup(this.summary, this.data);
}

/// Portable encrypted backup. See docs/BACKUP_FORMAT.md.
/// The payload is a JSON dump of every table (not the SQLite file), so it is
/// identical on Android and iOS.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  static const appId = 'com.qestak.app';
  static const formatVersion = 1;
  static const iterations = 100000;

  static const _tableOrder = [
    'customers',
    'contracts',
    'installments',
    'payments',
    'paymentAllocations',
    'customerCredits',
    'financialAdjustments',
    'paymentReversals',
    'followUps',
    'appSettings',
    'notificationSettings',
    'auditLogs',
    'backupMetadata',
    'attachments',
  ];

  Future<Map<String, List<Map<String, dynamic>>>> _dump() async {
    List<Map<String, dynamic>> j<T extends DataClass>(List<T> l) =>
        l.map((e) => e.toJson()).toList();
    return {
      'customers': j(await db.select(db.customers).get()),
      'contracts': j(await db.select(db.contracts).get()),
      'installments': j(await db.select(db.installments).get()),
      'payments': j(await db.select(db.payments).get()),
      'paymentAllocations': j(await db.select(db.paymentAllocations).get()),
      'customerCredits': j(await db.select(db.customerCredits).get()),
      'financialAdjustments': j(await db.select(db.financialAdjustments).get()),
      'paymentReversals': j(await db.select(db.paymentReversals).get()),
      'followUps': j(await db.select(db.followUps).get()),
      'appSettings': j(await db.select(db.appSettings).get()),
      'notificationSettings': j(await db.select(db.notificationSettings).get()),
      'auditLogs': j(await db.select(db.auditLogs).get()),
      'backupMetadata': j(await db.select(db.backupMetadata).get()),
      'attachments': j(await db.select(db.attachments).get()),
    };
  }

  List<int> _random(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  Future<SecretKey> _derive(String password, List<int> salt, int iters) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iters, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);

  List<int> _aad(String app, int fmt, int schema, String created) =>
      utf8.encode('$app|$fmt|$schema|$created');

  /// Builds the encrypted envelope (the content of a .qbk file).
  Future<Map<String, dynamic>> buildEnvelope(String password) async {
    if (password.length < 6) {
      throw BackupException('كلمة المرور يجب ألا تقل عن 6 أحرف');
    }
    final data = await db.transaction(() => _dump());
    final created = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'counts': {for (final e in data.entries) e.key: e.value.length},
      'data': data,
    };
    final salt = _random(16);
    final nonce = _random(12);
    final key = await _derive(password, salt, iterations);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: nonce,
      aad: _aad(appId, formatVersion, db.schemaVersion, created),
    );
    final file = {
      'app': appId,
      'format': formatVersion,
      'schemaVersion': db.schemaVersion,
      'createdAt': created,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'cipher': 'AES-256-GCM',
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
    return {...file, '_counts': data.map((k, v) => MapEntry(k, v.length))};
  }

  /// Creates an encrypted backup file in app-private storage and returns it.
  Future<File> createBackup(String password, {String kind = 'export'}) async {
    final env = await buildEnvelope(password);
    final counts = (env.remove('_counts') as Map).cast<String, int>();
    final now = DateTime.parse(env['createdAt'] as String);
    final file = env;
    final dir = kind == 'export'
        ? await getTemporaryDirectory()
        : await getApplicationDocumentsDirectory();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final out = File('${dir.path}/qestak_${kind == 'export' ? '' : 'pre_restore_'}$stamp.qbk');
    await out.writeAsString(jsonEncode(file), flush: true);

    await db.into(db.backupMetadata).insert(BackupMetadataCompanion.insert(
        id: 'bk_${now.microsecondsSinceEpoch}',
        createdAt: now,
        schemaVersion: db.schemaVersion,
        customerCount: counts['customers']!,
        contractCount: counts['contracts']!,
        paymentCount: counts['payments']!,
        kind: kind));
    return out;
  }

  /// Verifies file structure, password, integrity and compatibility.
  /// Nothing is written to the database.
  Future<OpenedBackup> open(String path, String password) async =>
      openFromString(await File(path).readAsString(), password);

  /// Same as [open] but takes the file content (works with any file picker).
  Future<OpenedBackup> openFromString(String content, String password) async {
    Map<String, dynamic> f;
    try {
      f = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      throw BackupException('الملف تالف أو ليس نسخة احتياطية من قسطك');
    }
    return openEnvelope(f, password);
  }

  Future<OpenedBackup> openEnvelope(Map<String, dynamic> f, String password) async {
    if (f['app'] != appId) {
      throw BackupException('هذا الملف ليس نسخة احتياطية من قسطك');
    }
    final fmt = f['format'];
    final schema = f['schemaVersion'];
    if (fmt is! int || fmt > formatVersion) {
      throw BackupException('نسخة من إصدار أحدث من التطبيق. حدّث التطبيق أولاً');
    }
    if (schema is! int || schema > db.schemaVersion) {
      throw BackupException('قاعدة بيانات النسخة أحدث من التطبيق. حدّث التطبيق أولاً');
    }
    List<int> plain;
    try {
      final key = await _derive(
          password, base64Decode(f['salt'] as String), f['iterations'] as int);
      final box = SecretBox(base64Decode(f['ciphertext'] as String),
          nonce: base64Decode(f['nonce'] as String),
          mac: Mac(base64Decode(f['mac'] as String)));
      plain = await AesGcm.with256bits().decrypt(box,
          secretKey: key,
          aad: _aad(f['app'] as String, fmt, schema, f['createdAt'] as String));
    } on SecretBoxAuthenticationError {
      throw BackupException('كلمة المرور خاطئة أو الملف تالف');
    } catch (_) {
      throw BackupException('الملف تالف أو غير مكتمل');
    }
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } catch (_) {
      throw BackupException('محتوى النسخة تالف');
    }
    final data = (payload['data'] as Map).cast<String, dynamic>();
    final counts = (payload['counts'] as Map).cast<String, dynamic>();
    for (final t in _tableOrder) {
      final l = data[t];
      if (l is! List || l.length != counts[t]) {
        throw BackupException('بيانات النسخة غير مكتملة ($t)');
      }
    }
    _validateRelations(data);
    return OpenedBackup(
        BackupSummary(
            DateTime.parse(f['createdAt'] as String).toLocal(),
            schema,
            (data['customers'] as List).length,
            (data['contracts'] as List).length,
            (data['payments'] as List).length,
            (data['installments'] as List).length),
        data);
  }

  void _validateRelations(Map<String, dynamic> d) {
    Set<String> ids(String t) =>
        {for (final r in d[t] as List) (r as Map)['id'] as String};
    final cust = ids('customers'), con = ids('contracts');
    final inst = ids('installments'), pay = ids('payments');
    for (final r in d['contracts'] as List) {
      if (!cust.contains((r as Map)['customerId'])) {
        throw BackupException('علاقات البيانات غير سليمة (عقود)');
      }
    }
    for (final r in d['installments'] as List) {
      if (!con.contains((r as Map)['contractId'])) {
        throw BackupException('علاقات البيانات غير سليمة (أقساط)');
      }
    }
    for (final r in d['paymentAllocations'] as List) {
      final m = r as Map;
      if (!pay.contains(m['paymentId']) || !inst.contains(m['installmentId'])) {
        throw BackupException('علاقات البيانات غير سليمة (توزيعات)');
      }
    }
    for (final r in d['payments'] as List) {
      if (!cust.contains((r as Map)['customerId'])) {
        throw BackupException('علاقات البيانات غير سليمة (دفعات)');
      }
    }
  }

  /// Replaces ALL data atomically. On any error the transaction rolls back and
  /// the existing database is untouched.
  Future<void> restore(OpenedBackup backup) async {
    final d = backup.data;
    await db.transaction(() async {
      await db.delete(db.attachments).go();
      await db.delete(db.backupMetadata).go();
      await db.delete(db.auditLogs).go();
      await db.delete(db.notificationSettings).go();
      await db.delete(db.appSettings).go();
      await db.delete(db.followUps).go();
      await db.delete(db.paymentReversals).go();
      await db.delete(db.financialAdjustments).go();
      await db.delete(db.customerCredits).go();
      await db.delete(db.paymentAllocations).go();
      await db.delete(db.payments).go();
      await db.delete(db.installments).go();
      await db.delete(db.contracts).go();
      await db.delete(db.customers).go();

      Future<void> ins<T extends Table, D>(
          TableInfo<T, D> table, String key, D Function(Map<String, dynamic>) from) async {
        for (final m in d[key] as List) {
          await db.into(table).insert(from((m as Map).cast<String, dynamic>()) as Insertable<D>);
        }
      }

      await ins(db.customers, 'customers', Customer.fromJson);
      await ins(db.contracts, 'contracts', Contract.fromJson);
      await ins(db.installments, 'installments', Installment.fromJson);
      await ins(db.payments, 'payments', Payment.fromJson);
      await ins(db.paymentAllocations, 'paymentAllocations', PaymentAllocation.fromJson);
      await ins(db.customerCredits, 'customerCredits', CustomerCredit.fromJson);
      await ins(db.financialAdjustments, 'financialAdjustments', FinancialAdjustment.fromJson);
      await ins(db.paymentReversals, 'paymentReversals', PaymentReversal.fromJson);
      await ins(db.followUps, 'followUps', FollowUp.fromJson);
      await ins(db.appSettings, 'appSettings', AppSetting.fromJson);
      await ins(db.notificationSettings, 'notificationSettings', NotificationPref.fromJson);
      await ins(db.auditLogs, 'auditLogs', AuditLog.fromJson);
      await ins(db.backupMetadata, 'backupMetadata', BackupMeta.fromJson);
      await ins(db.attachments, 'attachments', Attachment.fromJson);

      final problems = await verifyIntegrity();
      if (problems.isNotEmpty) {
        throw BackupException('فشل فحص السلامة بعد الاسترجاع: ${problems.first}');
      }
    });
  }

  /// Returns a list of problems (empty = consistent).
  Future<List<String>> verifyIntegrity() async {
    final problems = <String>[];
    final insts = await db.select(db.installments).get();
    final allocs = await db.select(db.paymentAllocations).get();
    final reversed = {
      for (final r in await db.select(db.paymentReversals).get()) r.paymentId
    };
    final paid = <String, int>{};
    for (final a in allocs) {
      if (!reversed.contains(a.paymentId)) {
        paid[a.installmentId] = (paid[a.installmentId] ?? 0) + a.amount;
      }
    }
    for (final i in insts) {
      if ((paid[i.id] ?? 0) > i.originalAmount) {
        problems.add('قسط مدفوع بأكثر من قيمته (عقد ${i.contractId})');
      }
    }
    final pays = await db.select(db.payments).get();
    final credits = await db.select(db.customerCredits).get();
    for (final p in pays) {
      final a = allocs.where((x) => x.paymentId == p.id).fold<int>(0, (s, x) => s + x.amount);
      final c = credits
          .where((x) => x.paymentId == p.id && x.delta > 0)
          .fold<int>(0, (s, x) => s + x.delta);
      if (a + c != p.amount) {
        problems.add('دفعة ${p.receiptNumber} مجموع توزيعها لا يساوي مبلغها');
      }
    }
    return problems;
  }
}
