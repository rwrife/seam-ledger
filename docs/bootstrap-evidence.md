# Milestone 1: Bootstrap & Evidence Record

## Overview
- Issue: #1 (M1: Native iPhone skeleton and measured CI contract)
- Branch: `feat/issue-1-native-skeleton`
- Target Bundle ID: `com.infinityball.seamledger`
- Targeted Device Family: `1` (iPhone only)
- Toolchain: Xcode 26.0.1 (17A400), iOS SDK 26.0, Swift 6

## Verification Matrix

### Host / Container (Linux Swift 6.2-noble & Python 3)
- `python3 -m unittest discover -s Scripts/tests -v`: PASS (21/21 tests passed)
- `bash scripts/check_zero_network.sh`: PASS (empty allowlist, no networking symbols)
- `bash scripts/check_native_only.sh`: PASS (no cross-platform or hybrid frameworks)
- `bash -n Scripts/ci.sh`: PASS (syntax clean)
- `actionlint .github/workflows/ci.yml`: PASS
- `swift test --package-path Packages/SeamLedgerKit`: PASS (3/3 swift-testing tests passed in container)
- `swift test --package-path Packages/SeamLedgerStore`: PASS (2/2 swift-testing tests passed in container)
- PBXproj pre-check: `TARGETED_DEVICE_FAMILY = 1;` declared in all 4 configurations; no `1,2` or non-iPhone values.

### Apple CI Lane (macos-26)
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
