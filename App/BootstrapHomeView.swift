import SeamLedgerKit
import SeamLedgerStore
import SwiftUI

struct BootstrapHomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "scissors")
                        .font(.system(size: 54))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Seam Ledger")
                        .font(.largeTitle.bold())
                    Text("An offline cutting-table workspace for home sewists.")
                        .multilineTextAlignment(.center)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Native app foundation is ready")
                            Text("Pieces, cut counts, seam allowances and fitting notes are planned, not available yet.")
                                .foregroundStyle(.secondary)
                            Text("Foundation: \(SeamLedgerKit.milestone) / \(SeamLedgerStore.milestone)")
                                .font(.footnote)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("bootstrap.foundation")
                }
                .padding(24)
            }
            .navigationTitle("Home")
        }
    }
}
