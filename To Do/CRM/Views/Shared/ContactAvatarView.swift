import SwiftUI

struct ContactAvatarView: View {
    let contact: Contact
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let data = contact.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(avatarColor(for: contact.name))
                    Text(contact.initials)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(contact.name.isEmpty ? "Contact" : contact.name)
    }

    /// Picks a stable colour for a name.
    ///
    /// `String.hashValue` is seeded per process, so using it would re-colour every avatar
    /// on each launch. Summing the UTF-8 bytes keeps the colour fixed for a given name, and
    /// avoids `abs(Int.min)` trapping.
    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .cyan, .mint]
        let seed = name.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % colors.count }
        return colors[seed]
    }
}
