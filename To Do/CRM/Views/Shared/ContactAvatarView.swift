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
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .cyan, .mint]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }
}
