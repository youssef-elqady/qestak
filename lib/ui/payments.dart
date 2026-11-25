import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/finance/allocation.dart';
import '../core/finance/errors.dart';
import '../core/finance/money.dart';
import '../core/formatting.dart';
import '../data/export_service.dart';
import '../data/providers.dart';
import '../data/repository.dart';
import '../data/snapshot.dart';
import 'common.dart';

class PaymentPage extends ConsumerStatefulWidget {
  final String? customerId;
  final String? targetInstallmentId;
  const PaymentPage({super.key, this.customerId, this.targetInstallmentId});
  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage> {
  final key = const Uuid().v4(); // one key per screen => no duplicate submit
  String? customerId;
  final amount = TextEditingController();
  final notes = TextEditingController();
  DateTime date = today();
  String method = 'cash';
  AllocationMode mode = AllocationMode.oldestFirst;
  String? target;
  bool credit = false;
  bool saving = false;
  final manual = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    customerId = widget.customerId;
    if (widget.targetInstallmentId != null) {
      mode = AllocationMode.specific;
      target = widget.targetInstallmentId;
    }
  }

  PaymentPlan? _plan(Snapshot s, String? err(String m)) {
    if (customerId == null) return null;
    final a = parseMoneyOr0(amount.text);
    if (a <= 0) return null;
    try {
      return PaymentPlanner.plan(
        customerId: customerId!,
        amount: a,
        open: s.openInstallmentsOf(customerId!),
        mode: mode,
        excess: credit ? ExcessPolicy.keepAsCredit : ExcessPolicy.reject,
        targetInstallmentId: target,
        manualAmounts: mode == AllocationMode.manual
            ? {
                for (final e in manual.entries)
                  if (parseMoneyOr0(e.value.text) > 0) e.key: parseMoneyOr0(e.value.text)
              }
            : null,
      );
    } on PaymentValidationException catch (e) {
      err(paymentErrorText(e));
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل دفعة')),
      body: SnapshotBuilder(builder: (context, s) {
        final customers = s.customerSummaries.where((c) => c.customer.status == 'active').toList()
          ..sort((a, b) => a.customer.fullName.compareTo(b.customer.fullName));
        final open = customerId == null ? <InstView>[] : (s.openViews.where((i) => i.customer.id == customerId).toList()..sort((a, b) => a.due.compareTo(b.due)));
        String? error;
        final plan = _plan(s, (m) => error = m);
        final debt = Snapshot.sumRemaining(open);
        String name(InstView i) => '${i.contract.contractNumber} • قسط ${i.inst.sequence} • ${fmtDate(i.due)} • متبقي ${egp(i.remaining)}';
        return ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<String>(
            value: customers.any((c) => c.customer.id == customerId) ? customerId : null,
            decoration: const InputDecoration(labelText: 'العميل', border: OutlineInputBorder()),
            items: [for (final c in customers) DropdownMenuItem(value: c.customer.id, child: Text('${c.customer.fullName} - ${c.customer.phone}'))],
            onChanged: widget.customerId != null ? null : (v) => setState(() { customerId = v; target = null; manual.clear(); }),
          ),
          if (customerId != null)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('إجمالي المستحق على العميل: ${egp(debt)}', style: const TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          MoneyField(amount, 'المبلغ المدفوع', onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('تاريخ الدفع: ${fmtDate(date)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await pickDate(context, date);
              if (d != null) setState(() => date = d);
            },
          ),
          DropdownButtonFormField<String>(
            value: method,
            decoration: const InputDecoration(labelText: 'طريقة الدفع', border: OutlineInputBorder()),
            items: [for (final e in methodLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => method = v!),
          ),
          const SectionTitle('توزيع الدفعة'),
          SegmentedButton<AllocationMode>(
            segments: const [
              ButtonSegment(value: AllocationMode.oldestFirst, label: Text('الأقدم أولاً')),
              ButtonSegment(value: AllocationMode.specific, label: Text('قسط محدد')),
              ButtonSegment(value: AllocationMode.manual, label: Text('يدوي')),
            ],
            selected: {mode},
            onSelectionChanged: (v) => setState(() => mode = v.first),
          ),
          if (mode == AllocationMode.specific)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DropdownButtonFormField<String>(
                value: open.any((i) => i.inst.id == target) ? target : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'القسط', border: OutlineInputBorder()),
                items: [for (final i in open) DropdownMenuItem(value: i.inst.id, child: Text(name(i), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => target = v),
              ),
            ),
          if (mode == AllocationMode.manual)
            for (final i in open)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: manual.putIfAbsent(i.inst.id, () => TextEditingController()),
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: name(i), border: const OutlineInputBorder()),
                ),
              ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('حفظ أي زيادة كرصيد دائن للعميل'),
            subtitle: const Text('وإلا سيُرفض المبلغ الزائد عن المستحق'),
            value: credit,
            onChanged: (v) => setState(() => credit = v),
          ),
          if (plan != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('معاينة التوزيع', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final a in plan.allocations)
                    Builder(builder: (_) {
                      final v = s.instViews.firstWhere((i) => i.inst.id == a.installmentId);
                      final left = v.remaining - a.amount;
                      return Text('${v.contract.contractNumber} قسط ${v.inst.sequence} (${fmtDate(v.due)}): ${egp(a.amount)} ${left == 0 ? '← مسدد بالكامل' : '← يتبقى ${egp(left)}'}');
                    }),
                  if (plan.creditAmount > 0) Text('رصيد دائن: ${egp(plan.creditAmount)}'),
                ]),
              ),
            ),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 8),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (plan == null || saving)
                ? null
                : () async {
                    setState(() => saving = true);
                    String? id;
                    final ok = await runAction(context, ref, () async {
                      id = await ref.read(repoProvider).recordPayment(
                            customerId: customerId!,
                            amount: parseMoneyOr0(amount.text),
                            date: date,
                            method: method,
                            idempotencyKey: key,
                            notes: notes.text,
                            mode: mode,
                            excess: credit ? ExcessPolicy.keepAsCredit : ExcessPolicy.reject,
                            targetInstallmentId: target,
                            manual: mode == AllocationMode.manual
                                ? {for (final e in manual.entries) if (parseMoneyOr0(e.value.text) > 0) e.key: parseMoneyOr0(e.value.text)}
                                : null,
                          );
                    });
                    if (!mounted) return;
                    if (ok && id != null) {
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReceiptPage(id!)));
                    } else {
                      setState(() => saving = false);
                    }
                  },
            icon: const Icon(Icons.check),
            label: const Text('حفظ الدفعة'),
          ),
        ]);
      }),
    );
  }
}

