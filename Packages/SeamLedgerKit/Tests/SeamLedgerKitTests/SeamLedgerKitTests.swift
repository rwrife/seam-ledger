import Testing
@testable import SeamLedgerKit

@Suite("Skeleton placeholder")
struct SeamLedgerKitTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(SeamLedgerKit.domain == "SeamLedgerKit")
    }

    @Test("milestone marker is set for M1")
    func milestoneMarker() {
        #expect(SeamLedgerKit.milestone == "M1-skeleton")
    }

    @Test("skeleton exposes no stored state beyond constants")
    func constantsAreStable() {
        // Guards the contract later issues depend on: these markers exist
        // and are pure constants (no clock, no I/O) in the M1 skeleton.
        let first = (SeamLedgerKit.domain, SeamLedgerKit.milestone)
        let second = (SeamLedgerKit.domain, SeamLedgerKit.milestone)
        #expect(first == second)
    }
}
