import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/formatting.dart';
import '../data/export_service.dart';
import '../data/providers.dart';
import '../data/reports.dart';
import '../data/repository.dart';
import '../data/snapshot.dart';
import 'collections.dart';
import 'common.dart';
import 'contracts.dart';
import 'payments.dart';

enum CustomerFilter { all, active, debt, overdue, paid, archived }

const _filterLabels = {
  CustomerFilter.all: 'كل العملاء',
  CustomerFilter.active: 'النشطون',
  CustomerFilter.debt: 'عليهم مديونية',
  CustomerFilter.overdue: 'متأخرون',
  CustomerFilter.paid: 'مسددون بالكامل',
  CustomerFilter.archived: 'المؤرشفون',
};

bool _matches(CustomerSummary c, CustomerFilter f) {
  switch (f) {
    case CustomerFilter.all:
      return true;
    case CustomerFilter.active:
      return c.customer.status == 'active';
    case CustomerFilter.debt:
      return c.remaining > 0;
    case CustomerFilter.overdue:
      return c.overdue > 0;
    case CustomerFilter.paid:
      return c.live.isNotEmpty && c.remaining == 0;
    case CustomerFilter.archived:
      return c.customer.status == 'archived';
  }
}

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});
  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  String q = '';
  CustomerFilter filter = CustomerFilter.active;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerFormPage())),
        icon: const Icon(Icons.person_add),
        label: const Text('عميل جديد'),
      ),
      body: SnapshotBuilder(builder: (context, s) {
        final list = s
            .search(q)
            .where((c) => _matches(c, filter))
            .toList()
          ..sort((a, b) => a.customer.fullName.compareTo(b.customer.fullName));
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'بحث بالاسم، الهاتف، رقم العقد، المنتج، العنوان',
                  border: OutlineInputBorder()),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final f in CustomerFilter.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: ChoiceChip(
                        label: Text(_filterLabels[f]!),
                        selected: filter == f,
                        onSelected: (_) => setState(() => filter = f)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('لا توجد نتائج'))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => CustomerTile(list[i]),
                  ),
          ),
        ]);
      }),
    );
  }
}

class CustomerTile extends StatelessWidget {
  final CustomerSummary c;
  const CustomerTile(this.c, {super.key});
  @override
  Widget build(BuildContext context) {
    final n = c.next;
    return ListTile(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerPage(c.customer.id))),
      title: Text(c.customer.fullName),
      subtitle: Text([
        c.customer.phone,
        if (n != null) 'القسط القادم ${fmtDate(n.due)}',
        if (c.customer.status == 'archived') 'مؤرشف',
      ].join(' • ')),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(egp(c.remaining), style: const TextStyle(fontWeight: FontWeight.bold)),
        if (c.overdue > 0)
          Text('متأخر ${egp(c.overdue)}', style: const TextStyle(color: Colors.red, fontSize: 12)),
      ]),
    );
  }
}

class CustomerFormPage extends ConsumerStatefulWidget {
  final Customer? existing;
  const CustomerFormPage({super.key, this.existing});
  @override
  ConsumerState<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends ConsumerState<CustomerFormPage> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.fullName);
  late final phone = TextEditingController(text: widget.existing?.phone);
  late final phone2 = TextEditingController(text: widget.existing?.phone2);
  late final address = TextEditingController(text: widget.existing?.address);
  late final area = TextEditingController(text: widget.existing?.area);
  late final notes = TextEditingController(text: widget.existing?.notes);
  bool saving = false;

  Future<void> save({bool allowDuplicate = false}) async {
    if (!_form.currentState!.validate() || saving) return;
    setState(() => saving = true);
    final repo = ref.read(repoProvider);
    try {
      if (widget.existing == null) {
        await repo.addCustomer(
            name: name.text, phone: phone.text, phone2: phone2.text,
            address: address.text, area: area.text, notes: notes.text,
            allowDuplicate: allowDuplicate);
      } else {
        await repo.updateCustomer(widget.existing!.id,
            name: name.text, phone: phone.text, phone2: phone2.text,
            address: address.text, area: area.text, notes: notes.text);
      }
      refreshAll(ref);
      if (mounted) Navigator.pop(context);
    } on DuplicateCustomerException catch (e) {
      if (mounted) {
        setState(() => saving = false);
        final ok = await confirm(context, 'عميل مكرر؟', '${e.message}\nهل تريد الحفظ على أي حال؟', ok: 'حفظ');
        if (ok) await save(allowDuplicate: true);
      }
    } on AppException catch (e) {
      if (mounted) snack(context, e.message);
      setState(() => saving = false);
    }
  }

  Widget _f(TextEditingController c, String label,
          {bool req = false, TextInputType? type, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          keyboardType: type,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          validator: req ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'عميل جديد' : 'تعديل العميل')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _f(name, 'الاسم الكامل', req: true),
          _f(phone, 'رقم الهاتف', req: true, type: TextInputType.phone),
          _f(phone2, 'رقم هاتف آخر (اختياري)', type: TextInputType.phone),
          _f(address, 'العنوان'),
          _f(area, 'المدينة / المنطقة'),
          _f(notes, 'ملاحظات', lines: 3),
          FilledButton(onPressed: saving ? null : () => save(), child: const Text('حفظ')),
        ]),
      ),
    );
  }
}

