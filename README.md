# Seam Ledger

**Pitch:** Offline iPhone sewing workspace for home sewists: turn a pattern's cut list into counted fabric pieces, pair seam allowances before stitching, and keep a portable alteration record without accounts or cloud.

## Motivation and target users

Paper cutting lists lose track of mirrored pairs and lining pieces. Notes rarely preserve which allowance was used on each edge or what changed after fitting. Seam Ledger serves home garment sewists and small repair projects: a cutting table companion, not pattern-design software or machine control.

## Use cases and intended workflow

1. Create a project (shirt, cushion, repair), import a PDF you own or enter instructions yourself, and select its measurement unit.
2. Enter pieces by name, fabric role, required count, mirrored-pair flag, and optional edge allowances. Counts are physical pieces: a mirrored pair requires two pieces. Fold-cut is a separate instruction, never an implicit count multiplier.
3. Check off individual cuts; undo mistakes. Missing required quantities remain unknown, not complete. Pieces changed after cutting need explicit reconciliation rather than silently reassigning prior cuts.
4. Link two edges into a seam. See both declared allowances and a mismatch warning; mark sewn and pressed independently. A missing allowance remains unspecified. Warnings compare user entries, not certify fit or construction safety.
5. Log fitting/alteration notes with optional picked photos and before/after dimensions. Export a project report or full backup when finished.

Concrete examples: distinguish outer and lining sleeve pairs; catch 10 mm versus 5/8 inch allowances before joining; preserve a trouser-hem change for the next alteration.

## Planned MVP

- Local projects with user-authored cut lists and optional owned PDF references.
- Per-piece required/cut counts, mirrored-pair validation, reversible cutting events.
- Explicit seam edge pairing and exact allowance comparison, with sewn/pressed state.
- Fitting notes, optional photos, and manually entered before/after measurements.
- Versioned JSON backup including references and photos; previewed replace restore; CSV cut/seam exports and a shareable PDF project report.
- VoiceOver, Dynamic Type, high contrast and large controls; no color-only warnings.

## Platform contract and dual-screen target

Native Swift (SwiftUI/UIKit), iPhone-only, iOS 26 SDK or newer. `toolchain.json` declares Xcode 26.0.1 (17A400), iOS SDK 26.0 and Swift 6. `TARGETED_DEVICE_FAMILY = 1` in every future app-target configuration and generator; Apple CI must verify built `UIDeviceFamily == [1]`. Native iPad support is disabled; iPhone compatibility mode on iPad is not native support.

The iPhone Duo design target keeps the pattern page/edge diagram visible on one display while cut counts and sewing/pressing controls remain on the other. Today's implementation must be a standard single-screen iPhone app. `SewingWorkspaceLayout` is the one future dual-screen migration seam; no unavailable fold APIs and no inferred iPad permission.

## Privacy, permissions and storage

SQLite and imported PDF/photo copies live in the app sandbox. Files import uses the system document picker; PhotosPicker imports selected images without broad library permission. No camera, microphone, location, contacts or notifications required in MVP. No network, accounts, analytics, ads, subscriptions, cloud sync or AI. User-initiated Files/share exports can expose measurements and photos: warn clearly and allow a report without photos. Delete-all removes the database and owned attachment files; files already exported remain outside app control.

## Non-goals and limits

No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity or other cross-platform/hybrid frameworks. No Android or native iPad implementation without explicit opt-in. No pattern marketplace, copyrighted pattern distribution, OCR, automatic grading, fabric nesting optimizer, camera measurement, sizing recommendations, machine connection, structural/safety advice or fit guarantees. The app compares recorded quantities and measurements only; never infer body measurements or treat missing allowances as zero.

## Bundle identifier and distribution

Bundle identifier `com.infinityball.seamledger` must match `PRODUCT_BUNDLE_IDENTIFIER`, Info.plist and signing/provisioning settings in every target. App Store Connect result on 2026-10-07: `CREATED com.infinityball.seamledger`.

GitHub Actions secret names configured: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID. No signing result exists yet. Release issue #7 must port `.github/workflows/release.yml` from rwrife/cook-console: `v*` tag or manual dispatch, macos-26, exact Xcode/iOS 26+ SDK verification, mode-600 API key, signed IPA archive/export, TestFlight upload via App Store Connect API, processing wait, GitHub release. Never invent a signing flow.

`AppStore/description.txt` is honest planning copy, not a published listing. Issue #7 requires real `AppStore/icon.png`, generated with the specifically requested `hermes-image-gen` model after analyzing repo and description, wired into the Xcode asset catalog. No substitute or placeholder may be called generated artwork; unavailable model means a blocked icon requirement.

## Status and milestones

Native iPhone skeleton (`SeamLedger.xcodeproj`), pure Swift foundation packages and pinned CI are implemented. See [bootstrap evidence](docs/bootstrap-evidence.md) for verified checks versus pending Apple evidence. No cutting/sewing workflow, database, icon, release Action, signed archive or TestFlight build is delivered by this foundation.

1. #1 Native skeleton and CI (Apple evidence required before completion).
2. #2 Measurement/count domain and persistence.
3. #3 Project/cutting workflow.
4. #4 Seam pairing, sewing/pressing and alteration record.
5. #5 Accessible reference-plus-control workspace and `SewingWorkspaceLayout`.
6. #6 Backup, reports, restore and privacy verification.
7. #7 Generated icon, listing review and ASC publish Action.

## Development quickstart

Run `swift test --package-path Packages/SeamLedgerKit` and `swift test --package-path Packages/SeamLedgerStore` with Swift 6.2. Run `bash scripts/check_zero_network.sh` and `bash scripts/check_native_only.sh`. On macOS with the exact pinned toolchain, open `SeamLedger.xcodeproj`, build the `SeamLedger` iPhone scheme and run its launch test. Linux package checks cannot validate a native app, simulator, archive or signing. See PLAN for evidence gates.

## License

MIT; see LICENSE. Imported patterns remain the user's property and are not redistributed with the app.
