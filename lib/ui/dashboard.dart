import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../core/formatting.dart';
import '../data/providers.dart';
import '../data/snapshot.dart';
import 'common.dart';
import 'contracts.dart';
import 'customers.dart';
import 'payments.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    return Scaffold(
      appBar: AppBar(title: Text(settings['businessName'] ?? 'قسطك')),
      body: SnapshotBuilder(builder: (context, s) {
        final t = s.today;
        final todayList = s.dueOn(t);
        final tomorrow = s.dueOn(t.add(const Duration(days: 1)));
        final week = s.dueBetween(t.add(const Duration(days: 1)), t.add(const Duration(days: 7)));
        final overdue = s.overdueViews;
        final lastBackup = DateTime.tryParse(settings['lastBackupAt'] ?? '');
        final needBackup = s.customers.isNotEmpty &&
            (lastBackup == null || DateTime.now().difference(lastBackup).inDays >= 7);
        final follow = s.followUps.where((f) => !f.completed).toList()
          ..sort((a, b) => a.followUpDate.compareTo(b.followUpDate));
        return ListView(padding: const EdgeInsets.all(12), children: [
          if (needBackup)
            Card(
              color: Colors.orange.shade100,
              child: ListTile(
                leading: const Icon(Icons.backup, color: Colors.orange),
                title: Text(lastBackup == null ? 'لم تقم بعمل نسخة احتياطية بعد' : 'آخر نسخة احتياطية منذ ${DateTime.now().difference(lastBackup).inDays} يوم', style: const TextStyle(color: Colors.black87)),
                subtitle: const Text('افتح الإعدادات لإنشاء نسخة احتياطية', style: TextStyle(color: Colors.black54)),
                onTap: () => ref.read(tabProvider.notifier).state = 5,
              ),
            ),
          Wrap(spacing: 8, runSpacing: 4, children: [
            ActionChip(avatar: const Icon(Icons.person_add, size: 18), label: const Text('إضافة عميل'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerFormPage()))),
            ActionChip(avatar: const Icon(Icons.note_add, size: 18), label: const Text('إنشاء عقد'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContractFormPage()))),
            ActionChip(avatar: const Icon(Icons.payments, size: 18), label: const Text('تسجيل دفعة'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentPage()))),
            ActionChip(avatar: const Icon(Icons.today, size: 18), label: const Text('أقساط اليوم'), onPressed: () => ref.read(tabProvider.notifier).state = 3),
            ActionChip(avatar: const Icon(Icons.search, size: 18), label: const Text('بحث عن عميل'), onPressed: () => ref.read(tabProvider.notifier).state = 1),
          ]),
          const SectionTitle('الملخص المالي'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.2,
            children: [
              StatCard('إجمالي قيمة العقود', egp(s.totalContracted)),
              StatCard('إجمالي المحصل', egp(s.totalCollected), color: QestakColors.paid),
              StatCard('إجمالي المتبقي', egp(s.totalRemaining)),
              StatCard('الربح المتوقع (تعاقدي)', egp(s.expectedMarkup)),
              StatCard('الربح المحقق (تناسبي)', egp(s.realizedMarkup), color: QestakColors.gold),
              StatCard('العملاء النشطون', '${s.activeCustomerCount}'),
              StatCard('العقود النشطة', '${s.activeContractCount}'),
              StatCard('المطلوب اليوم', egp(Snapshot.sumRemaining(todayList)), color: QestakColors.upcoming),
            ],
          ),
          const SectionTitle('التحصيل'),
          Card(
            child: Column(children: [
              _row('أقساط اليوم', todayList, ref, QestakColors.upcoming),
              _row('أقساط الغد', tomorrow, ref, QestakColors.upcoming),
              _row('خلال 7 أيام', week, ref, null),
              _row('المتأخرة', overdue, ref, QestakColors.overdue),
            ]),
          ),
          const SectionTitle('متابعات قادمة'),
          if (follow.isEmpty) const Text('لا توجد متابعات'),
          for (final f in follow.take(5))
            Card(
              child: ListTile(
                dense: true,
                title: Text('${s.customerById[f.customerId]?.fullName ?? ''} • ${fmtDate(f.followUpDate)}'),
                subtitle: Text(f.customerResponse ?? f.notes ?? ''),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerPage(f.customerId))),
              ),
            ),
          const SectionTitle('آخر الدفعات'),
          for (final p in s.paymentViews.take(5))
            ListTile(
              dense: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPage(p.payment.id))),
              title: Text(p.customer.fullName),
              subtitle: Text('${p.payment.receiptNumber} • ${fmtDate(p.payment.paymentDate)}${p.reversed ? ' • معكوسة' : ''}'),
              trailing: Text(egp(p.payment.amount)),
            ),
          const SectionTitle('آخر العملاء'),
          for (final c in ([...s.customers]..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(5))
            ListTile(dense: true, title: Text(c.fullName), subtitle: Text(c.phone), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerPage(c.id)))),
          const SectionTitle('آخر العقود'),
          for (final k in s.contractSummaries.take(5))
            ListTile(
              dense: true,
              title: Text('${k.contract.contractNumber} • ${k.contract.productName}'),
              subtitle: Text(k.customer.fullName),
              trailing: Text(egp(k.contract.finalPrice)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContractPage(k.contract.id))),
            ),
        ]);
      }),
    );
  }

  Widget _row(String label, List<InstView> list, WidgetRef ref, Color? color) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: Text('${list.length} قسط'),
        trailing: Text(egp(Snapshot.sumRemaining(list)), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        onTap: () => ref.read(tabProvider.notifier).state = 3,
      );
}
