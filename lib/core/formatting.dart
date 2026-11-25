import 'finance/money.dart';

String egp(int piastres) => '${Money.formatEgp(piastres)} ج.م';

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String fmtDateTime(DateTime d) =>
    '${fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

DateTime today() {
  final n = DateTime.now();
  return DateTime.utc(n.year, n.month, n.day);
}

const methodLabels = {
  'cash': 'نقداً',
  'bankTransfer': 'تحويل بنكي',
  'wallet': 'محفظة إلكترونية',
  'other': 'أخرى',
};
