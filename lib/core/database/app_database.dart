import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart'; // generated: dart run build_runner build

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
      : super(executor ?? driftDatabase(name: 'qestak'));

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
