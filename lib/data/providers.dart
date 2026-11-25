import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import 'backup_service.dart';
import 'repository.dart';
import 'snapshot.dart';

final dbProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());
final repoProvider = Provider<Repository>((ref) => Repository(ref.watch(dbProvider)));
final backupProvider = Provider<BackupService>((ref) => BackupService(ref.watch(dbProvider)));

/// Single authoritative financial view. Everything on screen derives from it.
final snapshotProvider = FutureProvider<Snapshot>((ref) => ref.watch(repoProvider).loadSnapshot());
final settingsProvider = FutureProvider<Map<String, String>>((ref) => ref.watch(repoProvider).loadSettings());
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final tabProvider = StateProvider<int>((ref) => 0);

void refreshAll(WidgetRef ref) {
  ref.invalidate(snapshotProvider);
  ref.invalidate(settingsProvider);
}
