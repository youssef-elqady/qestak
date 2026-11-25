import 'errors.dart';

/// One row of PaymentAllocations joined with its payment's reversal state.
class AllocationRecord {
  final String paymentId;
  final String installmentId;
  final int amount;
  final bool reversed;
  const AllocationRecord(
      this.paymentId, this.installmentId, this.amount, this.reversed);
}

class InstallmentSnapshot {
  final int original;
  final int paid;
  final bool cancelled;
  final bool rescheduled;
  const InstallmentSnapshot(this.original, this.paid,
      {this.cancelled = false, this.rescheduled = false});
  int get remaining => original - paid;
}

/// Single source of truth for balances: derived from allocations, never from
/// cached counters. Dashboard and reports must call these functions.
class Ledger {
  static int paidFor(String installmentId, Iterable<AllocationRecord> all) =>
      all
          .where((a) => a.installmentId == installmentId && !a.reversed)
          .fold(0, (s, a) => s + a.amount);

  static InstallmentSnapshot snapshot(
      int original, String installmentId, Iterable<AllocationRecord> all,
      {bool cancelled = false, bool rescheduled = false}) {
    final paid = paidFor(installmentId, all);
    if (paid > original) {
      throw StateError('Installment $installmentId over-allocated');
    }
    return InstallmentSnapshot(original, paid,
        cancelled: cancelled, rescheduled: rescheduled);
  }

  /// Outstanding balance across installments still in force.
  static int outstanding(Iterable<InstallmentSnapshot> items) => items
      .where((i) => !i.cancelled && !i.rescheduled)
      .fold(0, (s, i) => s + i.remaining);
}

class ReversalPlan {
  final String paymentId;
  final String reason;
  final List<AllocationRecord> allocationsToVoid;
  final int creditToRemove;
  const ReversalPlan(
      this.paymentId, this.reason, this.allocationsToVoid, this.creditToRemove);
}

class ReversalPlanner {
  /// The original payment and allocations are never deleted; a reversal
  /// record marks them void so Ledger stops counting them.
  static ReversalPlan plan({
    required String paymentId,
    required String reason,
    required List<AllocationRecord> allocationsOfPayment,
    required bool alreadyReversed,
    int creditCreatedByPayment = 0,
    int currentCustomerCredit = 0,
  }) {
    if (reason.trim().isEmpty) {
      throw PaymentValidationException(
          PaymentErrorCode.reasonRequired, 'A reason is required');
    }
    if (alreadyReversed) {
      throw PaymentValidationException(
          PaymentErrorCode.alreadyReversed, 'Payment already reversed');
    }
    if (currentCustomerCredit < creditCreatedByPayment) {
      throw PaymentValidationException(PaymentErrorCode.creditAlreadyConsumed,
          'Credit from this payment was already applied');
    }
    return ReversalPlan(paymentId, reason.trim(), allocationsOfPayment,
        creditCreatedByPayment);
  }
}
