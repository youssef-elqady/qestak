import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/arabic.dart';
import '../core/database/app_database.dart';
import '../core/finance/allocation.dart';
import '../core/finance/errors.dart';
import '../core/finance/ledger.dart';
import '../core/finance/pricing.dart';
import '../core/finance/schedule.dart';
import 'snapshot.dart';

class AppException implements Exception {
  final String message;
  AppException(this.message);
  @override
  String toString() => message;
}

class DuplicateCustomerException extends AppException {
  final Customer existing;
  DuplicateCustomerException(this.existing)
      : super('يوجد عميل بنفس رقم الهاتف: ${existing.fullName}');
}

String paymentErrorText(PaymentValidationException e) {
  switch (e.code) {
    case PaymentErrorCode.nonPositiveAmount:
      return 'يجب أن يكون المبلغ أكبر من صفر';
    case PaymentErrorCode.foreignContract:
      return 'القسط يخص عميلاً آخر';
    case PaymentErrorCode.installmentNotOpen:
      return 'القسط المحدد غير مستحق أو مسدد بالكامل';
    case PaymentErrorCode.excessWithoutPolicy:
      return 'المبلغ أكبر من المستحق. اختر حفظ الزيادة كرصيد للعميل أو قلل المبلغ';
    case PaymentErrorCode.manualOverAllocated:
      return 'مجموع التوزيع اليدوي أكبر من المبلغ المدفوع';
    case PaymentErrorCode.manualInvalidAmount:
      return 'مبلغ التوزيع اليدوي غير صحيح';
    case PaymentErrorCode.reasonRequired:
      return 'السبب مطلوب';
    case PaymentErrorCode.alreadyReversed:
      return 'تم عكس هذه الدفعة من قبل';
    case PaymentErrorCode.creditAlreadyConsumed:
      return 'الرصيد الناتج عن هذه الدفعة تم استخدامه بالفعل';
  }
}

class Repository {
  Repository(this.db);
  final AppDatabase db;
  static const _uuid = Uuid();
  String _id() => _uuid.v4();

  Future<Snapshot> loadSnapshot() async {
    return Snapshot(
      today: _todayUtc(),
      customers: await db.select(db.customers).get(),
      contracts: await db.select(db.contracts).get(),
      installments: await db.select(db.installments).get(),
      payments: await db.select(db.payments).get(),
      allocations: await db.select(db.paymentAllocations).get(),
      reversals: await db.select(db.paymentReversals).get(),
      credits: await db.select(db.customerCredits).get(),
      followUps: await db.select(db.followUps).get(),
    );
  }

