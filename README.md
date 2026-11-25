# Qestak (قسطك)

Offline installment manager for one owner. Flutter + Drift (SQLite) + Riverpod. Arabic RTL.

## Status: v0.2.0 - complete source, NOT yet compiled or run
It was written without a Flutter SDK, so expect a few compile errors on first build. Send them back and they get fixed.

## Get the apps (GitHub Actions, no installs needed)
1. Create a free GitHub account and a new PUBLIC repository (public so the download link works without login).
2. Upload ALL files of this folder (keep `.github/workflows/build-apk.yml`; if the hidden `.github` folder does not upload, use "Add file > Create new file", type `.github/workflows/build-apk.yml` and paste the content).
3. Actions tab > **Build Android + iOS** > **Run workflow**. Wait ~10-15 minutes.
4. Open the repository's **Releases** page (right side of the repo home). Download `qestak.apk` directly from the phone and install it (allow "install unknown apps").
5. iPhone: the release also holds `qestak-unsigned.ipa`. It is NOT signed, so it cannot be opened by tapping. Install it from a Windows/Mac PC with Sideloadly or AltStore using a free Apple ID (must be re-signed every 7 days), or use a paid Apple Developer account ($99/yr) for TestFlight. If the iOS job fails, the Android APK is still published.
If a run fails, open the failed step and send me its log text.

## Local build
```
flutter create --org com.qestak --project-name qestak --platforms=android,ios .
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build apk --release
```
iOS needs a Mac with Xcode and an Apple developer account; not covered here.

## Implemented
Customers (CRUD, archive, duplicate-phone warning, Arabic-normalized search + filters, profile, call/WhatsApp/copy, follow-ups) - Contracts (3 pricing methods, live calculation, editable schedule, monthly/weekly/custom, grace days, month-end rule) - Installments (list/calendar, filters, grouping, computed statuses) - Payments (partial, multiple, oldest-first / specific / manual allocation, credit, idempotent save, reversal with reason, PDF receipt) - Collections screen - Dashboard (all figures from one `Snapshot`) - Reports (PDF + Excel) - Encrypted portable backup/restore - PIN lock with auto-lock - light/dark theme.

## NOT implemented yet
Local notifications, biometric unlock, customer photos/attachments, applying existing customer credit to installments, contract cancellation, amending amounts (only due-date moves are supported and logged), tests for UI/notifications, iOS build config.

## Unverified areas (highest risk)
- Arabic shaping and column order in generated PDFs.
- PBKDF2 (100k iterations, pure Dart) may take a few seconds on older phones; the UI shows a progress dialog.
- Cross-platform (Android <-> iPhone) restore: format is platform-independent by design but has never been tested.

## Design rules
- Money = integer piastres; percent = basis points; half-up rounding; leftover piastres go to the first installments.
- Paid/remaining/status are derived from allocations (never cached); reversed payments are excluded.
- Down payment is counted as collected on the contract but is not a Payment row, so it is absent from the cash-collections report.
- Realized profit = contractual markup x (collected / final price) (proportional method).
See docs/SCHEMA.md and docs/BACKUP_FORMAT.md.
