import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 52) }

            Group {
                if message.isLoading {
                    TypingDotsView()
                } else {
                    Text(message.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleColor)
            .foregroundStyle(isUser ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !isUser { Spacer(minLength: 52) }
        }
    }

    private var bubbleColor: Color {
        if message.isError  { return .red.opacity(0.15) }
        if isUser           { return .blue }
        return Color(.secondarySystemBackground)
    }
}

// MARK: - Animated typing dots

struct TypingDotsView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary.opacity(phase == i ? 1 : 0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .onAppear { animate() }
    }

    private func animate() {
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { t in
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = (phase + 1) % 3
            }
        }
    }
}
