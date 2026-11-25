import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/finance/status.dart';
import '../core/formatting.dart';
import '../data/providers.dart';
import '../data/snapshot.dart';
import 'common.dart';
import 'customers.dart';
import 'payments.dart';

Future<void> addFollowUpDialog(BuildContext context, WidgetRef ref, String customerId,
    {String? contractId}) async {
  final response = TextEditingController();
  final notes = TextEditingController();
  var date = today();
  DateTime? expected;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      return AlertDialog(
        title: const Text('ملاحظة متابعة'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: response, decoration: const InputDecoration(labelText: 'رد العميل (مثال: هيدفع الخميس)')),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('تاريخ المتابعة: ${fmtDate(date)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await pickDate(c, date);
                if (d != null) set(() => date = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(expected == null ? 'موعد الدفع المتوقع (اختياري)' : 'الدفع المتوقع: ${fmtDate(expected!)}'),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final d = await pickDate(c, expected ?? date);
                if (d != null) set(() => expected = d);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      );
    }),
  );
  if (ok == true && context.mounted) {
    await runAction(
        context,
        ref,
        () => ref.read(repoProvider).addFollowUp(
            customerId: customerId,
            contractId: contractId,
            date: date,
            response: response.text,
            expectedPayment: expected,
            notes: notes.text),
        success: 'تم حفظ المتابعة');
  }
}

class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التحصيلات'),
          bottom: const TabBar(tabs: [
            Tab(text: 'اليوم'),
            Tab(text: 'غداً'),
            Tab(text: '7 أيام'),
            Tab(text: 'متأخر'),
          ]),
        ),
        body: SnapshotBuilder(builder: (context, s) {
          final t = s.today;
          return TabBarView(children: [
            _CollectionList(s, s.dueOn(t)),
            _CollectionList(s, s.dueOn(t.add(const Duration(days: 1)))),
            _CollectionList(s, s.dueBetween(t.add(const Duration(days: 1)), t.add(const Duration(days: 7)))),
            _CollectionList(s, s.overdueViews),
          ]);
        }),
      ),
    );
  }
}

class _CollectionList extends ConsumerWidget {
  final Snapshot s;
  final List<InstView> items;
  const _CollectionList(this.s, this.items);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const Center(child: Text('لا توجد أقساط في هذه الفترة'));
    final sorted = [...items]..sort((a, b) => a.due.compareTo(b.due));
    final total = Snapshot.sumRemaining(sorted);
    final byCustomer = <String, List<InstView>>{};
    for (final i in sorted) {
      byCustomer.putIfAbsent(i.customer.id, () => []).add(i);
    }
    return ListView(padding: const EdgeInsets.all(8), children: [
      Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: ListTile(title: const Text('المطلوب تحصيله'), trailing: Text(egp(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      ),
      for (final e in byCustomer.entries)
        Builder(builder: (context) {
          final list = e.value;
          final c = list.first.customer;
          final remaining = Snapshot.sumRemaining(list);
          final partial = list.fold<int>(0, (a, i) => a + i.paid);
          final pending = s.followUps.where((f) => f.customerId == c.id && !f.completed).toList();
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerPage(c.id))),
                  title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(c.phone),
                  trailing: Text(egp(remaining), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                for (final i in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text('${i.contract.contractNumber} • قسط ${i.inst.sequence} • ${fmtDate(i.due)}')),
                      Text(egp(i.remaining)),
                      const SizedBox(width: 8),
                      StatusBadge(i.status),
                    ]),
                  ),
                if (partial > 0) Text('دفعات سابقة على هذه الأقساط: ${egp(partial)}', style: const TextStyle(fontSize: 12)),
                if (pending.isNotEmpty)
                  Text('متابعة: ${pending.first.customerResponse ?? pending.first.notes ?? fmtDate(pending.first.followUpDate)}', style: const TextStyle(fontSize: 12, color: Colors.orange)),
                Wrap(spacing: 6, children: [
                  ActionChip(avatar: const Icon(Icons.payments, size: 18), label: const Text('تسجيل دفعة'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage(customerId: c.id)))),
                  ActionChip(avatar: const Icon(Icons.call, size: 18), label: const Text('اتصال'), onPressed: () => callPhone(c.phone)),
                  ActionChip(avatar: const Icon(Icons.note_add, size: 18), label: const Text('متابعة'), onPressed: () => addFollowUpDialog(context, ref, c.id)),
                  if (pending.isNotEmpty)
                    ActionChip(
                        avatar: const Icon(Icons.check, size: 18),
                        label: const Text('تمت المتابعة'),
                        onPressed: () => runAction(context, ref, () async {
                              for (final f in pending) {
                                await ref.read(repoProvider).setFollowUpDone(f.id, true);
                              }
                            })),
                ]),
              ]),
            ),
          );
        }),
    ]);
  }
}
