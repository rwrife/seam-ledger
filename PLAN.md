# Seam Ledger — delivery plan

## Scope and architecture

Standard native Swift iPhone app for an offline home-sewing cut/seam workspace. `SeamLedgerKit` holds pure-Swift units (integer micrometres or rational conversion, with overflow checks), cut-count constraints, immutable per-piece cutting events, explicit edge/allowance pairing and unknown-safe summaries. `SeamLedgerStore` persists projects/events in local GRDB SQLite with migrations and attachment manifests; `SeamLedgerApp` is a SwiftUI shell. `SewingWorkspaceLayout` is a single folded/one-screen versus future dual-screen migration seam, not an unavailable fold SDK dependency. App and domain are network-free.

## Technology choices

Swift 6, SwiftUI/UIKit, Foundation, PDFKit for viewing user-imported pattern PDFs, PhotosPicker for user-selected photos, GRDB for local SQLite, Swift Package Manager, Xcode 26.0.1 (17A400) with iOS 26.0+ SDK. Use fixed-unit conversion and dimensional validation rather than floating-point equality for seam allowance warnings. Exact bundle ID `com.infinityball.seamledger` in `PRODUCT_BUNDLE_IDENTIFIER`, Info.plist and signing configuration. `TARGETED_DEVICE_FAMILY = 1` in every app-target build configuration and generator; Apple CI verifies built `UIDeviceFamily == [1]`. Native iPad support is disabled; compatibility mode is not native support.

No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity or other cross-platform/hybrid frameworks. No Android or iPad without explicit user opt-in. Dual-screen is future iPhone Duo design target only: PDF/reference on one screen; persistent cut/seam controls on the other through `SewingWorkspaceLayout`.

## Milestones and dependencies

1. **Skeleton/CI (#1):** Xcode iPhone-only app, pure Swift package and store package, Linux unit-test lane, pinned macos-26 build/test lane, zero-network and bundle/device-family checks.
2. **Domain/store (#2):** project, piece, edge, seam, cutting events, fixed-unit conversions, GRDB migrations, fixture tests, reversible transitions. Depends on #1.
3. **Cut table (#3):** editable project and PDF import, distinct outer/lining pieces, mirrored-pair accounting and reversible cuts; explicit reconcile if definitions change. Depends on #2.
4. **Sewing record (#4):** edge pairing, mismatch display, sewn/pressed events, alteration measurements and optional photos. Depends on #3.
5. **Accessibility/workspace (#5):** single-screen reference/control flow with `SewingWorkspaceLayout`, VoiceOver and Dynamic Type; document future Duo split. Depends on #4.
6. **Ownership (#6):** versioned JSON backup + attachment manifest, preview/rollback restore, CSV/PDF exports, file permission minimization and zero-network regression checks. Depends on #5.
7. **Distribution (#7):** review AppStore/description.txt against actual app, generate and inspect real `AppStore/icon.png` with requested `hermes-image-gen`, wire Xcode catalog, port cook-console release Action. Depends on #1–6 and actual image-generation availability.

## Testing and acceptance evidence

- Unit tests: 10 mm vs 1 cm equal, 5/8 inch vs 10 mm mismatch, unknown allowance remains unknown, mirrored pair requires two physical pieces, duplicate/undo/definition-change events never silently count twice, corrupted backup rejects without overwriting live project.
- Store tests: migration fixtures, atomic event transactions, attachment removal and restore rollback; CSV/JSON round trips.
- XCUITest: import owned PDF, add mirrored pair, cut/undo, pair edges, record seam, export report; VoiceOver/Dynamic Type. CI must measure Xcode/SDK and built UIDeviceFamily from an Apple runner; Linux parse/contract probes are not native builds.
- Privacy gate rejects unexpected network dependencies/entitlements. No permissions except user-driven file/photo selection.

## Packaging and distribution

App Store Connect bundle `com.infinityball.seamledger` registered. ASC secret names ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID present. `.github/workflows/release.yml` is required in #7: port proven rwrife/cook-console template (green also in rise-log, split-slip, catch-tally). `v*` tag/manual dispatch → macos-26 → exact Xcode 26.0.1/17A400 and iOS 26+ SDK enforcement → mode-600 ASC API key → signed IPA archive/export → App Store Connect API TestFlight upload using all four secret names → wait for processing → GitHub release. Require workflow URL and processed ASC build ID before claiming release. Verify `TARGETED_DEVICE_FAMILY = 1`, built UIDeviceFamily [1], and exact bundle ID in signed outputs. Do not claim source-only Linux checks prove signing.

Scaffold `AppStore/description.txt` is planning copy, not a live listing; `AppStore/icon.png` and Xcode asset wiring do not exist yet. The icon must use the specified `hermes-image-gen` model and exact creative brief; no generated-art claim if blocked.

## Risks and non-goals

- Imported copyrighted patterns remain private; never ship sample commercial patterns.
- Mixed units and mirrored/fold pieces are easy to miscount; explicit physical-piece counting and user-controlled definitions are required. No fabric yield optimizer or certification of fit.
- Photo/PDF attachments may enlarge backups; preview export size and allow optional photo exclusion in report, never silently omit attachments in full backup.
- No pattern marketplace, accounts, cloud, camera measurement, OCR, automatic grading, hardware integration, AI suggestions, Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, Android or native iPad support. No fabricated testing or garment safety advice.
