import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qestak/core/database/app_database.dart';
import 'package:qestak/core/finance/allocation.dart';
import 'package:qestak/core/finance/pricing.dart';
import 'package:qestak/core/finance/schedule.dart';
import 'package:qestak/data/backup_service.dart';
import 'package:qestak/data/repository.dart';

int egp(int v) => v * 100;

AppDatabase newDb() => AppDatabase(NativeDatabase.memory());

/// Customer with one contract: 3 monthly installments of 1,000 EGP (future dates).
Future<({String customerId, String contractId})> seed(Repository repo) async {
  final cid = await repo.addCustomer(name: 'محمد أحمد', phone: '01012345678');
  final pricing = PricingCalculator.calculate(
      cashPrice: egp(3000), type: MarkupType.fixed, markupValue: 0);
  final schedule = ScheduleGenerator.generate(
      financedAmount: pricing.financedAmount,
      count: 3,
      frequency: PaymentFrequency.monthly,
      firstDate: DateTime.utc(2035, 1, 10));
  final kid = await repo.createContract(
    customerId: cid,
    productName: 'ثلاجة',
    pricing: pricing,
    markupType: MarkupType.fixed,
    markupValue: 0,
    frequency: 'monthly',
    firstDate: DateTime.utc(2035, 1, 10),
    schedule: schedule,
  );
  return (customerId: cid, contractId: kid);
}

