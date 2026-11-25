import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting.dart';
import '../data/export_service.dart';
import '../data/providers.dart';
import '../data/reports.dart';
import '../data/snapshot.dart';
import 'common.dart';

enum ReportKind { collections, paymentHistory, debt, overdue, expected, active, completed }

const _names = {
  ReportKind.collections: 'التحصيلات',
  ReportKind.paymentHistory: 'سجل الدفعات',
  ReportKind.debt: 'ديون العملاء',
  ReportKind.overdue: 'المتأخرات',
  ReportKind.expected: 'التحصيلات المتوقعة',
  ReportKind.active: 'العقود النشطة',
  ReportKind.completed: 'العقود المكتملة',
};

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  ReportKind kind = ReportKind.collections;
  late DateTime from = today();
  late DateTime to = today();
  String preset = 'day';

  void _setPreset(String p) {
    final t = today();
    setState(() {
      preset = p;
      if (p == 'day') {
        from = t; to = t;
      } else if (p == 'week') {
        from = t.subtract(Duration(days: (t.weekday + 1) % 7));
        to = from.add(const Duration(days: 6));
      } else if (p == 'month') {
        from = DateTime.utc(t.year, t.month, 1);
        to = DateTime.utc(t.year, t.month + 1, 0);
      } else if (p == 'year') {
        from = DateTime.utc(t.year, 1, 1);
        to = DateTime.utc(t.year, 12, 31);
      }
    });
  }

  ReportTable _build(Snapshot s) {
    switch (kind) {
      case ReportKind.collections:
        final title = {'day': 'التحصيلات اليومية', 'week': 'التحصيلات الأسبوعية', 'month': 'التحصيلات الشهرية', 'year': 'التحصيلات السنوية'}[preset] ?? 'تقرير التحصيلات';
        return Reports.collections(s, from, to, title: title);
      case ReportKind.paymentHistory:
        return Reports.paymentHistory(s, from, to);
      case ReportKind.debt:
        return Reports.customerDebt(s);
      case ReportKind.overdue:
        return Reports.overdue(s);
      case ReportKind.expected:
        return Reports.expected(s, from, to);
      case ReportKind.active:
        return Reports.contracts(s, completed: false);
      case ReportKind.completed:
        return Reports.contracts(s, completed: true);
    }
  }

  bool get _usesRange => kind == ReportKind.collections || kind == ReportKind.paymentHistory || kind == ReportKind.expected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: SnapshotBuilder(builder: (context, s) {
        final t = _build(s);
        return ListView(padding: const EdgeInsets.all(12), children: [
          DropdownButtonFormField<ReportKind>(
            value: kind,
            decoration: const InputDecoration(labelText: 'التقرير', border: OutlineInputBorder()),
            items: [for (final k in ReportKind.values) DropdownMenuItem(value: k, child: Text(_names[k]!))],
            onChanged: (v) => setState(() => kind = v!),
          ),
          if (_usesRange) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final e in {'day': 'اليوم', 'week': 'الأسبوع', 'month': 'الشهر', 'year': 'السنة'}.entries)
                ChoiceChip(label: Text(e.value), selected: preset == e.key, onSelected: (_) => _setPreset(e.key)),
            ]),
            Row(children: [
              Expanded(child: TextButton.icon(icon: const Icon(Icons.calendar_today), label: Text('من ${fmtDate(from)}'), onPressed: () async {
                final d = await pickDate(context, from);
                if (d != null) setState(() { from = d; preset = 'custom'; });
              })),
              Expanded(child: TextButton.icon(icon: const Icon(Icons.event), label: Text('إلى ${fmtDate(to)}'), onPressed: () async {
                final d = await pickDate(context, to);
                if (d != null) setState(() { to = d; preset = 'custom'; });
              })),
            ]),
          ],
          Row(children: [
            Expanded(child: FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF'),
              onPressed: () async {
                final biz = ref.read(settingsProvider).valueOrNull?['businessName'] ?? 'قسطك';
                await ExportService.share(await ExportService.reportPdf(t, biz));
              },
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.table_chart),
              label: const Text('Excel'),
              onPressed: () async => ExportService.share(await ExportService.reportExcel(t)),
            )),
          ]),
          SectionTitle(t.title),
          Text(t.subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [for (final h in t.headers) DataColumn(label: Text(h))],
              rows: [for (final r in t.rows) DataRow(cells: [for (final c in r) DataCell(Text(cellText(c)))])],
            ),
          ),
          if (t.rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('لا توجد بيانات'))),
          const SizedBox(height: 8),
          for (final n in t.notes) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(n)),
        ]);
      }),
    );
  }
}
