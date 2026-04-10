import SwiftUI

struct ContactRowView: View {
    let contact: Contact
    var showCity: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(contact: contact, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(contact.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    PriorityBadge(priority: contact.priority, compact: true)
                }

                if !contact.jobTitle.isEmpty || !contact.company.isEmpty {
                    Text([contact.jobTitle, contact.company].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if showCity && !contact.city.isEmpty {
                        Label(contact.city, systemImage: "mappin")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if !contact.tags.isEmpty {
                        TagChip(tag: contact.tags[0])
                            .scaleEffect(0.85, anchor: .leading)
                        if contact.tags.count > 1 {
                            Text("+\(contact.tags.count - 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if contact.isReconnectOverdue {
                        Label("Overdue", systemImage: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if let next = contact.nextReconnect {
                        Text(next.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
