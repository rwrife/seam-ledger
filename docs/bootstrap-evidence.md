# Milestone 1: Bootstrap & Evidence Record

## Overview
- Issue: #1 (M1: Native iPhone skeleton and measured CI contract)
- Branch: `feat/issue-1-native-skeleton`
- Target Bundle ID: `com.infinityball.seamledger`
- Targeted Device Family: `1` (iPhone only)
- Toolchain: Xcode 26.0.1 (17A400), iOS SDK 26.0, Swift 6

## Verification Matrix

### Host / Container (Linux Swift 6.2-noble & Python 3)
- `python3 -m unittest discover -s Scripts/tests -v`: PASS (host helper, contract-gate and already-booted retry regression tests)
- `bash scripts/check_zero_network.sh`: PASS (empty allowlist, no networking symbols)
- `bash scripts/check_native_only.sh`: PASS (no cross-platform or hybrid frameworks)
- `bash -n Scripts/ci.sh`: PASS (syntax clean)
- `actionlint .github/workflows/ci.yml`: PASS
- `swift test --package-path Packages/SeamLedgerKit`: PASS (3/3 swift-testing tests passed in container)
- `swift test --package-path Packages/SeamLedgerStore`: PASS (2/2 swift-testing tests passed in container)
- PBXproj pre-check: `TARGETED_DEVICE_FAMILY = 1;` declared in all 4 configurations; no `1,2` or non-iPhone values.

### Apple CI Lane (macos-26): acceptance still pending

First run: https://github.com/rwrife/seam-ledger/actions/runs/37654875788
measured Xcode 26.0.1 / 17A400 / iPhoneOS SDK 26.0 and installed the matching
simulator runtime. Simulator boot exited 149 before app build or UI tests.
Linux CI passed. This is not native app-build or simulator-test success.
A fresh exact-head Apple run is required after the contract-gate repairs.

The following are configured gates, not claimed execution results:
- Exact toolchain selection: Xcode 26.0.1 (17A400)
- iOS 26 SDK assertion
- Required simulator platform runtime check/install
- Zero-network gate & Native-only gate
- App build (`SeamLedger.xcodeproj` -> `SeamLedger.app`)
- Post-build assertions:
  - `UIDeviceFamily == [1]`
  - `CFBundleIdentifier == com.infinityball.seamledger`
  - `PrivacyInfo.xcprivacy` embedded in bundle
- UI Launch test: `SeamLedgerUITests` on booted iPhone simulator
