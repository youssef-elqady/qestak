# Database schema (v1)
Source of truth: `lib/core/database/tables.dart`.

- All ids are UUID text. All money columns are INTEGER piastres.
- `PRAGMA foreign_keys = ON` is set in `beforeOpen`. No FK uses CASCADE, so a customer/contract with children cannot be deleted. Archive via `status`.
- Paid amount, remaining amount and installment status are NOT stored; they are derived from `PaymentAllocations` whose payment has no row in `PaymentReversals` (see `Ledger`).
- `Payments.idempotencyKey` UNIQUE prevents duplicate submissions; `PaymentReversals.paymentId` UNIQUE allows one reversal per payment.
- Down payment: stored on `Contracts`; `financedAmount = finalPrice - downPayment` is what the installments sum to.
- Customer credit = SUM(`CustomerCredits.delta`) per customer.

Enum text values: customer.status = active|archived; contract.status = draft|active|completed|cancelled; markupType = percentage|fixed|manualFinalPrice; payment.method = cash|bankTransfer|wallet|other.
