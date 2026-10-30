import SwiftUI

struct HealthTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Health", systemImage: "heart.text.square", description: Text("Coming in 3.0."))
                .navigationTitle("Health")
        }
    }
}
