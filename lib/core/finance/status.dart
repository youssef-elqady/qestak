import 'schedule.dart';

enum InstallmentStatus {
  upcoming,
  dueToday,
  partiallyPaid,
  paid,
  overdue,
  rescheduled,
  cancelled,
}

class StatusInfo {
  final InstallmentStatus status;
  final bool hasPartialPayment; // paid > 0 and remaining > 0
  final int daysOverdue;
  const StatusInfo(this.status, this.hasPartialPayment, this.daysOverdue);
}

/// Statuses are computed, never stored (except cancelled/rescheduled flags).
/// Priority: cancelled > rescheduled > paid > overdue > partiallyPaid >
/// dueToday > upcoming. A partly paid installment past its due date is
/// "overdue" with hasPartialPayment = true, so the remainder is never hidden.
class StatusCalculator {
  static StatusInfo compute({
    required int original,
    required int paid,
    required DateTime dueDate,
    required DateTime today,
    int graceDays = 0,
    bool cancelled = false,
    bool rescheduled = false,
  }) {
    final remaining = original - paid;
    final partial = paid > 0 && remaining > 0;
    if (cancelled) return StatusInfo(InstallmentStatus.cancelled, partial, 0);
    if (rescheduled) {
      return StatusInfo(InstallmentStatus.rescheduled, partial, 0);
    }
    if (remaining <= 0) {
      return const StatusInfo(InstallmentStatus.paid, false, 0);
    }
    final due = dateOnly(dueDate);
    final now = dateOnly(today);
    final lateBy = now.difference(due).inDays - graceDays;
    if (lateBy > 0) {
      return StatusInfo(InstallmentStatus.overdue, partial, lateBy);
    }
    if (partial) return const StatusInfo(InstallmentStatus.partiallyPaid, true, 0);
    if (now == due) {
      return const StatusInfo(InstallmentStatus.dueToday, false, 0);
    }
    return const StatusInfo(InstallmentStatus.upcoming, false, 0);
  }
}
