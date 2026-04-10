import SwiftUI

struct PriorityBadge: View {
    let priority: Priority
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: priority.systemImage)
                .font(compact ? .caption2 : .caption)
            if !compact {
                Text(priority.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(backgroundColor.opacity(0.15))
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .secondary
        }
    }

    private var backgroundColor: Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return Color(.systemGray4)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        PriorityBadge(priority: .high)
        PriorityBadge(priority: .medium)
        PriorityBadge(priority: .low)
    }
    .padding()
}
