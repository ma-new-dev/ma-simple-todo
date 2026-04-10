import SwiftUI
import SwiftData

/// Root view for the CRM tab — wraps Dashboard + Contacts in their own TabView
struct CRMRootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house.fill") }

            ContactListView()
                .tabItem { Label("Contacts", systemImage: "person.2.fill") }
        }
    }
}

#Preview {
    CRMRootView()
        .modelContainer(for: Contact.self, inMemory: true)
}
