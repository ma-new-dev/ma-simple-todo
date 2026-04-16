import SwiftUI
import SwiftData

struct CRMRootView: View {
    var initialCRMTab: Int = 0
    @State private var selectedTab = 0

    init(initialCRMTab: Int = 0) {
        self.initialCRMTab = initialCRMTab
        self._selectedTab = State(initialValue: initialCRMTab)
    }

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
