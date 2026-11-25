import '../core/formatting.dart';
import '../core/finance/status.dart';
import 'snapshot.dart';

class Amt {
  final int piastres;
  const Amt(this.piastres);
}

String cellText(Object o) => o is Amt ? egpPlain(o.piastres) : o.toString();

String egpPlain(int p) => egp(p).replaceAll(' ج.م', '');

class ReportTable {
  final String title;
  final String subtitle;
  final List<String> headers;
  final List<List<Object>> rows;
  final List<String> notes;
  const ReportTable(this.title, this.subtitle, this.headers, this.rows,
      [this.notes = const []]);
}

String statusLabel(InstallmentStatus s) {
  switch (s) {
    case InstallmentStatus.upcoming:
      return 'قادم';
    case InstallmentStatus.dueToday:
      return 'مستحق اليوم';
    case InstallmentStatus.partiallyPaid:
      return 'مدفوع جزئياً';
    case InstallmentStatus.paid:
      return 'مدفوع';
    case InstallmentStatus.overdue:
      return 'متأخر';
    case InstallmentStatus.rescheduled:
      return 'مؤجل';
    case InstallmentStatus.cancelled:
      return 'ملغي';
  }
}

String _range(DateTime a, DateTime b) => 'من ${fmtDate(a)} إلى ${fmtDate(b)}';

class Reports {
  static bool _inRange(DateTime d, DateTime from, DateTime to) {
    final x = fromStorage(d);
    return !x.isBefore(from) && !x.isAfter(to);
  }

  /// Cash received (payments), excluding reversed ones.
  static ReportTable collections(Snapshot s, DateTime from, DateTime to,
      {String title = 'تقرير التحصيلات'}) {
    final list = s.paymentViews
        .where((p) => !p.reversed && _inRange(p.payment.paymentDate, from, to))
        .toList()
      ..sort((a, b) => a.payment.paymentDate.compareTo(b.payment.paymentDate));
    final total = list.fold<int>(0, (a, p) => a + p.payment.amount);
    return ReportTable(
      title,
      _range(from, to),
      ['التاريخ', 'رقم الإيصال', 'العميل', 'الطريقة', 'المبلغ'],
      [
        for (final p in list)
          [
            fmtDate(p.payment.paymentDate),
            p.payment.receiptNumber,
            p.customer.fullName,
            methodLabels[p.payment.method] ?? p.payment.method,
            Amt(p.payment.amount),
          ]
      ],
      [
        'إجمالي المبالغ المستلمة: ${egp(total)}',
        'الدفعات المعكوسة غير محسوبة. الدفعات المقدمة عند التعاقد لا تظهر هنا.'
      ],
    );
  }

  static ReportTable paymentHistory(Snapshot s, DateTime from, DateTime to) {
    final list = s.paymentViews
        .where((p) => _inRange(p.payment.paymentDate, from, to))
        .toList()
      ..sort((a, b) => a.payment.paymentDate.compareTo(b.payment.paymentDate));
    return ReportTable(
      'سجل الدفعات',
      _range(from, to),
      ['التاريخ', 'الإيصال', 'العميل', 'المبلغ', 'الحالة'],
      [
        for (final p in list)
          [
            fmtDate(p.payment.paymentDate),
            p.payment.receiptNumber,
            p.customer.fullName,
            Amt(p.payment.amount),
            p.reversed ? 'معكوسة: ${p.reversalReason}' : 'سارية',
          ]
      ],
    );
  }

  static ReportTable customerDebt(Snapshot s) {
    final list = s.customerSummaries.where((c) => c.remaining > 0).toList()
      ..sort((a, b) => b.remaining.compareTo(a.remaining));
    final total = list.fold<int>(0, (a, c) => a + c.remaining);
    return ReportTable(
      'ديون العملاء',
      'حتى ${fmtDate(s.today)}',
      ['العميل', 'الهاتف', 'إجمالي العقود', 'المحصل', 'المتبقي'],
      [
        for (final c in list)
          [c.customer.fullName, c.customer.phone, Amt(c.contracted), Amt(c.paid), Amt(c.remaining)]
      ],
      ['إجمالي الديون: ${egp(total)}'],
    );
  }

