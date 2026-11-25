import 'package:drift/drift.dart';

// Conventions:
//  * UUID text primary keys.
//  * All money columns are INTEGER piastres.
//  * Foreign keys have no cascade: deleting a parent that has children fails,
//    so financial rows can never be removed by cascade. Use status/archive.
//  * Enums are stored as TEXT (see docs/SCHEMA.md).

@TableIndex(name: 'idx_customers_phone', columns: {#phone})
@TableIndex(name: 'idx_customers_search', columns: {#searchName})
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get fullName => text().withLength(min: 1, max: 200)();
  // Normalized copy for Arabic-insensitive search. Original is never changed.
  TextColumn get searchName => text()();
  TextColumn get phone => text()();
  TextColumn get phone2 => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get area => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_contracts_customer', columns: {#customerId})
class Contracts extends Table {
  TextColumn get id => text()();
  TextColumn get contractNumber => text().unique()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get productName => text()();
  TextColumn get description => text().nullable()();
  IntColumn get cashPrice => integer().check(cashPrice.isBiggerThanValue(0))();
  TextColumn get markupType => text()(); // percentage|fixed|manualFinalPrice
  IntColumn get markupValue => integer()(); // bps | piastres | final price
  IntColumn get finalPrice => integer()();
  IntColumn get downPayment => integer().withDefault(const Constant(0))();
  IntColumn get financedAmount => integer()();
  IntColumn get installmentCount => integer()();
  TextColumn get frequency => text()(); // monthly|weekly|custom
  DateTimeColumn get firstPaymentDate => dateTime()();
  IntColumn get preferredDay => integer().nullable()();
  IntColumn get graceDays => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  // draft|active|completed|cancelled
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_installments_due', columns: {#dueDate})
@TableIndex(name: 'idx_installments_contract', columns: {#contractId})
class Installments extends Table {
  TextColumn get id => text()();
  TextColumn get contractId => text().references(Contracts, #id)();
  IntColumn get sequence => integer()();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get originalAmount =>
      integer().check(originalAmount.isBiggerThanValue(0))();
  // Only persisted flags; paid/remaining/status are derived from allocations.
  BoolColumn get cancelled => boolean().withDefault(const Constant(false))();
  BoolColumn get rescheduled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {contractId, sequence}
      ];
}

@TableIndex(name: 'idx_payments_customer', columns: {#customerId})
@TableIndex(name: 'idx_payments_date', columns: {#paymentDate})
class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get receiptNumber => text().unique()();
  // Client-generated key; UNIQUE blocks duplicate submissions.
  TextColumn get idempotencyKey => text().unique()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get contractId => text().nullable().references(Contracts, #id)();
  DateTimeColumn get paymentDate => dateTime()();
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  TextColumn get method => text()(); // cash|bankTransfer|wallet|other
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_alloc_installment', columns: {#installmentId})
@TableIndex(name: 'idx_alloc_payment', columns: {#paymentId})
class PaymentAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get paymentId => text().references(Payments, #id)();
  TextColumn get installmentId => text().references(Installments, #id)();
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Signed ledger of customer credit: + when a payment leaves an unallocated
/// remainder, - when credit is later applied or its payment is reversed.
class CustomerCredits extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get paymentId => text().nullable().references(Payments, #id)();
  IntColumn get delta => integer()();
  TextColumn get reason => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class FinancialAdjustments extends Table {
  TextColumn get id => text()();
  TextColumn get contractId => text().references(Contracts, #id)();
  TextColumn get installmentId =>
      text().nullable().references(Installments, #id)();
  TextColumn get kind => text()(); // amend|reschedule|cancel|discount
  IntColumn get amountBefore => integer().nullable()();
  IntColumn get amountAfter => integer().nullable()();
  TextColumn get reason => text().withLength(min: 1)();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class PaymentReversals extends Table {
  TextColumn get id => text()();
  // UNIQUE: a payment can be reversed at most once.
  TextColumn get paymentId => text().unique().references(Payments, #id)();
  TextColumn get reason => text().withLength(min: 1)();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_followups_date', columns: {#followUpDate})
class FollowUps extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get contractId => text().nullable().references(Contracts, #id)();
  DateTimeColumn get followUpDate => dateTime()();
  TextColumn get customerResponse => text().nullable()();
  DateTimeColumn get expectedPaymentDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();
  @override
  Set<Column> get primaryKey => {settingKey};
}

@DataClassName('NotificationPref')
class NotificationSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get minutesAfterMidnight =>
      integer().withDefault(const Constant(540))(); // 09:00
  TextColumn get reminderDays => text().withDefault(const Constant('0,1'))();
  BoolColumn get dailySummary => boolean().withDefault(const Constant(true))();
  BoolColumn get backupReminder =>
      boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_audit_time', columns: {#createdAt})
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get details => text().nullable()(); // JSON
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BackupMeta')
class BackupMetadata extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get schemaVersion => integer()();
  IntColumn get customerCount => integer()();
  IntColumn get contractCount => integer()();
  IntColumn get paymentCount => integer()();
  TextColumn get kind => text()(); // export|pre-restore
  @override
  Set<Column> get primaryKey => {id};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerType => text()(); // customer|contract|payment
  TextColumn get ownerId => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  TextColumn get sha256 => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}
