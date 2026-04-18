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
    var updatedAt: Date = Foundation.Date()
    var sortOrder: Int = 0
    var supabaseId: UUID = UUID()   // stable ID for Supabase sync

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
    var updatedAt: Date = Foundation.Date()
    var completedAt: Date?
    var sortOrder: Int = 0
    var supabaseId: UUID = UUID()   // stable ID for Supabase sync

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
