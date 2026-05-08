//
//  Item.swift
//  To Do
//
//  Created by Mukul Arora on 28/02/26.
//

import Foundation
import SwiftData

@Model
final class TodoList {
    var name: String = ""
    var createdAt: Date = Foundation.Date()
    var sortOrder: Int = 0

    // Transient: not persisted, not synced to CloudKit. Kept as in-memory
    // properties so existing code that reads/writes them still compiles.
    // CloudKit Production schema does not contain these fields, and shipping
    // them caused records to be silently rejected by CloudKit.
    @Transient var updatedAt: Date = Foundation.Date()
    @Transient var supabaseId: UUID = UUID()

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.list)
    var tasks: [TaskItem]?

    init(name: String, createdAt: Date = .now, sortOrder: Int = 0) {
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.sortOrder = sortOrder
        self.supabaseId = UUID()
    }
}

@Model
final class TaskItem {
    var title: String = ""
    var createdAt: Date = Foundation.Date()
    var completedAt: Date?
    var sortOrder: Int = 0

    @Transient var updatedAt: Date = Foundation.Date()
    @Transient var supabaseId: UUID = UUID()

    var list: TodoList?

    init(
        title: String,
        list: TodoList?,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.title = title
        self.list = list
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.supabaseId = UUID()
    }

    var isCompleted: Bool {
        completedAt != nil
    }
}
