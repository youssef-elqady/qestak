import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/finance/errors.dart';
import '../core/finance/money.dart';
import '../core/finance/pricing.dart';
import '../core/finance/schedule.dart';
import '../core/formatting.dart';
import '../data/export_service.dart';
import '../data/providers.dart';
import '../data/reports.dart';
import '../data/snapshot.dart';
import 'collections.dart';
import 'common.dart';
import 'payments.dart';

class ContractFormPage extends ConsumerStatefulWidget {
  final String? customerId;
  const ContractFormPage({super.key, this.customerId});
  @override
  ConsumerState<ContractFormPage> createState() => _ContractFormPageState();
}

class _ContractFormPageState extends ConsumerState<ContractFormPage> {
  final _form = GlobalKey<FormState>();
  String? customerId;
  final product = TextEditingController();
  final desc = TextEditingController();
  final cash = TextEditingController();
  final markup = TextEditingController();
  final down = TextEditingController();
  final count = TextEditingController(text: '10');
  final prefDay = TextEditingController();
  final grace = TextEditingController(text: '0');
  final notes = TextEditingController();
  MarkupType type = MarkupType.percentage;
  PaymentFrequency freq = PaymentFrequency.monthly;
  DateTime first = today().add(const Duration(days: 30));
  List<ScheduleItem>? items; // step 2 when not null
  bool edited = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    customerId = widget.customerId;
  }

  int get _count => int.tryParse(count.text.trim()) ?? 0;

  /// Returns null and fills [err] when inputs are not valid yet.
  PricingResult? _pricing(void Function(String) err) {
    try {
      final c = parseMoneyOr0(cash.text);
      final m = type == MarkupType.percentage
          ? (markup.text.trim().isEmpty ? 0 : Money.parsePercentToBps(markup.text))
          : parseMoneyOr0(markup.text);
      if (c <= 0) return null;
      return PricingCalculator.calculate(cashPrice: c, type: type, markupValue: m, downPayment: parseMoneyOr0(down.text));
    } on PricingException catch (e) {
      err(e.message == 'Down payment exceeds final price'
          ? 'المقدم أكبر من السعر النهائي'
          : e.message == 'Final price cannot be below cash price'
              ? 'السعر النهائي أقل من السعر النقدي'
              : 'بيانات التسعير غير صحيحة');
      return null;
    } on FormatException {
      err('قيمة غير صحيحة');
      return null;
    }
  }

  void _toSchedule(PricingResult p) {
    final pd = int.tryParse(prefDay.text.trim());
    setState(() {
      items = ScheduleGenerator.generate(
          financedAmount: p.financedAmount,
          count: _count,
          frequency: freq,
          firstDate: first,
          preferredDay: (pd != null && pd >= 1 && pd <= 31) ? pd : null);
      edited = false;
    });
  }

  List<ScheduleItem> _renumber(List<ScheduleItem> l) =>
      [for (var i = 0; i < l.length; i++) ScheduleItem(i + 1, l[i].dueDate, l[i].amount)];

  Future<void> _editItem(int idx) async {
    final ctl = TextEditingController(text: Money.formatEgp(items![idx].amount).replaceAll(',', ''));
    var date = items![idx].dueDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('القسط ${idx + 1}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            MoneyField(ctl, 'المبلغ'),
            ListTile(
              title: Text('الاستحقاق: ${fmtDate(date)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await pickDate(c, date);
                if (d != null) set(() => date = d);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final a = parseMoneyOr0(ctl.text);
      if (a > 0) {
        setState(() {
          final l = [...items!];
          l[idx] = ScheduleItem(idx + 1, date, a);
          items = l;
          edited = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String? perr;
    final p = _pricing((m) => perr = m);
    return Scaffold(
      appBar: AppBar(title: Text(items == null ? 'عقد تقسيط جديد' : 'مراجعة جدول الأقساط')),
      body: SnapshotBuilder(builder: (context, s) {
        final customers = s.customerSummaries.where((c) => c.customer.status == 'active').toList()
          ..sort((a, b) => a.customer.fullName.compareTo(b.customer.fullName));
        return items == null ? _step1(customers, p, perr) : _step2(p!);
      }),
    );
  }

  Widget _tf(TextEditingController c, String label,
          {bool req = false, TextInputType? type, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          keyboardType: type,
          maxLines: lines,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          validator: req ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null : null,
        ),
      );

  Widget _step1(List<CustomerSummary> customers, PricingResult? p, String? perr) {
    final n = _count;
    final firstInstallment = (p != null && n > 0) ? Money.distributeEvenly(p.financedAmount, n).first : null;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            value: customers.any((c) => c.customer.id == customerId) ? customerId : null,
            decoration: const InputDecoration(labelText: 'العميل', border: OutlineInputBorder()),
            items: [for (final c in customers) DropdownMenuItem(value: c.customer.id, child: Text('${c.customer.fullName} - ${c.customer.phone}'))],
            onChanged: widget.customerId != null ? null : (v) => setState(() => customerId = v),
            validator: (v) => v == null ? 'اختر العميل' : null,
          ),
        ),
        _tf(product, 'المنتج / الصنف', req: true),
        _tf(desc, 'وصف'),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: MoneyField(cash, 'السعر النقدي الأصلي', onChanged: (_) => setState(() {}))),
        SegmentedButton<MarkupType>(
          segments: const [
            ButtonSegment(value: MarkupType.percentage, label: Text('نسبة %')),
            ButtonSegment(value: MarkupType.fixed, label: Text('مبلغ ثابت')),
            ButtonSegment(value: MarkupType.manualFinalPrice, label: Text('سعر نهائي')),
          ],
          selected: {type},
          onSelectionChanged: (v) => setState(() => type = v.first),
        ),
        const SizedBox(height: 12),
        if (type == MarkupType.percentage)
          _tf(markup, 'نسبة الزيادة %', type: const TextInputType.numberWithOptions(decimal: true))
        else
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MoneyField(markup, type == MarkupType.fixed ? 'مبلغ الزيادة' : 'السعر النهائي المتفق عليه', onChanged: (_) => setState(() {}))),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: MoneyField(down, 'الدفعة المقدمة', required: false, onChanged: (_) => setState(() {}))),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: p == null
                ? Text(perr ?? 'أدخل السعر لعرض الحساب')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('الحساب قبل التأكيد', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('السعر النقدي: ${egp(p.cashPrice)}'),
                    Text('الزيادة (الربح التعاقدي): ${egp(p.markupAmount)}'),
                    Text('السعر النهائي: ${egp(p.finalPrice)}'),
                    Text('المقدم: ${egp(p.downPayment)}'),
                    Text('المبلغ المقسط: ${egp(p.financedAmount)}'),
                    if (firstInstallment != null) Text('القسط التقريبي: ${egp(firstInstallment)} × $n'),
                  ]),
          ),
        ),
        const SizedBox(height: 12),
        _tf(count, 'عدد الأقساط', type: TextInputType.number),
        SegmentedButton<PaymentFrequency>(
          segments: const [
            ButtonSegment(value: PaymentFrequency.monthly, label: Text('شهري')),
            ButtonSegment(value: PaymentFrequency.weekly, label: Text('أسبوعي')),
          ],
          selected: {freq},
          onSelectionChanged: (v) => setState(() => freq = v.first),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('تاريخ أول قسط: ${fmtDate(first)}'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final d = await pickDate(context, first);
            if (d != null) setState(() => first = d);
          },
        ),
        _tf(prefDay, 'يوم السداد المفضل (1-31) اختياري', type: TextInputType.number),
        _tf(grace, 'فترة سماح بالأيام قبل اعتبار القسط متأخراً', type: TextInputType.number),
        _tf(notes, 'ملاحظات', lines: 2),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            if (p == null) return snack(context, perr ?? 'راجع بيانات التسعير');
            if (p.financedAmount <= 0) return snack(context, 'المبلغ المقسط يجب أن يكون أكبر من صفر');
            if (_count <= 0 || _count > 360) return snack(context, 'عدد الأقساط غير صحيح');
            _toSchedule(p);
          },
          child: const Text('التالي: مراجعة جدول الأقساط'),
        ),
      ]),
    );
  }

  Widget _step2(PricingResult p) {
    final l = items!;
    final sum = l.fold<int>(0, (a, i) => a + i.amount);
    final err = ScheduleGenerator.validateCustom(l, p.financedAmount);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: ListTile(
          title: Text('المبلغ المقسط ${egp(p.financedAmount)}'),
          subtitle: Text('مجموع الأقساط ${egp(sum)}${sum == p.financedAmount ? '' : ' • الفرق ${egp(p.financedAmount - sum)}'}'),
        ),
      ),
      for (var i = 0; i < l.length; i++)
        Card(
          child: ListTile(
            title: Text('قسط ${i + 1}: ${egp(l[i].amount)}'),
            subtitle: Text(fmtDate(l[i].dueDate)),
            onTap: () => _editItem(i),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: l.length <= 1 ? null : () => setState(() { items = _renumber([...l]..removeAt(i)); edited = true; }),
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          final last = l.last;
          items = _renumber([...l, ScheduleItem(l.length + 1, last.dueDate.add(const Duration(days: 30)), 100)]);
          edited = true;
        }),
        icon: const Icon(Icons.add),
        label: const Text('إضافة قسط'),
      ),
      if (err != null) Padding(padding: const EdgeInsets.all(8), child: Text('يجب أن يساوي مجموع الأقساط المبلغ المقسط تماماً', style: const TextStyle(color: Colors.red))),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => items = null), child: const Text('رجوع'))),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: (err != null || saving)
                ? null
                : () async {
                    setState(() => saving = true);
                    final pd = int.tryParse(prefDay.text.trim());
                    final ok = await runAction(
                        context,
                        ref,
                        () => ref.read(repoProvider).createContract(
                              customerId: customerId!,
                              productName: product.text,
                              description: desc.text,
                              pricing: p,
                              markupType: type,
                              markupValue: type == MarkupType.percentage
                                  ? (markup.text.trim().isEmpty ? 0 : Money.parsePercentToBps(markup.text))
                                  : parseMoneyOr0(markup.text),
                              frequency: edited ? 'custom' : freq.name,
                              firstDate: l.first.dueDate,
                              preferredDay: (pd != null && pd >= 1 && pd <= 31) ? pd : null,
                              graceDays: int.tryParse(grace.text.trim()) ?? 0,
                              notes: notes.text,
                              schedule: l,
                            ),
                        success: 'تم إنشاء العقد');
                    if (mounted) {
                      if (ok) {
                        Navigator.pop(context);
                      } else {
                        setState(() => saving = false);
                      }
                    }
                  },
            child: const Text('تفعيل العقد'),
          ),
        ),
      ]),
    ]);
  }
}

