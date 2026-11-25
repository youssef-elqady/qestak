import '../core/arabic.dart';
import '../core/database/app_database.dart';
import '../core/finance/allocation.dart';
import '../core/finance/ledger.dart';
import '../core/finance/money.dart';
import '../core/finance/schedule.dart';
import '../core/finance/status.dart';

/// Dates are stored as local midnight and handled by the engine as UTC dates.
DateTime fromStorage(DateTime d) => DateTime.utc(d.year, d.month, d.day);
DateTime toStorage(DateTime d) => DateTime(d.year, d.month, d.day);

class InstView {
  final Installment inst;
  final Contract contract;
  final Customer customer;
  final int paid;
  final StatusInfo status;
  InstView(this.inst, this.contract, this.customer, this.paid, this.status);
  int get remaining => inst.originalAmount - paid;
  DateTime get due => fromStorage(inst.dueDate);
  bool get inForce => !inst.cancelled && !inst.rescheduled;
}

class PaymentView {
  final Payment payment;
  final Customer customer;
  final bool reversed;
  final String? reversalReason;
  final List<PaymentAllocation> allocations;
  PaymentView(this.payment, this.customer, this.reversed, this.reversalReason,
      this.allocations);
}

class ContractSummary {
  final Contract contract;
  final Customer customer;
  final List<InstView> installments;
  final int collected; // down payment + allocated installment payments
  final int remaining;
  ContractSummary(this.contract, this.customer, this.installments,
      this.collected, this.remaining);
  bool get cancelled => contract.status == 'cancelled';
  bool get completed =>
      !cancelled && remaining == 0 && installments.any((i) => i.inForce);
  int get markup => contract.finalPrice - contract.cashPrice;
  int get overdue => installments
      .where((i) => i.status.status == InstallmentStatus.overdue)
      .fold(0, (s, i) => s + i.remaining);
  int get realizedMarkup {
    if (contract.finalPrice <= 0) return 0;
    final v = Money.roundDiv(markup * collected, contract.finalPrice);
    return v > markup ? markup : v;
  }
}

class CustomerSummary {
  final Customer customer;
  final List<ContractSummary> contracts;
  final int credit;
  CustomerSummary(this.customer, this.contracts, this.credit);
  List<ContractSummary> get live => contracts.where((c) => !c.cancelled).toList();
  int get activeCount => live.where((c) => !c.completed).length;
  int get completedCount => live.where((c) => c.completed).length;
  int get contracted => live.fold(0, (s, c) => s + c.contract.finalPrice);
  int get paid => live.fold(0, (s, c) => s + c.collected);
  int get remaining => live.fold(0, (s, c) => s + c.remaining);
  int get overdue => live.fold(0, (s, c) => s + c.overdue);
  InstView? get next {
    final open = live
        .expand((c) => c.installments)
        .where((i) => i.inForce && i.remaining > 0)
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    return open.isEmpty ? null : open.first;
  }
}

class Snapshot {
  final DateTime today;
  final List<Customer> customers;
  final List<Contract> contracts;
  final List<Installment> installments;
  final List<Payment> payments;
  final List<PaymentAllocation> allocations;
  final List<PaymentReversal> reversals;
  final List<CustomerCredit> credits;
  final List<FollowUp> followUps;

  late final Map<String, Customer> customerById;
  late final List<InstView> instViews;
  late final List<ContractSummary> contractSummaries;
  late final List<CustomerSummary> customerSummaries;
  late final List<PaymentView> paymentViews;

