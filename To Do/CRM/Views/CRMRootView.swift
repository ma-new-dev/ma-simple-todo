import SwiftUI
import SwiftData

struct CRMRootView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("CRM Section", selection: $selectedTab) {
                    Text("Dashboard").tag(0)
                    Text("Contacts").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if selectedTab == 0 {
                    DashboardView()
                } else {
                    ContactListView()
                }
            }
            .navigationTitle(selectedTab == 0 ? "Dashboard" : "Contacts")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    CRMRootView()
        .modelContainer(for: Contact.self, inMemory: true)
}
