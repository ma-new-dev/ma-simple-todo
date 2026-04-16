import Foundation
import SwiftData

/// Injects realistic sample data for App Store screenshots.
/// Triggered by the SCREENSHOT_MODE launch argument.
enum SampleData {

    static func inject(into context: ModelContext) {
        // MARK: - Todo Lists

        let work = TodoList(name: "Work", sortOrder: 0)
        let personal = TodoList(name: "Personal", sortOrder: 1)
        let travel = TodoList(name: "Travel Planning", sortOrder: 2)

        context.insert(work)
        context.insert(personal)
        context.insert(travel)

        // Work tasks
        let workTasks: [(String, Bool, Int)] = [
            ("Review Q2 investment memo", false, 0),
            ("Prep for portfolio board meeting", false, 1),
            ("Send term sheet to Aakash", false, 2),
            ("Follow up with Priya re: Series A", false, 3),
            ("Read YC batch applications", false, 4),
            ("LP update call — prep deck", true, 5),
            ("Due diligence on FinStack", true, 6),
        ]
        for (title, completed, order) in workTasks {
            let task = TaskItem(
                title: title,
                list: work,
                completedAt: completed ? Date().addingTimeInterval(-86400) : nil,
                sortOrder: order
            )
            context.insert(task)
        }

        // Personal tasks
        let personalTasks: [(String, Bool, Int)] = [
            ("Book flights for Goa trip", false, 0),
            ("Renew car insurance", false, 1),
            ("Gift for Rohan's birthday", false, 2),
            ("Call dad this weekend", false, 3),
            ("Schedule annual health check", false, 4),
            ("Order new running shoes", true, 5),
        ]
        for (title, completed, order) in personalTasks {
            let task = TaskItem(
                title: title,
                list: personal,
                completedAt: completed ? Date().addingTimeInterval(-172800) : nil,
                sortOrder: order
            )
            context.insert(task)
        }

        // Travel tasks
        let travelTasks: [(String, Bool, Int)] = [
            ("Research hotels in Lisbon", false, 0),
            ("Apply for Portugal visa", false, 1),
            ("Book airport transfer", false, 2),
            ("Get travel insurance", false, 3),
        ]
        for (title, completed, order) in travelTasks {
            let task = TaskItem(
                title: title,
                list: travel,
                completedAt: completed ? Date().addingTimeInterval(-43200) : nil,
                sortOrder: order
            )
            context.insert(task)
        }

        // MARK: - Contacts

        let now = Date()
        let day: TimeInterval = 86_400

        let contacts: [(String, String, String, String, Priority, Date?, Date?, Date?)] = [
            // name, company, title, city, priority, lastContacted, nextReconnect, birthday
            ("Aakash Mehta",    "FinStack",           "CEO",              "Bengaluru", .high,   now - 2*day,  now + 3*day,  nil),
            ("Priya Sharma",    "Sequoia India",      "VP Investments",   "Mumbai",    .high,   now - 15*day, now - 5*day,  nil),
            ("Rohan Kapoor",    "Elevation Capital",  "Principal",        "Delhi",     .medium, now - 1*day,  now + 10*day, now + 5*day),
            ("Sara Chen",       "OpenAI",             "Product Lead",     "San Francisco", .high, now - 30*day, now - 8*day, nil),
            ("Vikram Nair",     "Swiggy",             "CTO",              "Bengaluru", .medium, now - 8*day,  now + 14*day, nil),
            ("Ananya Iyer",     "Razorpay",           "CFO",              "Bengaluru", .medium, now - 45*day, nil,          nil),
            ("James Park",      "a16z",               "General Partner",  "Menlo Park", .high,  now - 60*day, nil,          nil),
            ("Neha Gupta",      "Meesho",             "Head of Growth",   "Bengaluru", .low,    now - 3*day,  now + 20*day, nil),
        ]

        for (name, company, title, city, priority, lastContacted, nextReconnect, birthday) in contacts {
            let c = Contact(
                name: name,
                city: city,
                company: company,
                jobTitle: title,
                tags: priority == .high ? ["investor", "key"] : ["portfolio"],
                priority: priority,
                lastContacted: lastContacted,
                nextReconnect: nextReconnect,
                birthday: birthday
            )
            context.insert(c)

            // Add a recent interaction for some contacts
            if let lc = lastContacted {
                let i = Interaction(
                    date: lc,
                    type: [InteractionType.call, .meeting, .email, .message].randomElement()!,
                    notes: "Caught up on latest developments"
                )
                i.contact = c
                context.insert(i)
            }
        }

        try? context.save()
    }
}