class ReceiptPage extends ConsumerWidget {
  final String paymentId;
  const ReceiptPage(this.paymentId, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SnapshotBuilder(builder: (context, s) {
      final matches = s.paymentViews.where((p) => p.payment.id == paymentId);
      if (matches.isEmpty) return const Scaffold(body: Center(child: Text('الدفعة غير موجودة')));
      final p = matches.first;
      final cust = s.customerSummary(p.customer.id);
      return Scaffold(
        appBar: AppBar(title: Text('إيصال ${p.payment.receiptNumber}')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (p.reversed)
            Card(color: Colors.red.shade100, child: ListTile(title: const Text('دفعة معكوسة (ملغاة)'), subtitle: Text('السبب: ${p.reversalReason}'))),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.customer.fullName, style: Theme.of(context).textTheme.titleLarge),
                Text(p.customer.phone),
                const Divider(),
                Text('المبلغ: ${egp(p.payment.amount)}', style: Theme.of(context).textTheme.titleMedium),
                Text('التاريخ: ${fmtDate(p.payment.paymentDate)}'),
                Text('الطريقة: ${methodLabels[p.payment.method]}'),
                if (p.payment.notes != null) Text('ملاحظات: ${p.payment.notes}'),
                const Divider(),
                const Text('التوزيع', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final a in p.allocations)
                  Builder(builder: (_) {
                    final v = s.instViews.firstWhere((i) => i.inst.id == a.installmentId);
                    return Text('${v.contract.contractNumber} • قسط ${v.inst.sequence} (${fmtDate(v.due)}): ${egp(a.amount)}');
                  }),
                Builder(builder: (_) {
                  final cr = s.credits.where((c) => c.paymentId == p.payment.id && c.delta > 0).fold<int>(0, (a, c) => a + c.delta);
                  return cr > 0 ? Text('رصيد دائن: ${egp(cr)}') : const SizedBox.shrink();
                }),
                const Divider(),
                Text('المتبقي على العميل: ${egp(cust?.remaining ?? 0)}'),
              ]),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              final biz = ref.read(settingsProvider).valueOrNull?['businessName'] ?? 'قسطك';
              final f = await ExportService.receiptPdf(p, s, biz);
              await ExportService.share(f);
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('مشاركة الإيصال PDF'),
          ),
          if (!p.reversed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  final reason = await askText(context, 'عكس الدفعة', hint: 'اكتب سبب العكس (مطلوب)');
                  if (reason == null || !context.mounted) return;
                  if (!await confirm(context, 'تأكيد عكس الدفعة', 'ستبقى الدفعة الأصلية في السجل وسيُنشأ قيد عكس، وتعود الأقساط إلى رصيدها السابق.', ok: 'عكس')) return;
                  if (context.mounted) {
                    await runAction(context, ref, () => ref.read(repoProvider).reversePayment(paymentId, reason), success: 'تم عكس الدفعة');
                  }
                },
                icon: const Icon(Icons.undo),
                label: const Text('عكس الدفعة'),
              ),
            ),
        ]),
      );
    });
  }
}
