import 'package:flutter_test/flutter_test.dart';
import 'package:qestak/core/finance/allocation.dart';
import 'package:qestak/core/finance/errors.dart';
import 'package:qestak/core/finance/ledger.dart';
import 'package:qestak/core/finance/money.dart';
import 'package:qestak/core/finance/pricing.dart';
import 'package:qestak/core/finance/schedule.dart';
import 'package:qestak/core/finance/status.dart';

int egp(int v) => v * 100;
DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

OpenInstallment inst(String id, int seq, DateTime due, int remainingEgp,
        {String customer = 'c1', String contract = 'k1'}) =>
    OpenInstallment(
        id: id,
        contractId: contract,
        customerId: customer,
        sequence: seq,
        dueDate: due,
        remaining: egp(remainingEgp));

void main() {
  group('Money', () {
    test('parse and format', () {
      expect(Money.parseEgp('2,000'), egp(2000));
      expect(Money.parseEgp('٢٬٠٠٠٫٥٠'), 200050);
      expect(Money.parseEgp('1500.5'), 150050);
      expect(() => Money.parseEgp('1.234'), throwsFormatException);
      expect(Money.formatEgp(200050), '2,000.50');
      expect(Money.formatEgp(egp(24000)), '24,000');
      expect(Money.parsePercentToBps('12.5'), 1250);
    });
    test('distributeEvenly sums exactly', () {
      expect(Money.distributeEvenly(10000, 3), [3334, 3333, 3333]);
      for (final n in [1, 2, 3, 7, 10, 12, 36]) {
        expect(Money.distributeEvenly(1234567, n).fold(0, (a, b) => a + b),
            1234567);
      }
    });
    test('roundDiv is half-up', () {
      expect(Money.roundDiv(10005000, 10000), 1001);
      expect(Money.roundDiv(10004999, 10000), 1000);
    });
  });

  group('Pricing', () {
    test('percentage markup (spec example)', () {
      final r = PricingCalculator.calculate(
          cashPrice: egp(20000),
          type: MarkupType.percentage,
          markupValue: 2000,
          downPayment: egp(4000));
      expect(r.finalPrice, egp(24000));
      expect(r.markupAmount, egp(4000));
      expect(r.financedAmount, egp(20000));
      final s = ScheduleGenerator.generate(
          financedAmount: r.financedAmount,
          count: 10,
          frequency: PaymentFrequency.monthly,
          firstDate: d(2025, 1, 5));
      expect(s.every((i) => i.amount == egp(2000)), isTrue);
    });
    test('fixed and manual', () {
      expect(
          PricingCalculator.calculate(
                  cashPrice: egp(5000),
                  type: MarkupType.fixed,
                  markupValue: egp(1500))
              .finalPrice,
          egp(6500));
      expect(
          PricingCalculator.calculate(
                  cashPrice: egp(5000),
                  type: MarkupType.manualFinalPrice,
                  markupValue: egp(7000))
              .markupAmount,
          egp(2000));
    });
    test('rejects invalid input', () {
      expect(
          () => PricingCalculator.calculate(
              cashPrice: egp(100),
              type: MarkupType.manualFinalPrice,
              markupValue: egp(50)),
          throwsA(isA<PricingException>()));
      expect(
          () => PricingCalculator.calculate(
              cashPrice: egp(100),
              type: MarkupType.fixed,
              markupValue: 0,
              downPayment: egp(101)),
          throwsA(isA<PricingException>()));
    });
    test('rounding half-up on percentage', () {
      final r = PricingCalculator.calculate(
          cashPrice: 10005, type: MarkupType.percentage, markupValue: 1000);
      expect(r.markupAmount, 1001);
    });
  });

  group('Schedule', () {
    List<DateTime> dates(DateTime first, int n,
            {int? day, PaymentFrequency f = PaymentFrequency.monthly}) =>
        ScheduleGenerator.generate(
                financedAmount: egp(1000),
                count: n,
                frequency: f,
                firstDate: first,
                preferredDay: day)
            .map((e) => e.dueDate)
            .toList();

    test('month-end in leap year', () {
      expect(dates(d(2024, 1, 31), 4),
          [d(2024, 1, 31), d(2024, 2, 29), d(2024, 3, 31), d(2024, 4, 30)]);
    });
    test('month-end in non-leap year', () {
      expect(dates(d(2023, 1, 31), 2)[1], d(2023, 2, 28));
    });
    test('year rollover and clamping', () {
      expect(dates(d(2024, 11, 30), 5)[3], d(2025, 2, 28));
    });
    test('preferred day', () {
      expect(dates(d(2024, 1, 15), 3, day: 31)[1], d(2024, 2, 29));
    });
    test('weekly', () {
      expect(dates(d(2024, 1, 1), 3, f: PaymentFrequency.weekly),
          [d(2024, 1, 1), d(2024, 1, 8), d(2024, 1, 15)]);
    });
    test('custom schedule validation', () {
      final ok = [ScheduleItem(1, d(2024, 1, 1), 500), ScheduleItem(2, d(2024, 2, 1), 700)];
      expect(ScheduleGenerator.validateCustom(ok, 1200), isNull);
      expect(ScheduleGenerator.validateCustom(ok, 1000), isNotNull);
    });
  });

  group('Status', () {
    StatusInfo s(int paid, DateTime due, DateTime today, {int grace = 0}) =>
        StatusCalculator.compute(
            original: egp(2000),
            paid: egp(paid),
            dueDate: due,
            today: today,
            graceDays: grace);
    test('upcoming / due today / overdue / paid / partial', () {
      expect(s(0, d(2025, 3, 10), d(2025, 3, 1)).status,
          InstallmentStatus.upcoming);
      expect(s(0, d(2025, 3, 10), d(2025, 3, 10)).status,
          InstallmentStatus.dueToday);
      expect(s(0, d(2025, 3, 10), d(2025, 3, 11)).status,
          InstallmentStatus.overdue);
      expect(s(2000, d(2025, 3, 10), d(2025, 4, 1)).status,
          InstallmentStatus.paid);
      expect(s(1000, d(2025, 3, 10), d(2025, 3, 1)).status,
          InstallmentStatus.partiallyPaid);
    });
    test('partial and overdue keeps partial flag', () {
      final r = s(1000, d(2025, 3, 10), d(2025, 3, 20));
      expect(r.status, InstallmentStatus.overdue);
      expect(r.hasPartialPayment, isTrue);
      expect(r.daysOverdue, 10);
    });
    test('grace period', () {
      expect(s(0, d(2025, 3, 10), d(2025, 3, 12), grace: 3).status,
          InstallmentStatus.upcoming);
    });
  });

  group('Allocation', () {
    final open = [
      inst('jan', 1, d(2025, 1, 1), 1000),
      inst('feb', 2, d(2025, 2, 1), 2000),
      inst('mar', 3, d(2025, 3, 1), 2000),
    ];
    Map<String, int> m(PaymentPlan p) =>
        {for (final a in p.allocations) a.installmentId: a.amount};

    test('oldest-first (spec example 2,500)', () {
      final p = PaymentPlanner.plan(
          customerId: 'c1', amount: egp(2500), open: open);
      expect(m(p), {'jan': egp(1000), 'feb': egp(1500)});
      expect(p.creditAmount, 0);
    });
    test('partial then completing payment', () {
      final one = [inst('a', 1, d(2025, 1, 1), 2000)];
      final p1 =
          PaymentPlanner.plan(customerId: 'c1', amount: egp(1000), open: one);
      expect(p1.allocatedTotal, egp(1000));
      final two = [inst('a', 1, d(2025, 1, 1), 1000)];
      final p2 =
          PaymentPlanner.plan(customerId: 'c1', amount: egp(1000), open: two);
      expect(p2.allocatedTotal, egp(1000));
    });
    test('specific target with spill to later installments', () {
      final p = PaymentPlanner.plan(
          customerId: 'c1',
          amount: egp(2500),
          open: open,
          mode: AllocationMode.specific,
          targetInstallmentId: 'jan',
          excess: ExcessPolicy.applyToNextInstallments);
      expect(m(p), {'jan': egp(1000), 'feb': egp(1500)});
    });
    test('specific target, excess kept as credit', () {
      final p = PaymentPlanner.plan(
          customerId: 'c1',
          amount: egp(1500),
          open: open,
          mode: AllocationMode.specific,
          targetInstallmentId: 'jan',
          excess: ExcessPolicy.keepAsCredit);
      expect(m(p), {'jan': egp(1000)});
      expect(p.creditAmount, egp(500));
    });
    test('manual distribution', () {
      final p = PaymentPlanner.plan(
          customerId: 'c1',
          amount: egp(2500),
          open: open,
          mode: AllocationMode.manual,
          manualAmounts: {'jan': egp(500), 'mar': egp(2000)});
      expect(p.allocatedTotal, egp(2500));
    });
    test('manual validation', () {
      expect(
          () => PaymentPlanner.plan(
              customerId: 'c1',
              amount: egp(100),
              open: open,
              mode: AllocationMode.manual,
              manualAmounts: {'jan': egp(500)}),
          throwsA(isA<PaymentValidationException>()));
      expect(
          () => PaymentPlanner.plan(
              customerId: 'c1',
              amount: egp(5000),
              open: open,
              mode: AllocationMode.manual,
              manualAmounts: {'jan': egp(2000)}),
          throwsA(isA<PaymentValidationException>()));
    });
    test('excess over total debt: rejected unless credit chosen', () {
      expect(
          () => PaymentPlanner.plan(
              customerId: 'c1', amount: egp(6000), open: open),
          throwsA(isA<PaymentValidationException>()));
      final p = PaymentPlanner.plan(
          customerId: 'c1',
          amount: egp(6000),
          open: open,
          excess: ExcessPolicy.keepAsCredit);
      expect(p.allocatedTotal, egp(5000));
      expect(p.creditAmount, egp(1000));
      expect(p.allocatedTotal + p.creditAmount, p.amount);
    });
    test('zero/negative amount and foreign customer rejected', () {
      for (final a in [0, -100]) {
        expect(
            () => PaymentPlanner.plan(customerId: 'c1', amount: a, open: open),
            throwsA(isA<PaymentValidationException>()));
      }
      expect(
          () => PaymentPlanner.plan(customerId: 'c2', amount: 100, open: open),
          throwsA(isA<PaymentValidationException>()));
    });
    test('customer with no open installments', () {
      expect(
          () => PaymentPlanner.plan(customerId: 'c1', amount: 100, open: []),
          throwsA(isA<PaymentValidationException>()));
      final p = PaymentPlanner.plan(
          customerId: 'c1',
          amount: 100,
          open: [],
          excess: ExcessPolicy.keepAsCredit);
      expect(p.creditAmount, 100);
    });
    test('multiple contracts: oldest due date first across contracts', () {
      final mixed = [
        inst('b1', 1, d(2025, 2, 1), 1000, contract: 'k2'),
        inst('a1', 1, d(2025, 1, 1), 1000, contract: 'k1'),
      ];
      final p = PaymentPlanner.plan(
          customerId: 'c1', amount: egp(1000), open: mixed);
      expect(p.allocations.single.installmentId, 'a1');
    });
  });

  group('Ledger and reversal', () {
    test('multiple partial payments are kept separately', () {
      final recs = [
        const AllocationRecord('p1', 'i1', 100000, false),
        const AllocationRecord('p2', 'i1', 100000, false),
      ];
      final snap = Ledger.snapshot(200000, 'i1', recs);
      expect(snap.paid, 200000);
      expect(snap.remaining, 0);
      expect(recs.length, 2);
    });
    test('reversed allocation is no longer counted', () {
      final recs = [
        const AllocationRecord('p1', 'i1', 100000, false),
        const AllocationRecord('p2', 'i1', 100000, true),
      ];
      expect(Ledger.snapshot(200000, 'i1', recs).remaining, 100000);
    });
    test('over-allocation is detected', () {
      expect(
          () => Ledger.snapshot(
              100, 'i1', [const AllocationRecord('p', 'i1', 200, false)]),
          throwsStateError);
    });
    test('outstanding excludes cancelled/rescheduled', () {
      expect(
          Ledger.outstanding(const [
            InstallmentSnapshot(1000, 400),
            InstallmentSnapshot(1000, 0, cancelled: true),
            InstallmentSnapshot(1000, 0, rescheduled: true),
          ]),
          600);
    });
    test('reversal requires reason, once, and unconsumed credit', () {
      expect(
          () => ReversalPlanner.plan(
              paymentId: 'p',
              reason: '  ',
              allocationsOfPayment: [],
              alreadyReversed: false),
          throwsA(isA<PaymentValidationException>()));
      expect(
          () => ReversalPlanner.plan(
              paymentId: 'p',
              reason: 'typo',
              allocationsOfPayment: [],
              alreadyReversed: true),
          throwsA(isA<PaymentValidationException>()));
      expect(
          () => ReversalPlanner.plan(
              paymentId: 'p',
              reason: 'typo',
              allocationsOfPayment: [],
              alreadyReversed: false,
              creditCreatedByPayment: 500,
              currentCustomerCredit: 100),
          throwsA(isA<PaymentValidationException>()));
      final ok = ReversalPlanner.plan(
          paymentId: 'p',
          reason: 'typo',
          allocationsOfPayment: [],
          alreadyReversed: false,
          creditCreatedByPayment: 500,
          currentCustomerCredit: 500);
      expect(ok.creditToRemove, 500);
    });
  });
}
