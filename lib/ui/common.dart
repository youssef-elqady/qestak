import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../core/arabic.dart';
import '../core/finance/money.dart';
import '../core/finance/status.dart';
import '../core/formatting.dart';
import '../data/providers.dart';
import '../data/reports.dart';
import '../data/repository.dart';
import '../data/snapshot.dart';

Color statusColor(InstallmentStatus s) {
  switch (s) {
    case InstallmentStatus.paid:
      return QestakColors.paid;
    case InstallmentStatus.overdue:
      return QestakColors.overdue;
    case InstallmentStatus.upcoming:
    case InstallmentStatus.dueToday:
    case InstallmentStatus.partiallyPaid:
      return QestakColors.upcoming;
    default:
      return Colors.grey;
  }
}

class StatusBadge extends StatelessWidget {
  final StatusInfo info;
  const StatusBadge(this.info, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(info.status);
    var label = statusLabel(info.status);
    if (info.status == InstallmentStatus.overdue) {
      label = '$label ${info.daysOverdue} يوم';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? color;
  const StatCard(this.title, this.value, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          ),
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Builds from the shared snapshot; keeps showing old data while reloading.
class SnapshotBuilder extends ConsumerWidget {
  final Widget Function(BuildContext, Snapshot) builder;
  const SnapshotBuilder({super.key, required this.builder});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(snapshotProvider);
    final v = a.valueOrNull;
    if (v != null) return builder(context, v);
    if (a.hasError) return Center(child: Text('تعذر تحميل البيانات: ${a.error}'));
    return const Center(child: CircularProgressIndicator());
  }
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Runs a write operation, refreshes data, reports errors in Arabic.
Future<bool> runAction(BuildContext context, WidgetRef ref, Future<void> Function() action,
    {String? success}) async {
  try {
    await action();
    refreshAll(ref);
    if (success != null && context.mounted) snack(context, success);
    return true;
  } on AppException catch (e) {
    if (context.mounted) snack(context, e.message);
  } catch (e) {
    if (context.mounted) snack(context, 'حدث خطأ غير متوقع: $e');
  }
  return false;
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'تأكيد'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(BuildContext context, String title,
    {String hint = '', bool obscure = false, TextInputType? type}) async {
  final ctl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: ctl,
          autofocus: true,
          obscureText: obscure,
          keyboardType: type,
          decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('موافق')),
      ],
    ),
  );
  return r;
}

Future<DateTime?> pickDate(BuildContext context, DateTime initial) async {
  final d = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final ValueChanged<String>? onChanged;
  const MoneyField(this.controller, this.label, {super.key, this.required = true, this.onChanged});
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixText: 'ج.م'),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return required ? 'مطلوب' : null;
          try {
            if (Money.parseEgp(v) < 0) return 'قيمة غير صحيحة';
          } catch (_) {
            return 'قيمة غير صحيحة';
          }
          return null;
        },
      );
}

int parseMoneyOr0(String s) {
  try {
    return s.trim().isEmpty ? 0 : Money.parseEgp(s);
  } catch (_) {
    return 0;
  }
}

Future<void> callPhone(String phone) =>
    launchUrl(Uri(scheme: 'tel', path: phone));

Future<void> openWhatsApp(String phone) => launchUrl(
    Uri.parse('https://wa.me/${whatsappNumber(phone)}'),
    mode: LaunchMode.externalApplication);

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) snack(context, 'تم النسخ');
}

/// One installment row, used in lists everywhere.
class InstallmentTile extends StatelessWidget {
  final InstView v;
  final bool showCustomer;
  final VoidCallback? onTap;
  final Widget? trailing;
  const InstallmentTile(this.v, {super.key, this.showCustomer = true, this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) {
    final partial = v.paid > 0 && v.remaining > 0;
    return ListTile(
      onTap: onTap,
      title: Text(showCustomer ? v.customer.fullName : 'قسط ${v.inst.sequence} - ${v.contract.productName}'),
      subtitle: Text([
        if (showCustomer) '${v.contract.contractNumber} • قسط ${v.inst.sequence}',
        'الاستحقاق ${fmtDate(v.due)}',
        if (partial) 'مدفوع ${egp(v.paid)} من ${egp(v.inst.originalAmount)}',
      ].join('\n')),
      isThreeLine: showCustomer || partial,
      trailing: trailing ??
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(egp(v.remaining), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            StatusBadge(v.status),
          ]),
    );
  }
}