  Snapshot({
    required this.today,
    required this.customers,
    required this.contracts,
    required this.installments,
    required this.payments,
    required this.allocations,
    required this.reversals,
    required this.credits,
    required this.followUps,
  }) {
    customerById = {for (final c in customers) c.id: c};
    final contractById = {for (final c in contracts) c.id: c};
    final reversedIds = {for (final r in reversals) r.paymentId};

    final records = allocations
        .map((a) => AllocationRecord(
            a.paymentId, a.installmentId, a.amount, reversedIds.contains(a.paymentId)))
        .toList();
    final paidBy = <String, int>{};
    for (final r in records) {
      if (!r.reversed) paidBy[r.installmentId] = (paidBy[r.installmentId] ?? 0) + r.amount;
    }

    instViews = installments.map((i) {
      final c = contractById[i.contractId]!;
      final paid = paidBy[i.id] ?? 0;
      final st = StatusCalculator.compute(
        original: i.originalAmount,
        paid: paid,
        dueDate: fromStorage(i.dueDate),
        today: today,
        graceDays: c.graceDays,
        cancelled: i.cancelled || c.status == 'cancelled',
        rescheduled: i.rescheduled,
      );
      return InstView(i, c, customerById[c.customerId]!, paid, st);
    }).toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    contractSummaries = contracts.map((c) {
      final list = instViews.where((i) => i.contract.id == c.id).toList()
        ..sort((a, b) => a.inst.sequence.compareTo(b.inst.sequence));
      final snaps = list.map((i) => InstallmentSnapshot(
          i.inst.originalAmount, i.paid,
          cancelled: i.inst.cancelled || c.status == 'cancelled',
          rescheduled: i.inst.rescheduled));
      final paid = list.fold<int>(0, (s, i) => s + i.paid);
      return ContractSummary(
          c, customerById[c.customerId]!, list, c.downPayment + paid, Ledger.outstanding(snaps));
    }).toList()
      ..sort((a, b) => b.contract.createdAt.compareTo(a.contract.createdAt));

    customerSummaries = customers
        .map((c) => CustomerSummary(
            c,
            contractSummaries.where((s) => s.contract.customerId == c.id).toList(),
            creditOf(c.id)))
        .toList();

    paymentViews = payments.map((p) {
      final rev = reversals.where((r) => r.paymentId == p.id);
      return PaymentView(p, customerById[p.customerId]!, rev.isNotEmpty,
          rev.isEmpty ? null : rev.first.reason,
          allocations.where((a) => a.paymentId == p.id).toList());
    }).toList()
      ..sort((a, b) => b.payment.createdAt.compareTo(a.payment.createdAt));
  }

  int creditOf(String customerId) => credits
      .where((c) => c.customerId == customerId)
      .fold(0, (s, c) => s + c.delta);

  CustomerSummary? customerSummary(String id) {
    for (final s in customerSummaries) {
      if (s.customer.id == id) return s;
    }
    return null;
  }

  ContractSummary? contractSummary(String id) {
    for (final s in contractSummaries) {
      if (s.contract.id == id) return s;
    }
    return null;
  }

  List<OpenInstallment> openInstallmentsOf(String customerId) => instViews
      .where((i) => i.customer.id == customerId && i.inForce && i.remaining > 0)
      .map((i) => OpenInstallment(
          id: i.inst.id,
          contractId: i.contract.id,
          customerId: customerId,
          sequence: i.inst.sequence,
          dueDate: i.due,
          remaining: i.remaining))
      .toList();

  /// Installments that still have a balance and are in force.
  List<InstView> get openViews =>
      instViews.where((i) => i.inForce && i.remaining > 0).toList();

  // ---- dashboard numbers (same logic is used by reports) ----
  List<ContractSummary> get liveContracts =>
      contractSummaries.where((c) => !c.cancelled).toList();
  int get totalContracted => liveContracts.fold(0, (s, c) => s + c.contract.finalPrice);
  int get totalCollected => liveContracts.fold(0, (s, c) => s + c.collected);
  int get totalRemaining => liveContracts.fold(0, (s, c) => s + c.remaining);
  int get expectedMarkup => liveContracts.fold(0, (s, c) => s + c.markup);
  int get realizedMarkup => liveContracts.fold(0, (s, c) => s + c.realizedMarkup);
  int get activeContractCount => liveContracts.where((c) => !c.completed).length;
  int get activeCustomerCount => customers.where((c) => c.status == 'active').length;

  List<InstView> dueOn(DateTime day) =>
      openViews.where((i) => i.due == day).toList();
  List<InstView> dueBetween(DateTime from, DateTime to) =>
      openViews.where((i) => !i.due.isBefore(from) && !i.due.isAfter(to)).toList();
  List<InstView> get overdueViews => openViews
      .where((i) => i.status.status == InstallmentStatus.overdue)
      .toList();
  static int sumRemaining(Iterable<InstView> v) =>
      v.fold(0, (s, i) => s + i.remaining);

  // ---- search ----
  List<CustomerSummary> search(String query) {
    final q = normalizeArabic(query);
    if (q.isEmpty) return customerSummaries;
    final qPhone = normalizePhone(query);
    return customerSummaries.where((s) {
      final c = s.customer;
      if (normalizeArabic(c.fullName).contains(q)) return true;
      if (qPhone.isNotEmpty &&
          (c.phone.contains(qPhone) || (c.phone2 ?? '').contains(qPhone))) {
        return true;
      }
      if (normalizeArabic('${c.address ?? ''} ${c.area ?? ''}').contains(q)) {
        return true;
      }
      return s.contracts.any((k) =>
          k.contract.contractNumber.toLowerCase().contains(q) ||
          normalizeArabic(k.contract.productName).contains(q));
    }).toList();
  }
}
