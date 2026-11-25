import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/finance/schedule.dart';
import '../core/finance/status.dart';
import '../core/formatting.dart';
import '../data/snapshot.dart';
import 'common.dart';
import 'contracts.dart';
import 'payments.dart';

enum InstFilter { all, today, tomorrow, week, month, overdue, partial, paid, upcoming }

const _labels = {
  InstFilter.all: 'الكل',
  InstFilter.today: 'اليوم',
  InstFilter.tomorrow: 'غداً',
  InstFilter.week: 'هذا الأسبوع',
  InstFilter.month: 'هذا الشهر',
  InstFilter.overdue: 'متأخر',
  InstFilter.partial: 'مدفوع جزئياً',
  InstFilter.paid: 'مدفوع',
  InstFilter.upcoming: 'قادم',
};

enum GroupBy { none, customer, contract }

class InstallmentsPage extends StatefulWidget {
  const InstallmentsPage({super.key});
  @override
  State<InstallmentsPage> createState() => _InstallmentsPageState();
}

class _InstallmentsPageState extends State<InstallmentsPage> {
  InstFilter filter = InstFilter.all;
  GroupBy group = GroupBy.none;
  bool calendar = false;

  bool _match(InstView v, DateTime t) {
    final start = t.subtract(Duration(days: (t.weekday + 1) % 7)); // week starts Saturday
    final end = start.add(const Duration(days: 6));
    switch (filter) {
      case InstFilter.all:
        return true;
      case InstFilter.today:
        return v.due == t && v.remaining > 0;
      case InstFilter.tomorrow:
        return v.due == t.add(const Duration(days: 1)) && v.remaining > 0;
      case InstFilter.week:
        return !v.due.isBefore(start) && !v.due.isAfter(end) && v.remaining > 0;
      case InstFilter.month:
        return v.due.year == t.year && v.due.month == t.month && v.remaining > 0;
      case InstFilter.overdue:
        return v.status.status == InstallmentStatus.overdue;
      case InstFilter.partial:
        return v.status.hasPartialPayment;
      case InstFilter.paid:
        return v.status.status == InstallmentStatus.paid;
      case InstFilter.upcoming:
        return v.status.status == InstallmentStatus.upcoming || v.status.status == InstallmentStatus.dueToday;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأقساط'), actions: [
        IconButton(
          tooltip: calendar ? 'عرض القائمة' : 'عرض التقويم',
          icon: Icon(calendar ? Icons.list : Icons.calendar_month),
          onPressed: () => setState(() => calendar = !calendar),
        ),
      ]),
      body: SnapshotBuilder(builder: (context, s) {
        if (calendar) return _CalendarView(s);
        final list = s.instViews.where((v) => v.inForce && _match(v, s.today)).toList();
        final children = <Widget>[];
        void tile(InstView v) => children.add(InstallmentTile(v, onTap: () => _open(context, v)));
        if (group == GroupBy.none) {
          list.forEach(tile);
        } else {
          final map = <String, List<InstView>>{};
          for (final v in list) {
            final k = group == GroupBy.customer ? v.customer.fullName : '${v.contract.contractNumber} • ${v.customer.fullName}';
            map.putIfAbsent(k, () => []).add(v);
          }
          for (final e in map.entries) {
            children.add(SectionTitle('${e.key} (${egp(Snapshot.sumRemaining(e.value))})'));
            e.value.forEach(tile);
          }
        }
        return Column(children: [
          SizedBox(
            height: 52,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              for (final f in InstFilter.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: ChoiceChip(label: Text(_labels[f]!), selected: filter == f, onSelected: (_) => setState(() => filter = f)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<GroupBy>(
              segments: const [
                ButtonSegment(value: GroupBy.none, label: Text('بدون تجميع')),
                ButtonSegment(value: GroupBy.customer, label: Text('حسب العميل')),
                ButtonSegment(value: GroupBy.contract, label: Text('حسب العقد')),
              ],
              selected: {group},
              onSelectionChanged: (v) => setState(() => group = v.first),
            ),
          ),
          Expanded(child: list.isEmpty ? const Center(child: Text('لا توجد أقساط')) : ListView(children: children)),
        ]);
      }),
    );
  }

  void _open(BuildContext context, InstView v) {
    if (v.remaining > 0) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage(customerId: v.customer.id, targetInstallmentId: v.inst.id)));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ContractPage(v.contract.id)));
    }
  }
}

class _CalendarView extends StatefulWidget {
  final Snapshot s;
  const _CalendarView(this.s);
  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> {
  late int year = widget.s.today.year;
  late int month = widget.s.today.month;
  DateTime? selected;

  static const names = ['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'];

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final offset = (DateTime.utc(year, month, 1).weekday + 1) % 7;
    final days = daysInMonth(year, month);
    final byDay = <int, List<InstView>>{};
    for (final v in s.instViews.where((v) => v.inForce && v.due.year == year && v.due.month == month)) {
      byDay.putIfAbsent(v.due.day, () => []).add(v);
    }
    final sel = selected == null ? <InstView>[] : (byDay[selected!.day] ?? []);
    return ListView(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() { month--; if (month == 0) { month = 12; year--; } selected = null; })),
        Text('$month / $year', style: Theme.of(context).textTheme.titleMedium),
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() { month++; if (month == 13) { month = 1; year++; } selected = null; })),
      ]),
      Row(children: [for (final n in names) Expanded(child: Center(child: Text(n, style: const TextStyle(fontSize: 11))))]),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(4),
        children: [
          for (var i = 0; i < offset; i++) const SizedBox.shrink(),
          for (var d = 1; d <= days; d++)
            Builder(builder: (context) {
              final list = byDay[d] ?? [];
              final open = list.where((v) => v.remaining > 0).toList();
              final overdue = open.any((v) => v.status.status == InstallmentStatus.overdue);
              final color = list.isEmpty ? null : open.isEmpty ? Colors.green : overdue ? Colors.red : Colors.orange;
              final isSel = selected?.day == d;
              return InkWell(
                onTap: () => setState(() => selected = DateTime.utc(year, month, d)),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: color?.withOpacity(0.18),
                    border: Border.all(color: isSel ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$d'),
                    if (list.isNotEmpty) Text('${list.length}', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
                  ]),
                ),
              );
            }),
        ],
      ),
      if (selected != null) ...[
        SectionTitle('أقساط ${fmtDate(selected!)}'),
        if (sel.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد أقساط في هذا اليوم')),
        for (final v in sel)
          InstallmentTile(v, onTap: () {
            if (v.remaining > 0) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage(customerId: v.customer.id, targetInstallmentId: v.inst.id)));
            } else {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ContractPage(v.contract.id)));
            }
          }),
      ],
    ]);
  }
}
