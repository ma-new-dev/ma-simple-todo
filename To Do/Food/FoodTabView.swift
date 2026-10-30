import SwiftUI

struct FoodTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Food", systemImage: "fork.knife", description: Text("Coming in 3.0."))
                .navigationTitle("Food")
        }
    }
}
