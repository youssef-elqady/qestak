import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme.dart';
import 'core/database/app_database.dart';
import 'data/providers.dart';
import 'data/repository.dart';
import 'ui/lock.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final settings = await Repository(db).loadSettings();
  final mode = settings['themeMode'] == 'dark'
      ? ThemeMode.dark
      : settings['themeMode'] == 'light'
          ? ThemeMode.light
          : ThemeMode.system;
  runApp(ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(db),
      themeModeProvider.overrideWith((ref) => mode),
    ],
    child: const QestakApp(),
  ));
}

class QestakApp extends ConsumerWidget {
  const QestakApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'قسطك',
      debugShowCheckedModeBanner: false,
      theme: QestakTheme.light(),
      darkTheme: QestakTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LockGate(child: Shell()),
    );
  }
}
