import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting.dart';
import '../data/backup_service.dart';
import '../data/export_service.dart';
import '../data/providers.dart';
import 'common.dart';
import 'lock.dart';

const privacyText = '''
قسطك يعمل بالكامل على هاتفك دون أي خادم أو حساب.
• جميع بيانات العملاء والعقود والدفعات تُحفظ محلياً داخل التطبيق فقط ولا تُرسل إلى أي جهة.
• لا توجد إعلانات ولا أدوات تتبع.
• النسخة الاحتياطية ملف مشفر بكلمة مرور تضعها أنت. أنت من يقرر أين تحفظه أو تشاركه.
• إذا فقدت كلمة مرور النسخة الاحتياطية فلا يمكن استرجاعها بأي وسيلة.
• إذا فقدت هاتفك دون نسخة احتياطية تضيع البيانات. أنشئ نسخة بشكل دوري.
• رمز القفل يُخزن بصيغة مشفرة (hash) ولا يمكن استرجاعه إذا نسيته.
''';

Future<String?> askPassword(BuildContext context, {required bool confirmMode, String title = 'كلمة مرور النسخة الاحتياطية'}) {
  final a = TextEditingController();
  final b = TextEditingController();
  String? err;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (confirmMode)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('احتفظ بكلمة المرور في مكان آمن. إذا فقدتها لن يمكن فتح النسخة الاحتياطية أبداً.', style: TextStyle(color: Colors.orange)),
              ),
            TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور (6 أحرف على الأقل)')),
            if (confirmMode) TextField(controller: b, obscureText: true, decoration: InputDecoration(labelText: 'تأكيد كلمة المرور', errorText: err)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (a.text.length < 6) return set(() => err = 'كلمة المرور قصيرة');
              if (confirmMode && a.text != b.text) return set(() => err = 'غير متطابقة');
              Navigator.pop(c, a.text);
            },
            child: const Text('موافق'),
          ),
        ],
      ),
    ),
  );
}

void _busy(BuildContext context, String msg) => showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Expanded(child: Text(msg))]))),
    );

