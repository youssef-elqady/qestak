import 'package:drift/drift.dart';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart'; // generated: dart run build_runner build

/// Runs on the raw SQLite connection right after opening, outside any
/// transaction (PRAGMA foreign_keys is ignored inside a transaction).
void enableForeignKeys(dynamic raw) => raw.execute('PRAGMA foreign_keys = ON');

QueryExecutor _openConnection() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File('${dir.path}/qestak.sqlite'),
        setup: enableForeignKeys,
      );
    });

@DriftDatabase(tables: [
  Customers,
  Contracts,
  Installments,
  Payments,
  PaymentAllocations,
  CustomerCredits,
  FinancialAdjustments,
  PaymentReversals,
  FollowUps,
  AppSettings,
  NotificationSettings,
  AuditLogs,
  BackupMetadata,
  Attachments,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Add stepwise migrations here: if (from < 2) { ... }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
