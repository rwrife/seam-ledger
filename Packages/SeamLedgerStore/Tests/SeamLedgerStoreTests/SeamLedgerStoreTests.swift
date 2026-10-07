import Testing
@testable import SeamLedgerStore

@Suite("SeamLedgerStore skeleton tests")
struct SeamLedgerStoreTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(SeamLedgerStore.domain == "SeamLedgerStore")
    }

    @Test("milestone marker is M1-skeleton")
    func milestoneMarker() {
        #expect(SeamLedgerStore.milestone == "M1-skeleton")
    }
}
