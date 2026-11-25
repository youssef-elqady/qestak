import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/formatting.dart';
import 'reports.dart';
import 'snapshot.dart';

class ExportService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<pw.Document> _newDoc() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
    return pw.Document(theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!));
  }

  static pw.Widget _t(String s, {double size = 11, bool bold = false}) => pw.Text(
        s,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      );

  static String _safe(String s) => s.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');

  static Future<File> _write(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static Future<File> reportPdf(ReportTable t, String business) async {
    final doc = await _newDoc();
    final headers = t.headers.reversed.toList(); // RTL: first column on the right
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => [
        pw.Align(alignment: pw.Alignment.centerRight, child: _t(business, size: 12, bold: true)),
        pw.Align(alignment: pw.Alignment.centerRight, child: _t(t.title, size: 18, bold: true)),
        pw.Align(alignment: pw.Alignment.centerRight, child: _t(t.subtitle, size: 10)),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [for (final h in headers) pw.Padding(padding: const pw.EdgeInsets.all(4), child: _t(h, size: 10, bold: true))],
            ),
            for (final r in t.rows)
              pw.TableRow(children: [
                for (final c in r.reversed) pw.Padding(padding: const pw.EdgeInsets.all(4), child: _t(cellText(c), size: 10))
              ]),
          ],
        ),
        pw.SizedBox(height: 10),
        for (final n in t.notes) pw.Align(alignment: pw.Alignment.centerRight, child: _t(n, size: 10)),
      ],
    ));
    return _write('${_safe(t.title)}.pdf', await doc.save());
  }

  static Future<File> reportExcel(ReportTable t) async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([TextCellValue(t.title)]);
    sheet.appendRow([TextCellValue(t.subtitle)]);
    sheet.appendRow([for (final h in t.headers) TextCellValue(h)]);
    for (final r in t.rows) {
      sheet.appendRow([
        for (final c in r)
          c is Amt ? DoubleCellValue(c.piastres / 100) : TextCellValue(c.toString())
      ]);
    }
    for (final n in t.notes) {
      sheet.appendRow([TextCellValue(n)]);
    }
    final bytes = excel.encode();
    if (bytes == null) throw StateError('Excel encode failed');
    return _write('${_safe(t.title)}.xlsx', bytes);
  }

  static Future<File> receiptPdf(
      PaymentView p, Snapshot s, String business) async {
    final doc = await _newDoc();
    final cust = s.customerSummary(p.customer.id);
    final lines = <List<String>>[];
    for (final a in p.allocations) {
      final v = s.instViews.firstWhere((i) => i.inst.id == a.installmentId);
      lines.add([
        'عقد ${v.contract.contractNumber} - قسط ${v.inst.sequence} (${fmtDate(v.due)})',
        egp(a.amount)
      ]);
    }
    final credit = s.credits
        .where((c) => c.paymentId == p.payment.id && c.delta > 0)
        .fold<int>(0, (a, c) => a + c.delta);
    pw.Widget row(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [_t(k, bold: true), _t(v)]));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Center(child: _t(business, size: 18, bold: true)),
        pw.Center(child: _t('إيصال استلام', size: 14, bold: true)),
        if (p.reversed) pw.Center(child: _t('*** دفعة ملغاة (معكوسة): ${p.reversalReason} ***', size: 12, bold: true)),
        pw.Divider(),
        row('رقم الإيصال', p.payment.receiptNumber),
        row('التاريخ', fmtDate(p.payment.paymentDate)),
        row('العميل', p.customer.fullName),
        row('الهاتف', p.customer.phone),
        row('طريقة الدفع', methodLabels[p.payment.method] ?? p.payment.method),
        row('المبلغ المستلم', egp(p.payment.amount)),
        pw.Divider(),
        _t('توزيع الدفعة', bold: true),
        for (final l in lines) row(l[0], l[1]),
        if (credit > 0) row('رصيد دائن للعميل', egp(credit)),
        pw.Divider(),
        row('المتبقي على العميل حالياً', egp(cust?.remaining ?? 0)),
        if (p.payment.notes != null) row('ملاحظات', p.payment.notes!),
      ]),
    ));
    return _write('receipt_${p.payment.receiptNumber}.pdf', await doc.save());
  }

  static Future<void> share(File f, {String? text}) async {
    await Share.shareXFiles([XFile(f.path)], text: text);
  }
}