class CustomerPage extends ConsumerWidget {
  final String customerId;
  const CustomerPage(this.customerId, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SnapshotBuilder(builder: (context, s) {
      final c = s.customerSummary(customerId);
      if (c == null) return const Scaffold(body: Center(child: Text('العميل غير موجود')));
      final cu = c.customer;
      final pays = s.paymentViews.where((p) => p.customer.id == cu.id).toList();
      final follow = s.followUps.where((f) => f.customerId == cu.id).toList()
        ..sort((a, b) => b.followUpDate.compareTo(a.followUpDate));
      final archived = cu.status == 'archived';
      return Scaffold(
        appBar: AppBar(title: Text(cu.fullName), actions: [
          IconButton(
              tooltip: 'تعديل',
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerFormPage(existing: cu)))),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'archive') {
                if (c.remaining > 0 &&
                    !await confirm(context, 'أرشفة عميل عليه مديونية', 'عليه ${egp(c.remaining)}. سيبقى سجله المالي محفوظاً. متابعة؟')) {
                  return;
                }
                if (context.mounted) {
                  await runAction(context, ref, () => ref.read(repoProvider).setCustomerStatus(cu.id, archived ? 'active' : 'archived'));
                }
              } else if (v == 'pdf' || v == 'xlsx') {
                final t = Reports.customerStatement(s, c);
                final biz = ref.read(settingsProvider).valueOrNull?['businessName'] ?? 'قسطك';
                final f = v == 'pdf' ? await ExportService.reportPdf(t, biz) : await ExportService.reportExcel(t);
                await ExportService.share(f);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'archive', child: Text(archived ? 'استعادة العميل' : 'أرشفة العميل')),
              const PopupMenuItem(value: 'pdf', child: Text('كشف حساب PDF')),
              const PopupMenuItem(value: 'xlsx', child: Text('كشف حساب Excel')),
            ],
          ),
        ]),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${cu.phone}${cu.phone2 == null ? '' : ' • ${cu.phone2}'}', style: Theme.of(context).textTheme.titleMedium),
                if (cu.address != null || cu.area != null) Text([cu.address, cu.area].whereType<String>().join('، ')),
                if (cu.notes != null) Text('ملاحظات: ${cu.notes}'),
                if (archived) const Text('العميل مؤرشف', style: TextStyle(color: Colors.orange)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  ActionChip(avatar: const Icon(Icons.call, size: 18), label: const Text('اتصال'), onPressed: () => callPhone(cu.phone)),
                  ActionChip(avatar: const Icon(Icons.chat, size: 18), label: const Text('واتساب'), onPressed: () => openWhatsApp(cu.phone)),
                  ActionChip(avatar: const Icon(Icons.copy, size: 18), label: const Text('نسخ الرقم'), onPressed: () => copyText(context, cu.phone)),
                ]),
              ]),
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.2,
            children: [
              StatCard('عقود نشطة / مكتملة', '${c.activeCount} / ${c.completedCount}'),
              StatCard('إجمالي العقود', egp(c.contracted)),
              StatCard('المدفوع', egp(c.paid), color: Colors.green),
              StatCard('المتبقي', egp(c.remaining)),
              StatCard('المتأخر', egp(c.overdue), color: c.overdue > 0 ? Colors.red : null),
              StatCard('القسط القادم', c.next == null ? '-' : '${fmtDate(c.next!.due)} • ${egp(c.next!.remaining)}'),
            ],
          ),
          if (c.credit > 0) Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet), title: Text('رصيد دائن للعميل: ${egp(c.credit)}'), subtitle: const Text('منفصل عن الأقساط المسددة'))),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage(customerId: cu.id))), icon: const Icon(Icons.payments), label: const Text('تسجيل دفعة'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContractFormPage(customerId: cu.id))), icon: const Icon(Icons.note_add), label: const Text('عقد جديد'))),
          ]),
          const SectionTitle('العقود'),
          if (c.contracts.isEmpty) const Text('لا توجد عقود'),
          for (final k in c.contracts)
            Card(
              child: ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContractPage(k.contract.id))),
                title: Text('${k.contract.contractNumber} • ${k.contract.productName}'),
                subtitle: Text('النهائي ${egp(k.contract.finalPrice)} • المحصل ${egp(k.collected)}'),
                trailing: Text(k.cancelled ? 'ملغي' : k.completed ? 'مكتمل' : egp(k.remaining), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          SectionTitle('المتابعات', trailing: TextButton.icon(onPressed: () => addFollowUpDialog(context, ref, cu.id), icon: const Icon(Icons.add), label: const Text('إضافة'))),
          if (follow.isEmpty) const Text('لا توجد ملاحظات متابعة'),
          for (final f in follow)
            Card(
              child: CheckboxListTile(
                value: f.completed,
                onChanged: (v) => runAction(context, ref, () => ref.read(repoProvider).setFollowUpDone(f.id, v ?? false)),
                title: Text('${fmtDate(f.followUpDate)}${f.customerResponse == null ? '' : ' • ${f.customerResponse}'}'),
                subtitle: Text([
                  if (f.expectedPaymentDate != null) 'موعد الدفع المتوقع ${fmtDate(f.expectedPaymentDate!)}',
                  if (f.notes != null) f.notes!,
                ].join('\n')),
              ),
            ),
          const SectionTitle('سجل الدفعات'),
          if (pays.isEmpty) const Text('لا توجد دفعات'),
          for (final p in pays)
            Card(
              child: ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPage(p.payment.id))),
                title: Text('${p.payment.receiptNumber} • ${egp(p.payment.amount)}', style: TextStyle(decoration: p.reversed ? TextDecoration.lineThrough : null)),
                subtitle: Text('${fmtDate(p.payment.paymentDate)} • ${methodLabels[p.payment.method]}${p.reversed ? ' • معكوسة' : ''}'),
              ),
            ),
        ]),
      );
    });
  }
}
