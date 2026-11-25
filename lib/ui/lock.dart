import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

final lockedProvider = StateProvider<bool>((ref) => true);

Future<String> hashPin(String pin, String salt) async {
  final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 20000, bits: 256)
      .deriveKeyFromPassword(password: pin, nonce: utf8.encode(salt));
  return base64Encode(await key.extractBytes());
}

String newSalt() {
  final r = Random.secure();
  return base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
}

class LockGate extends ConsumerStatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});
  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      refreshAll(ref); // new day => statuses must be recomputed
      final m = ref.read(settingsProvider).valueOrNull ?? {};
      final secs = int.tryParse(m['autoLockSeconds'] ?? '') ?? 60;
      if ((m['pinHash'] ?? '').isNotEmpty &&
          pausedAt != null &&
          DateTime.now().difference(pausedAt!).inSeconds >= secs) {
        ref.read(lockedProvider.notifier).state = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final locked = ref.watch(lockedProvider);
    final m = settings.valueOrNull;
    if (m == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if ((m['pinHash'] ?? '').isNotEmpty && locked) {
      return PinScreen(salt: m['pinSalt'] ?? '', hash: m['pinHash']!);
    }
    return widget.child;
  }
}

class PinScreen extends ConsumerStatefulWidget {
  final String salt;
  final String hash;
  const PinScreen({super.key, required this.salt, required this.hash});
  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final ctl = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> _check() async {
    setState(() { busy = true; error = null; });
    final h = await hashPin(ctl.text, widget.salt);
    if (!mounted) return;
    if (h == widget.hash) {
      ref.read(lockedProvider.notifier).state = false;
    } else {
      setState(() { busy = false; error = 'الرمز غير صحيح'; ctl.clear(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock, size: 56),
              const SizedBox(height: 12),
              Text('قسطك', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              TextField(
                controller: ctl,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 8,
                onSubmitted: (_) => _check(),
                decoration: InputDecoration(labelText: 'أدخل رمز القفل', errorText: error, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: busy ? null : _check, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('فتح')),
            ]),
          ),
        ),
      ),
    );
  }
}