  static ReportTable overdue(Snapshot s) {
    final list = s.overdueViews..sort((a, b) => a.due.compareTo(b.due));
    return ReportTable(
      'المتأخرات',
      'حتى ${fmtDate(s.today)}',
      ['العميل', 'العقد', 'القسط', 'الاستحقاق', 'أيام التأخير', 'المتبقي'],
      [
        for (final i in list)
          [
            i.customer.fullName,
            i.contract.contractNumber,
            '${i.inst.sequence}',
            fmtDate(i.due),
            '${i.status.daysOverdue}',
            Amt(i.remaining),
          ]
      ],
      ['إجمالي المتأخرات: ${egp(Snapshot.sumRemaining(list))}'],
    );
  }

  static ReportTable expected(Snapshot s, DateTime from, DateTime to) {
    final list = s.dueBetween(from, to)..sort((a, b) => a.due.compareTo(b.due));
    return ReportTable(
      'التحصيلات المتوقعة',
      _range(from, to),
      ['الاستحقاق', 'العميل', 'العقد', 'القسط', 'المتبقي'],
      [
        for (final i in list)
          [fmtDate(i.due), i.customer.fullName, i.contract.contractNumber, '${i.inst.sequence}', Amt(i.remaining)]
      ],
      ['إجمالي المتوقع: ${egp(Snapshot.sumRemaining(list))}'],
    );
  }

  static ReportTable contracts(Snapshot s, {required bool completed}) {
    final list = s.liveContracts.where((c) => c.completed == completed).toList();
    return ReportTable(
      completed ? 'العقود المكتملة' : 'العقود النشطة',
      'حتى ${fmtDate(s.today)}',
      ['رقم العقد', 'العميل', 'المنتج', 'السعر النقدي', 'السعر النهائي', 'الربح التعاقدي', 'المحصل', 'المتبقي', 'ربح محقق (تناسبي)'],
      [
        for (final c in list)
          [
            c.contract.contractNumber,
            c.customer.fullName,
            c.contract.productName,
            Amt(c.contract.cashPrice),
            Amt(c.contract.finalPrice),
            Amt(c.markup),
            Amt(c.collected),
            Amt(c.remaining),
            Amt(c.realizedMarkup),
          ]
      ],
      [
        'الربح التعاقدي = السعر النهائي - السعر النقدي (متوقع وليس نقداً محصلاً).',
        'الربح المحقق (تناسبي) = الربح التعاقدي × (المحصل ÷ السعر النهائي).'
      ],
    );
  }

  static ReportTable customerStatement(Snapshot s, CustomerSummary c) {
    final rows = <List<Object>>[];
    for (final k in c.contracts) {
      for (final i in k.installments) {
        rows.add([
          k.contract.contractNumber,
          '${i.inst.sequence}',
          fmtDate(i.due),
          Amt(i.inst.originalAmount),
          Amt(i.paid),
          Amt(i.remaining),
          statusLabel(i.status.status),
        ]);
      }
    }
    return ReportTable(
      'كشف حساب: ${c.customer.fullName}',
      'هاتف ${c.customer.phone} - حتى ${fmtDate(s.today)}',
      ['العقد', 'القسط', 'الاستحقاق', 'القيمة', 'المدفوع', 'المتبقي', 'الحالة'],
      rows,
      [
        'إجمالي العقود: ${egp(c.contracted)}',
        'المحصل (يشمل المقدمات): ${egp(c.paid)}',
        'المتبقي: ${egp(c.remaining)}',
        'المتأخر: ${egp(c.overdue)}',
        'رصيد العميل الدائن: ${egp(c.credit)}',
      ],
    );
  }

  static ReportTable contractStatement(Snapshot s, ContractSummary k) {
    return ReportTable(
      'كشف عقد ${k.contract.contractNumber} - ${k.contract.productName}',
      'العميل: ${k.customer.fullName} - حتى ${fmtDate(s.today)}',
      ['القسط', 'الاستحقاق', 'القيمة', 'المدفوع', 'المتبقي', 'الحالة'],
      [
        for (final i in k.installments)
          [
            '${i.inst.sequence}',
            fmtDate(i.due),
            Amt(i.inst.originalAmount),
            Amt(i.paid),
            Amt(i.remaining),
            statusLabel(i.status.status),
          ]
      ],
      [
        'السعر النقدي: ${egp(k.contract.cashPrice)}',
        'السعر النهائي: ${egp(k.contract.finalPrice)}',
        'المقدم: ${egp(k.contract.downPayment)}',
        'المحصل: ${egp(k.collected)}',
        'المتبقي: ${egp(k.remaining)}',
      ],
    );
  }
}