void _unbusy(BuildContext context) => Navigator.of(context, rootNavigator: true).pop();

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final pw = await askPassword(context, confirmMode: true);
    if (pw == null || !context.mounted) return;
    _busy(context, 'جاري إنشاء النسخة المشفرة...');
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      final f = await ref.read(backupProvider).createBackup(pw);
      await ref.read(repoProvider).setSetting('lastBackupAt', DateTime.now().toIso8601String());
      refreshAll(ref);
      if (!context.mounted) return;
      _unbusy(context);
      await ExportService.share(f, text: 'نسخة احتياطية من قسطك');
    } on BackupException catch (e) {
      if (context.mounted) { _unbusy(context); snack(context, e.message); }
    } catch (e) {
      if (context.mounted) { _unbusy(context); snack(context, 'فشل إنشاء النسخة: $e'); }
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final pick = await FilePicker.platform.pickFiles();
    final path = pick?.files.single.path;
    if (path == null || !context.mounted) return;
    final pw = await askPassword(context, confirmMode: false, title: 'كلمة مرور النسخة');
    if (pw == null || !context.mounted) return;
    final svc = ref.read(backupProvider);
    _busy(context, 'جاري فحص النسخة...');
    await Future.delayed(const Duration(milliseconds: 150));
    OpenedBackup opened;
    try {
      opened = await svc.open(path, pw);
    } on BackupException catch (e) {
      if (context.mounted) { _unbusy(context); snack(context, e.message); }
      return;
    }
    if (!context.mounted) return;
    _unbusy(context);

    final snap = ref.read(snapshotProvider).valueOrNull;
    final hasData = snap != null && (snap.customers.isNotEmpty || snap.contracts.isNotEmpty);
    var backupCurrent = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('تأكيد الاسترجاع'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تاريخ النسخة: ${fmtDateTime(opened.summary.createdAt)}'),
            Text('العملاء: ${opened.summary.customers}'),
            Text('العقود: ${opened.summary.contracts}'),
            Text('الدفعات: ${opened.summary.payments}'),
            const Divider(),
            if (hasData) ...[
              Text('تحذير: سيتم استبدال كل البيانات الحالية (${snap.customers.length} عميل، ${snap.payments.length} دفعة) بالكامل. لا يتم دمج النسختين.', style: const TextStyle(color: Colors.red)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: backupCurrent,
                onChanged: (v) => set(() => backupCurrent = v ?? true),
                title: const Text('إنشاء نسخة من بياناتي الحالية أولاً (بنفس كلمة المرور)'),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('استرجاع')),
          ],
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    _busy(context, 'جاري الاسترجاع...');
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      if (hasData && backupCurrent) {
        final f = await svc.createBackup(pw, kind: 'pre-restore');
        if (context.mounted) snack(context, 'حُفظت نسخة البيانات القديمة: ${f.path.split('/').last}');
      }
      await svc.restore(opened);
      refreshAll(ref);
      ref.read(lockedProvider.notifier).state = false;
      final s = await ref.read(repoProvider).loadSettings();
      ref.read(themeModeProvider.notifier).state = _mode(s['themeMode']);
      if (context.mounted) {
        _unbusy(context);
        snack(context, 'تم الاسترجاع بنجاح');
      }
    } on BackupException catch (e) {
      if (context.mounted) { _unbusy(context); snack(context, 'فشل الاسترجاع (لم تتغير بياناتك): ${e.message}'); }
    } catch (e) {
      if (context.mounted) { _unbusy(context); snack(context, 'فشل الاسترجاع (لم تتغير بياناتك): $e'); }
    }
  }

  static ThemeMode _mode(String? s) => s == 'dark' ? ThemeMode.dark : s == 'light' ? ThemeMode.light : ThemeMode.system;

  Future<void> _setPin(BuildContext context, WidgetRef ref) async {
    final pin = await askText(context, 'رمز القفل الجديد', hint: '4 إلى 8 أرقام', obscure: true, type: TextInputType.number);
    if (pin == null || !context.mounted) return;
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) return snack(context, 'الرمز يجب أن يكون من 4 إلى 8 أرقام');
    final salt = newSalt();
    final h = await hashPin(pin, salt);
    final repo = ref.read(repoProvider);
    await repo.setSetting('pinSalt', salt);
    await repo.setSetting('pinHash', h);
    ref.read(lockedProvider.notifier).state = false;
    refreshAll(ref);
    if (context.mounted) snack(context, 'تم تفعيل القفل. إذا نسيت الرمز لن يمكن استرجاعه إلا بحذف التطبيق (احتفظ بنسخة احتياطية).');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(settingsProvider).valueOrNull ?? {};
    final repo = ref.read(repoProvider);
    final hasPin = (m['pinHash'] ?? '').isNotEmpty;
    final last = DateTime.tryParse(m['lastBackupAt'] ?? '');
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(children: [
        const SectionTitle('النشاط'),
        ListTile(
          title: const Text('اسم النشاط (يظهر في الإيصالات والتقارير)'),
          subtitle: Text(m['businessName'] ?? 'قسطك'),
          trailing: const Icon(Icons.edit),
          onTap: () async {
            final v = await askText(context, 'اسم النشاط');
            if (v != null && v.trim().isNotEmpty) {
              await repo.setSetting('businessName', v.trim());
              refreshAll(ref);
            }
          },
        ),
        const SectionTitle('المظهر'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('تلقائي')),
              ButtonSegment(value: ThemeMode.light, label: Text('فاتح')),
              ButtonSegment(value: ThemeMode.dark, label: Text('داكن')),
            ],
            selected: {mode},
            onSelectionChanged: (v) async {
              ref.read(themeModeProvider.notifier).state = v.first;
              await repo.setSetting('themeMode', v.first.name);
            },
          ),
        ),
        const SectionTitle('الأمان'),
        ListTile(
          leading: const Icon(Icons.lock),
          title: Text(hasPin ? 'تغيير رمز القفل' : 'تفعيل رمز القفل'),
          onTap: () => _setPin(context, ref),
        ),
        if (hasPin) ...[
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('القفل التلقائي بعد'),
            trailing: DropdownButton<String>(
              value: {'15', '60', '300'}.contains(m['autoLockSeconds']) ? m['autoLockSeconds'] : '60',
              items: const [
                DropdownMenuItem(value: '15', child: Text('15 ثانية')),
                DropdownMenuItem(value: '60', child: Text('دقيقة')),
                DropdownMenuItem(value: '300', child: Text('5 دقائق')),
              ],
              onChanged: (v) async {
                await repo.setSetting('autoLockSeconds', v!);
                refreshAll(ref);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_open),
            title: const Text('إلغاء رمز القفل'),
            onTap: () async {
              if (!await confirm(context, 'إلغاء القفل', 'سيصبح التطبيق مفتوحاً بدون رمز.')) return;
              await repo.setSetting('pinHash', '');
              refreshAll(ref);
            },
          ),
        ],
        const SectionTitle('النسخ الاحتياطي'),
        ListTile(
          leading: const Icon(Icons.backup),
          title: const Text('إنشاء نسخة احتياطية مشفرة ومشاركتها'),
          subtitle: Text(last == null ? 'لم تُنشأ نسخة بعد' : 'آخر نسخة: ${fmtDateTime(last)}'),
          onTap: () => _create(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('استرجاع نسخة احتياطية'),
          subtitle: const Text('يستبدل كل البيانات الحالية'),
          onTap: () => _restore(context, ref),
        ),
        const SectionTitle('معلومات'),
        ListTile(
          leading: const Icon(Icons.privacy_tip),
          title: const Text('سياسة الخصوصية'),
          onTap: () => showDialog(context: context, builder: (c) => AlertDialog(title: const Text('سياسة الخصوصية'), content: const SingleChildScrollView(child: Text(privacyText)), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))])),
        ),
        const ListTile(
          leading: Icon(Icons.info),
          title: Text('قسطك - الإصدار 0.2.0'),
          subtitle: Text('الإشعارات والبصمة غير متاحة في هذا الإصدار.'),
        ),
      ]),
    );
  }
}
