# TestFlight release workflow

The release workflow accepts a `v*` tag or a manual version input. Both must match `VERSION`; the run number is used as the monotonically increasing App Store Connect build number. The workflow requires the pinned Xcode 26.0.1 build 17A400 and iOS 26 or newer SDK, archives the `SeamLedger` iPhone target, verifies the archived bundle ID and `UIDeviceFamily == [1]`, uploads through Xcode's App Store Connect API-key support, waits for processing, adds the build to the Internal tester group, and creates a GitHub release.

Configure these repository secret names: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, and `ASC_TEAM_ID`. Values are passed only as environment variables; the private key is written with mode 600 to the runner temp directory and removed by an `always()` cleanup step. The workflow never prints secret values.

No release is complete until a successful native workflow run, processed App Store Connect build ID, and GitHub release URL are recorded. The automated workflow does not claim that a build has been signed or processed before those results exist. App Store listing text and the generated app icon require their separate review and evidence.