  Future<void> _audit(String action, String type, String id,
      [String? details]) async {
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
        id: _id(),
        action: action,
        entityType: type,
        entityId: id,
        details: Value(details),
        createdAt: DateTime.now()));
  }

  // ------------------------------------------------------------ customers
  Future<String> addCustomer({
    required String name,
    required String phone,
    String? phone2,
    String? address,
    String? area,
    String? notes,
    bool allowDuplicate = false,
  }) async {
    final p = normalizePhone(phone);
    if (name.trim().isEmpty || p.isEmpty) {
      throw AppException('الاسم ورقم الهاتف مطلوبان');
    }
    if (!allowDuplicate) {
      final dup = await (db.select(db.customers)..where((c) => c.phone.equals(p))).get();
      if (dup.isNotEmpty) throw DuplicateCustomerException(dup.first);
    }
    final id = _id();
    await db.transaction(() async {
      await db.into(db.customers).insert(CustomersCompanion.insert(
            id: id,
            fullName: name.trim(),
            searchName: normalizeArabic(name),
            phone: p,
            createdAt: DateTime.now(),
            phone2: Value(_nz(phone2) == null ? null : normalizePhone(phone2!)),
            address: Value(_nz(address)),
            area: Value(_nz(area)),
            notes: Value(_nz(notes)),
          ));
      await _audit('create', 'customer', id);
    });
    return id;
  }

  String? _nz(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<void> updateCustomer(String id,
      {required String name,
      required String phone,
      String? phone2,
      String? address,
      String? area,
      String? notes}) async {
    final p = normalizePhone(phone);
    if (name.trim().isEmpty || p.isEmpty) {
      throw AppException('الاسم ورقم الهاتف مطلوبان');
    }
    await db.transaction(() async {
      await (db.update(db.customers)..where((c) => c.id.equals(id))).write(
          CustomersCompanion(
              fullName: Value(name.trim()),
              searchName: Value(normalizeArabic(name)),
              phone: Value(p),
              phone2: Value(_nz(phone2) == null ? null : normalizePhone(phone2!)),
              address: Value(_nz(address)),
              area: Value(_nz(area)),
              notes: Value(_nz(notes))));
      await _audit('update', 'customer', id);
    });
  }

  Future<void> setCustomerStatus(String id, String status) async {
    await db.transaction(() async {
      await (db.update(db.customers)..where((c) => c.id.equals(id)))
          .write(CustomersCompanion(status: Value(status)));
      await _audit(status == 'archived' ? 'archive' : 'restore', 'customer', id);
    });
  }

  // ------------------------------------------------------------ contracts
  Future<String> createContract({
    required String customerId,
    required String productName,
    String? description,
    required PricingResult pricing,
    required MarkupType markupType,
    required int markupValue,
    required String frequency, // monthly | weekly | custom
    required DateTime firstDate,
    int? preferredDay,
    int graceDays = 0,
    String? notes,
    required List<ScheduleItem> schedule,
  }) async {
    if (productName.trim().isEmpty) throw AppException('اسم المنتج مطلوب');
    if (pricing.financedAmount <= 0) {
      throw AppException('المبلغ المقسط يجب أن يكون أكبر من صفر');
    }
    final err = ScheduleGenerator.validateCustom(schedule, pricing.financedAmount);
    if (err != null) throw AppException('جدول الأقساط غير صحيح');
    final id = _id();
    await db.transaction(() async {
      final n = (await db.select(db.contracts).get()).length;
      var number = 'C-${(n + 1).toString().padLeft(4, '0')}';
      var k = n + 1;
      while ((await (db.select(db.contracts)
                ..where((c) => c.contractNumber.equals(number)))
              .get())
          .isNotEmpty) {
        k++;
        number = 'C-${k.toString().padLeft(4, '0')}';
      }
      await db.into(db.contracts).insert(ContractsCompanion.insert(
            id: id,
            contractNumber: number,
            customerId: customerId,
            productName: productName.trim(),
            description: Value(_nz(description)),
            cashPrice: pricing.cashPrice,
            markupType: markupType.name,
            markupValue: markupValue,
            finalPrice: pricing.finalPrice,
            downPayment: Value(pricing.downPayment),
            financedAmount: pricing.financedAmount,
            installmentCount: schedule.length,
            frequency: frequency,
            firstPaymentDate: toStorage(firstDate),
            preferredDay: Value(preferredDay),
            graceDays: Value(graceDays),
            notes: Value(_nz(notes)),
            status: const Value('active'),
            createdAt: DateTime.now(),
          ));
      for (final s in schedule) {
        await db.into(db.installments).insert(InstallmentsCompanion.insert(
            id: _id(),
            contractId: id,
            sequence: s.sequence,
            dueDate: toStorage(s.dueDate),
            originalAmount: s.amount,
            createdAt: DateTime.now()));
      }
      await _audit('create', 'contract', id, number);
    });
    return id;
  }

  /// Documented amendment: only the due date of an installment can be moved.
  Future<void> moveInstallmentDate(
      String installmentId, DateTime newDate, String reason) async {
    if (reason.trim().isEmpty) throw AppException('سبب التعديل مطلوب');
    await db.transaction(() async {
      final inst = await (db.select(db.installments)
            ..where((i) => i.id.equals(installmentId)))
          .getSingle();
      await (db.update(db.installments)..where((i) => i.id.equals(installmentId)))
          .write(InstallmentsCompanion(dueDate: Value(toStorage(newDate))));
      await db.into(db.financialAdjustments).insert(
          FinancialAdjustmentsCompanion.insert(
              id: _id(),
              contractId: inst.contractId,
              installmentId: Value(installmentId),
              kind: 'reschedule',
              reason: reason.trim(),
              createdAt: DateTime.now()));
      await _audit('reschedule', 'installment', installmentId,
          '${inst.dueDate.toIso8601String()} -> ${newDate.toIso8601String()}');
    });
  }

  // ------------------------------------------------------------- payments
  Future<String> recordPayment({
    required String customerId,
    required int amount,
    required DateTime date,
    required String method,
    required String idempotencyKey,
    String? notes,
    AllocationMode mode = AllocationMode.oldestFirst,
    ExcessPolicy excess = ExcessPolicy.reject,
    String? targetInstallmentId,
    Map<String, int>? manual,
  }) async {
    try {
      return await db.transaction(() async {
        final dup = await (db.select(db.payments)
              ..where((p) => p.idempotencyKey.equals(idempotencyKey)))
            .getSingleOrNull();
        if (dup != null) return dup.id; // duplicate submission: no second row
        final snap = await loadSnapshot();
        final plan = PaymentPlanner.plan(
          customerId: customerId,
          amount: amount,
          open: snap.openInstallmentsOf(customerId),
          mode: mode,
          excess: excess,
          targetInstallmentId: targetInstallmentId,
          manualAmounts: manual,
        );
        final contractIds = <String>{
          for (final a in plan.allocations)
            snap.instViews.firstWhere((v) => v.inst.id == a.installmentId).contract.id
        };
        final id = _id();
        final receipt = 'R-${(snap.payments.length + 1).toString().padLeft(6, '0')}';
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              id: id,
              receiptNumber: receipt,
              idempotencyKey: idempotencyKey,
              customerId: customerId,
              contractId: Value(contractIds.length == 1 ? contractIds.first : null),
              paymentDate: toStorage(date),
              amount: amount,
              method: method,
              notes: Value(_nz(notes)),
              createdAt: DateTime.now(),
            ));
        for (final a in plan.allocations) {
          await db.into(db.paymentAllocations).insert(
              PaymentAllocationsCompanion.insert(
                  id: _id(),
                  paymentId: id,
                  installmentId: a.installmentId,
                  amount: a.amount));
        }
        if (plan.creditAmount > 0) {
          await db.into(db.customerCredits).insert(CustomerCreditsCompanion.insert(
              id: _id(),
              customerId: customerId,
              paymentId: Value(id),
              delta: plan.creditAmount,
              reason: 'زيادة عن المستحق - $receipt',
              createdAt: DateTime.now()));
        }
        await _audit('create', 'payment', id, receipt);
        return id;
      });
    } on PaymentValidationException catch (e) {
      throw AppException(paymentErrorText(e));
    }
  }

  Future<void> reversePayment(String paymentId, String reason) async {
    try {
      await db.transaction(() async {
        final snap = await loadSnapshot();
        final pay = snap.payments.firstWhere((p) => p.id == paymentId);
        final reversed = snap.reversals.any((r) => r.paymentId == paymentId);
        final allocs = snap.allocations
            .where((a) => a.paymentId == paymentId)
            .map((a) => AllocationRecord(a.paymentId, a.installmentId, a.amount, false))
            .toList();
        final created = snap.credits
            .where((c) => c.paymentId == paymentId && c.delta > 0)
            .fold<int>(0, (s, c) => s + c.delta);
        final plan = ReversalPlanner.plan(
          paymentId: paymentId,
          reason: reason,
          allocationsOfPayment: allocs,
          alreadyReversed: reversed,
          creditCreatedByPayment: created,
          currentCustomerCredit: snap.creditOf(pay.customerId),
        );
        await db.into(db.paymentReversals).insert(PaymentReversalsCompanion.insert(
            id: _id(), paymentId: paymentId, reason: plan.reason, createdAt: DateTime.now()));
        if (plan.creditToRemove > 0) {
          await db.into(db.customerCredits).insert(CustomerCreditsCompanion.insert(
              id: _id(),
              customerId: pay.customerId,
              paymentId: Value(paymentId),
              delta: -plan.creditToRemove,
              reason: 'عكس دفعة ${pay.receiptNumber}',
              createdAt: DateTime.now()));
        }
        await _audit('reverse', 'payment', paymentId, plan.reason);
      });
    } on PaymentValidationException catch (e) {
      throw AppException(paymentErrorText(e));
    }
  }

  // ------------------------------------------------------------ follow-ups
  Future<void> addFollowUp({
    required String customerId,
    String? contractId,
    required DateTime date,
    String? response,
    DateTime? expectedPayment,
    String? notes,
  }) async {
    await db.into(db.followUps).insert(FollowUpsCompanion.insert(
        id: _id(),
        customerId: customerId,
        contractId: Value(contractId),
        followUpDate: toStorage(date),
        customerResponse: Value(_nz(response)),
        expectedPaymentDate:
            Value(expectedPayment == null ? null : toStorage(expectedPayment)),
        notes: Value(_nz(notes)),
        createdAt: DateTime.now()));
  }

  Future<void> setFollowUpDone(String id, bool done) =>
      (db.update(db.followUps)..where((f) => f.id.equals(id)))
          .write(FollowUpsCompanion(completed: Value(done)));

  // -------------------------------------------------------------- settings
  Future<Map<String, String>> loadSettings() async {
    final rows = await db.select(db.appSettings).get();
    return {for (final r in rows) r.settingKey: r.settingValue};
  }

  Future<void> setSetting(String key, String value) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
          AppSettingsCompanion.insert(settingKey: key, settingValue: value));
}

DateTime _todayUtc() {
  final n = DateTime.now();
  return DateTime.utc(n.year, n.month, n.day);
}