void main() {
  late AppDatabase db;
  late Repository repo;
  setUp(() {
    db = newDb();
    repo = Repository(db);
  });
  tearDown(() => db.close());

  test('partial payments are kept separately and complete the installment', () async {
    final s0 = await seed(repo);
    await repo.recordPayment(
        customerId: s0.customerId, amount: egp(400), date: DateTime.utc(2035, 1, 1), method: 'cash', idempotencyKey: 'k1');
    var snap = await repo.loadSnapshot();
    var first = snap.instViews.first;
    expect(first.paid, egp(400));
    expect(first.remaining, egp(600));
    expect(first.status.hasPartialPayment, isTrue);

    await repo.recordPayment(
        customerId: s0.customerId, amount: egp(600), date: DateTime.utc(2035, 1, 2), method: 'cash', idempotencyKey: 'k2');
    snap = await repo.loadSnapshot();
    first = snap.instViews.first;
    expect(first.remaining, 0);
    expect(snap.payments.length, 2);
    expect(snap.allocations.length, 2);
    expect(snap.totalRemaining, egp(2000));
  });

  test('duplicate submission with same key creates one payment', () async {
    final s0 = await seed(repo);
    for (var i = 0; i < 3; i++) {
      await repo.recordPayment(
          customerId: s0.customerId, amount: egp(500), date: DateTime.utc(2035, 1, 1), method: 'cash', idempotencyKey: 'same');
    }
    expect((await repo.loadSnapshot()).payments.length, 1);
  });

  test('excess is rejected, or kept as credit when chosen', () async {
    final s0 = await seed(repo);
    await expectLater(
        repo.recordPayment(customerId: s0.customerId, amount: egp(3500), date: DateTime.utc(2035, 1, 1), method: 'cash', idempotencyKey: 'a'),
        throwsA(isA<AppException>()));
    expect((await repo.loadSnapshot()).payments, isEmpty); // rolled back
    await repo.recordPayment(
        customerId: s0.customerId, amount: egp(3500), date: DateTime.utc(2035, 1, 1), method: 'cash',
        idempotencyKey: 'b', excess: ExcessPolicy.keepAsCredit);
    final snap = await repo.loadSnapshot();
    expect(snap.totalRemaining, 0);
    expect(snap.creditOf(s0.customerId), egp(500));
  });

  test('reversal restores balances, keeps history, and works once', () async {
    final s0 = await seed(repo);
    final pid = await repo.recordPayment(
        customerId: s0.customerId, amount: egp(2500), date: DateTime.utc(2035, 1, 1), method: 'cash', idempotencyKey: 'r');
    expect((await repo.loadSnapshot()).totalRemaining, egp(500));
    await expectLater(repo.reversePayment(pid, '  '), throwsA(isA<AppException>()));
    await repo.reversePayment(pid, 'خطأ في الإدخال');
    final snap = await repo.loadSnapshot();
    expect(snap.totalRemaining, egp(3000));
    expect(snap.payments.length, 1); // original kept
    expect(snap.allocations.length, 3); // original allocations kept
    await expectLater(repo.reversePayment(pid, 'again'), throwsA(isA<AppException>()));
  });

  test('cannot pay another customer\'s installment', () async {
    final s0 = await seed(repo);
    final other = await repo.addCustomer(name: 'علي', phone: '01099999999');
    await expectLater(
        repo.recordPayment(
            customerId: other, amount: egp(100), date: DateTime.utc(2035, 1, 1), method: 'cash', idempotencyKey: 'x',
            mode: AllocationMode.specific, targetInstallmentId: (await repo.loadSnapshot()).instViews.first.inst.id),
        throwsA(isA<AppException>()));
    expect(s0.customerId == other, isFalse);
  });

  test('duplicate phone is flagged; customer with contracts cannot be deleted', () async {
    final s0 = await seed(repo);
    await expectLater(repo.addCustomer(name: 'شخص آخر', phone: '٠١٠١٢٣٤٥٦٧٨'), throwsA(isA<DuplicateCustomerException>()));
    await expectLater((db.delete(db.customers)..where((c) => c.id.equals(s0.customerId))).go(), throwsA(anything));
  });

  test('search is Arabic-normalization tolerant', () async {
    await seed(repo);
    final snap = await repo.loadSnapshot();
    expect(snap.search('احمد').length, 1); // أ vs ا
    expect(snap.search('01012').length, 1);
    expect(snap.search('ثلاجه').length, 1); // ة vs ه (product)
    expect(snap.search('C-0001').length, 1);
    expect(snap.search('xyz'), isEmpty);
  });

  test('backup round trip into a clean database', () async {
    final s0 = await seed(repo);
    await repo.recordPayment(
        customerId: s0.customerId, amount: egp(1500), date: DateTime.utc(2035, 1, 1), method: 'cash', idempotencyKey: 'bk');
    final svc = BackupService(db);
    final env = await svc.buildEnvelope('secret123');

    final db2 = newDb();
    addTearDown(db2.close);
    final svc2 = BackupService(db2);
    final opened = await svc2.openEnvelope(env, 'secret123');
    expect(opened.summary.customers, 1);
    expect(opened.summary.payments, 1);
    await svc2.restore(opened);

    final a = await repo.loadSnapshot();
    final b = await Repository(db2).loadSnapshot();
    expect(b.totalRemaining, a.totalRemaining);
    expect(b.totalCollected, a.totalCollected);
    expect(b.allocations.length, a.allocations.length);
    expect(await svc2.verifyIntegrity(), isEmpty);
  });

  test('wrong password and tampered file are rejected', () async {
    await seed(repo);
    final svc = BackupService(db);
    final env = await svc.buildEnvelope('secret123');
    await expectLater(svc.openEnvelope(env, 'wrong-pass'), throwsA(isA<BackupException>()));
    final tampered = Map<String, dynamic>.from(env)..remove('_counts');
    tampered['ciphertext'] = (tampered['ciphertext'] as String).replaceRange(10, 14, 'AAAA');
    await expectLater(svc.openEnvelope(tampered, 'secret123'), throwsA(isA<BackupException>()));
    final notOurs = Map<String, dynamic>.from(env)..['app'] = 'other';
    await expectLater(svc.openEnvelope(notOurs, 'secret123'), throwsA(isA<BackupException>()));
  });

  test('failed restore leaves existing data untouched', () async {
    await seed(repo);
    final svc = BackupService(db);
    final env = await svc.buildEnvelope('secret123');
    final opened = await svc.openEnvelope(env, 'secret123');
    // corrupt in memory: allocation pointing to a missing installment
    final data = opened.data;
    (data['paymentAllocations'] as List).add({
      'id': 'bad', 'paymentId': 'nope', 'installmentId': 'nope', 'amount': 5
    });
    await expectLater(svc.restore(OpenedBackup(opened.summary, data)), throwsA(anything));
    expect((await repo.loadSnapshot()).customers.length, 1);
  });
}
