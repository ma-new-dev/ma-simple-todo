import SwiftUI

struct NetWorthTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Net Worth", systemImage: "indianrupeesign.circle", description: Text("Coming in 3.0."))
                .navigationTitle("Net Worth")
        }
    }
}
