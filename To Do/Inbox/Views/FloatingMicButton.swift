import SwiftUI

struct FloatingMicButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel("New brain dump")
    }
}

#Preview {
    FloatingMicButton(action: {})
}
