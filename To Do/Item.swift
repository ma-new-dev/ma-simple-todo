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

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.list)
    var tasks: [TaskItem]?

    init(name: String, createdAt: Date = .now, sortOrder: Int = 0) {
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

@Model
final class TaskItem {
    var title: String = ""
    var createdAt: Date = Foundation.Date()
    var completedAt: Date?
    var sortOrder: Int = 0

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
        self.completedAt = completedAt
        self.sortOrder = sortOrder
    }

    var isCompleted: Bool {
        completedAt != nil
    }
}
