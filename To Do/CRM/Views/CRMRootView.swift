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
        // The single navigation stack for this tab. DashboardView and ContactListView used
        // to open their own as well, which produced two stacked navigation bars, a
        // duplicated title, and a search field rendered under the outer large title.
        // They now set their own title and toolbar items on this stack.
        NavigationStack {
            VStack(spacing: 0) {
                Picker("CRM Section", selection: $selectedTab) {
                    Text("Dashboard").tag(0)
                    Text("Contacts").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityIdentifier("crmSectionPicker")

                Divider()

                if selectedTab == 0 {
                    DashboardView()
                } else {
                    ContactListView()
                }
            }
        }
    }
}

#Preview {
    CRMRootView()
        .modelContainer(for: Contact.self, inMemory: true)
}