class ContractPage extends ConsumerWidget {
  final String contractId;
  const ContractPage(this.contractId, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SnapshotBuilder(builder: (context, s) {
      final k = s.contractSummary(contractId);
      if (k == null) return const Scaffold(body: Center(child: Text('العقد غير موجود')));
      final c = k.contract;
      final db = ref.read(dbProvider);
      return Scaffold(
        appBar: AppBar(title: Text('عقد ${c.contractNumber}'), actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final t = Reports.contractStatement(s, k);
              final biz = ref.read(settingsProvider).valueOrNull?['businessName'] ?? 'قسطك';
              final f = v == 'pdf' ? await ExportService.reportPdf(t, biz) : await ExportService.reportExcel(t);
              await ExportService.share(f);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('كشف العقد PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('كشف العقد Excel')),
            ],
          ),
        ]),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.productName, style: Theme.of(context).textTheme.titleLarge),
                if (c.description != null) Text(c.description!),
                Text('العميل: ${k.customer.fullName}'),
                Text('أنشئ في ${fmtDate(c.createdAt)} • ${k.cancelled ? 'ملغي' : k.completed ? 'مكتمل' : 'نشط'}'),
                const Divider(),
                Text('السعر النقدي: ${egp(c.cashPrice)}'),
                Text('الربح التعاقدي (متوقع): ${egp(k.markup)}'),
                Text('السعر النهائي: ${egp(c.finalPrice)}'),
                Text('المقدم: ${egp(c.downPayment)} • المقسط: ${egp(c.financedAmount)}'),
                if (c.notes != null) Text('ملاحظات: ${c.notes}'),
              ]),
            ),
          ),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.6,
            children: [
              StatCard('المحصل', egp(k.collected), color: Colors.green),
              StatCard('المتبقي', egp(k.remaining)),
              StatCard('ربح محقق (تناسبي)', egp(k.realizedMarkup)),
            ],
          ),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: k.remaining > 0 ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage(customerId: k.customer.id))) : null, icon: const Icon(Icons.payments), label: const Text('تسجيل دفعة'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => addFollowUpDialog(context, ref, k.customer.id, contractId: c.id), icon: const Icon(Icons.note_add), label: const Text('متابعة'))),
          ]),
          const SectionTitle('الأقساط'),
          for (final i in k.installments)
            Card(
              child: InstallmentTile(i, showCustomer: false, onTap: () => _installmentSheet(context, ref, i)),
            ),
          const SectionTitle('سجل التعديلات'),
          FutureBuilder(
            future: (db.select(db.financialAdjustments)
                  ..where((a) => a.contractId.equals(c.id))
                  ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
                .get(),
            builder: (context, snap) {
              final list = snap.data ?? [];
              if (list.isEmpty) return const Text('لا توجد تعديلات');
              return Column(children: [
                for (final a in list) ListTile(dense: true, title: Text('${a.kind == 'reschedule' ? 'تعديل موعد قسط' : a.kind} • ${fmtDate(a.createdAt)}'), subtitle: Text(a.reason)),
              ]);
            },
          ),
        ]),
      );
    });
  }

  void _installmentSheet(BuildContext context, WidgetRef ref, InstView i) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (i.remaining > 0)
            ListTile(
              leading: const Icon(Icons.payments),
              title: const Text('تسجيل دفعة لهذا القسط'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage(customerId: i.customer.id, targetInstallmentId: i.inst.id)));
              },
            ),
          if (i.remaining > 0)
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('تغيير موعد الاستحقاق (يُسجل في سجل التعديلات)'),
              onTap: () async {
                Navigator.pop(c);
                final d = await pickDate(context, i.due);
                if (d == null || !context.mounted) return;
                final reason = await askText(context, 'سبب التعديل', hint: 'مثال: اتفاق مع العميل');
                if (reason == null || !context.mounted) return;
                await runAction(context, ref, () => ref.read(repoProvider).moveInstallmentDate(i.inst.id, d, reason), success: 'تم تعديل الموعد');
              },
            ),
        ]),
      ),
    );
  }
}
