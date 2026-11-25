import 'dart:math';

import 'errors.dart';

class OpenInstallment {
  final String id;
  final String contractId;
  final String customerId;
  final int sequence;
  final DateTime dueDate;
  final int remaining;
  const OpenInstallment({
    required this.id,
    required this.contractId,
    required this.customerId,
    required this.sequence,
    required this.dueDate,
    required this.remaining,
  });
}

enum AllocationMode { oldestFirst, specific, manual }

enum ExcessPolicy {
  /// Reject any amount that cannot be allocated.
  reject,

  /// Keep the unallocated remainder as customer credit.
  keepAsCredit,

  /// (specific mode only) continue into later installments, then reject
  /// whatever is still left.
  applyToNextInstallments,
}

class PlannedAllocation {
  final String installmentId;
  final int amount;
  const PlannedAllocation(this.installmentId, this.amount);
}

class PaymentPlan {
  final int amount;
  final List<PlannedAllocation> allocations;
  final int creditAmount;
  const PaymentPlan(this.amount, this.allocations, this.creditAmount);
  int get allocatedTotal => allocations.fold(0, (s, a) => s + a.amount);
}

class PaymentPlanner {
  static int _cmp(OpenInstallment a, OpenInstallment b) {
    final d = a.dueDate.compareTo(b.dueDate);
    if (d != 0) return d;
    final c = a.contractId.compareTo(b.contractId);
    return c != 0 ? c : a.sequence.compareTo(b.sequence);
  }

  /// Pure function: decides how [amount] is split. Persisting the result is
  /// the repository's job and must happen in one DB transaction.
  /// Invariant: allocatedTotal + creditAmount == amount.
  static PaymentPlan plan({
    required String customerId,
    required int amount,
    required List<OpenInstallment> open,
    AllocationMode mode = AllocationMode.oldestFirst,
    ExcessPolicy excess = ExcessPolicy.reject,
    String? targetInstallmentId,
    Map<String, int>? manualAmounts,
  }) {
    if (amount <= 0) {
      throw PaymentValidationException(
          PaymentErrorCode.nonPositiveAmount, 'Amount must be > 0');
    }
    for (final o in open) {
      if (o.customerId != customerId) {
        throw PaymentValidationException(PaymentErrorCode.foreignContract,
            'Installment ${o.id} belongs to another customer');
      }
    }
    final sorted = open.where((o) => o.remaining > 0).toList()..sort(_cmp);
    final out = <PlannedAllocation>[];
    var left = amount;

    void take(OpenInstallment o) {
      if (left <= 0) return;
      final a = min(left, o.remaining);
      out.add(PlannedAllocation(o.id, a));
      left -= a;
    }

    switch (mode) {
      case AllocationMode.oldestFirst:
        sorted.forEach(take);
      case AllocationMode.specific:
        final idx = sorted.indexWhere((o) => o.id == targetInstallmentId);
        if (idx < 0) {
          throw PaymentValidationException(PaymentErrorCode.installmentNotOpen,
              'Target installment is not open');
        }
        take(sorted[idx]);
        if (left > 0 && excess == ExcessPolicy.applyToNextInstallments) {
          sorted.skip(idx + 1).forEach(take);
        }
      case AllocationMode.manual:
        final m = manualAmounts ?? const <String, int>{};
        var sum = 0;
        for (final e in m.entries) {
          final inst = sorted.where((o) => o.id == e.key);
          if (inst.isEmpty) {
            throw PaymentValidationException(
                PaymentErrorCode.installmentNotOpen, '${e.key} is not open');
          }
          if (e.value <= 0 || e.value > inst.first.remaining) {
            throw PaymentValidationException(
                PaymentErrorCode.manualInvalidAmount,
                'Invalid amount for ${e.key}');
          }
          sum += e.value;
          out.add(PlannedAllocation(e.key, e.value));
        }
        if (sum > amount) {
          throw PaymentValidationException(PaymentErrorCode.manualOverAllocated,
              'Manual allocations exceed payment');
        }
        left = amount - sum;
    }

    var credit = 0;
    if (left > 0) {
      if (excess == ExcessPolicy.keepAsCredit) {
        credit = left;
      } else {
        throw PaymentValidationException(PaymentErrorCode.excessWithoutPolicy,
            '$left piastres exceed what can be allocated');
      }
    }
    return PaymentPlan(amount, out, credit);
  }
}
