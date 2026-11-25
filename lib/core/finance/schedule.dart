import 'money.dart';

enum PaymentFrequency { monthly, weekly }

class ScheduleItem {
  final int sequence; // 1-based
  final DateTime dueDate; // date-only, UTC
  final int amount; // piastres
  const ScheduleItem(this.sequence, this.dueDate, this.amount);
}

DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

class ScheduleGenerator {
  /// Month-end rule: each due date is computed from the ORIGINAL anchor day
  /// (preferredDay, else first date's day) and clamped to the month length,
  /// so Jan 31 -> Feb 28/29 -> Mar 31 -> Apr 30 (no drift).
  /// The first installment is always exactly [firstDate].
  static List<ScheduleItem> generate({
    required int financedAmount,
    required int count,
    required PaymentFrequency frequency,
    required DateTime firstDate,
    int? preferredDay,
  }) {
    if (count <= 0) throw ArgumentError('count must be > 0');
    final amounts = Money.distributeEvenly(financedAmount, count);
    final first = dateOnly(firstDate);
    final anchorDay = preferredDay ?? first.day;
    return List<ScheduleItem>.generate(count, (k) {
      final DateTime due;
      if (k == 0) {
        due = first;
      } else if (frequency == PaymentFrequency.weekly) {
        due = first.add(Duration(days: 7 * k));
      } else {
        final m0 = first.month - 1 + k;
        final y = first.year + m0 ~/ 12;
        final m = m0 % 12 + 1;
        final dim = daysInMonth(y, m);
        due = DateTime.utc(y, m, anchorDay < dim ? anchorDay : dim);
      }
      return ScheduleItem(k + 1, due, amounts[k]);
    });
  }

  /// Validates an owner-edited schedule before contract activation.
  static String? validateCustom(List<ScheduleItem> items, int financedAmount) {
    if (items.isEmpty) return 'Schedule is empty';
    var sum = 0;
    for (var i = 0; i < items.length; i++) {
      if (items[i].amount <= 0) return 'Installment ${i + 1} must be > 0';
      if (i > 0 && items[i].dueDate.isBefore(items[i - 1].dueDate)) {
        return 'Dates must not go backwards';
      }
      sum += items[i].amount;
    }
    return sum == financedAmount ? null : 'Sum differs from financed amount';
  }
}
