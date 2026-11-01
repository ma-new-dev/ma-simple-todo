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

        // MARK: - Health (screenshot mode only)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Six months of believable days: slow monthly drift plus a weekly rhythm.
        for back in (0..<182).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let t = Double(back)
            let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
            let m = DailyMetric(date: date)
            m.recovery = min(96, max(22, 64 + 12 * sin(t / 4.3) - (back < 60 && back > 30 ? 7 : 0) + (back < 30 ? 4 : 0)))
            m.hrv = 49 + 4 * sin(t / 5.1) + (back < 30 ? 2.2 : 0) - (back > 120 ? 1.5 : 0)
            m.restingHR = 54 - 1.2 * sin(t / 6.0) - (back < 30 ? 1 : 0)
            m.sleepHours = 7.2 + 0.6 * sin(t / 3.1)
            m.sleepNeedHours = 8.2 + 0.3 * sin(t / 2.7)
            m.sleepDebtHours = max(0, 1.1 + 0.6 * sin(t / 4.0))
            m.sleepPerformance = 84 + 6 * sin(t / 3.1)
            m.sleepConsistency = 72 + 8 * sin(t / 7.0)
            m.deepPct = 22 + 2 * sin(t / 2.0)
            m.remPct = 30 + 3 * sin(t / 2.5)
            m.dayStrain = back == 0 ? 6.4 : ([1, 7].contains(weekday) ? 13.5 : (weekday == 4 ? 6 : 10.5)) + 1.5 * sin(t / 1.7)
            m.steps = 11_000 + 3_000 * sin(t / 2.2)
            m.exerciseMinutes = 45 + 15 * sin(t / 2.9)
            m.recoverySource = "whoop"
            if back % 6 == 2 { m.vo2Max = 44.2 + Double(182 - back) / 182 * 1.8 + 0.3 * sin(t) }
            if back % 3 == 0 { m.cardioRecoveryBpm = 24 + 3 * sin(t / 5) + (back < 30 ? 1.5 : 0) }
            m.daylightMinutes = 22 + 14 * sin(t / 3.3)
            if back % 7 == 0 { m.weightKg = 66.1 + 0.3 * sin(t / 9) }
            m.wristTempDeltaC = back == 0 ? 0.2 : 0.1 * sin(t)
            m.breathingDisturbances = 4 + sin(t / 2)
            context.insert(m)

            let sport: String? = switch weekday {
            case 2, 6: "weightlifting"
            case 4: "functional fitness"
            case 5: "running"
            case 7: "padel"
            case 1: "cricket"
            default: nil
            }
            if let sport, back < 70 {
                let workout = Workout(date: date.addingTimeInterval(8 * 3600), externalID: "sample-\(back)", type: sport,
                                      durationMin: sport == "cricket" ? 150 : 55, source: "whoop")
                workout.strain = sport == "padel" || sport == "cricket" ? 12.4 : (sport == "running" ? 13.1 : 11.2)
                workout.avgHR = sport == "running" ? 141 : 112
                workout.zoneMinutes = [10, 15, 12, 14, sport == "padel" ? 3 : 0.4, 0]
                if sport == "running" {
                    let km = 6 + Double(back % 3)
                    workout.distanceKm = km
                    workout.durationMin = km * 6.1
                    workout.elevationGainM = 38
                    workout.avgPowerW = 236
                    workout.avgCadenceSpm = 166
                    workout.effortScore = 6
                    workout.splitsSecPerKm = (0..<Int(km)).map { 372 - Double($0) * 3 + (Double($0 % 2) * 6) }
                    workout.healthKitID = "sample-hk-\(back)"
                }
                context.insert(workout)
            }
        }
        let brief = HealthBrief(date: Date())
        brief.headline = "Recovery 71 (from 58), HRV 53.4 ms, resting HR 53, 7.6 h sleep."
        brief.goingWell = ["Recovery is in the green after a 13-point jump.", "30-day average HRV 51.4 ms, up from 48.9 the 30 days before."]
        brief.watch = ["Slept 7.6 h against an 8.4 h need; sleep debt is 72 min.", "Only 6 min at zone 4 or above in 30 days."]
        brief.today = ["Green light for padel as planned; add 5 to 10 min at zone 4.", "Dinner by 19:30 and lights out by 22:15."]
        context.insert(brief)

        // MARK: - Food (screenshot mode only)

        for slot in MealSlot.allCases {
            let picker = FoodPicker(dishes: FoodCatalog.dishes, date: today, slot: slot, history: [], week: WeekBalance(), shownToday: [])
            for (index, pick) in picker.pick(FoodPlanService.optionsPerSlot).enumerated() {
                let option = MealOption(date: today, slot: slot, sortOrder: index, name: pick.dish.name, detail: pick.dish.detail)
                option.proteinGrams = pick.dish.protein
                option.vegetables = pick.dish.vegetables
                option.proteinSources = pick.dish.proteins
                option.grains = pick.dish.grains
                option.isGlutenMeal = pick.dish.gluten
                option.reason = pick.reason
                if slot == .breakfast, index == 1 { option.decision = .chosen }
                if slot == .lunch, index == 2 { option.decision = .liked }
                context.insert(option)
            }
        }

        // MARK: - Net worth (screenshot mode only; made-up numbers)

        NetWorthStore.shared.summary = NetWorthSummary(
            asOf: "2026-09-30",
            refreshedAt: "2026-11-01",
            totals: .init(netInvestedCr: 100, fmvCr: 120, gainCr: 20, lifetimeGainPct: 20, blendedIrrPct: 11, blendedIrrInclCashPct: 9, vsNifty500Cr: 2.5),
            allocation: [.init(name: "Equity / AIF", pct: 50), .init(name: "Parked cash", pct: 35), .init(name: "Debt", pct: 10), .init(name: "Multi-asset", pct: 5)],
            segments: [
                .init(name: "Equity", netInvestedCr: 50, fmvCr: 60, irrPct: 10.5, note: "6 PMS/AIF + 2 MF"),
                .init(name: "Debt", netInvestedCr: 12, fmvCr: 13, irrPct: 8.8, note: nil),
                .init(name: "Parked cash", netInvestedCr: 40, fmvCr: 42, irrPct: 5.6, note: "Liquid + Arbitrage"),
            ],
            managers: [
                .init(name: "Manager A", type: "PMS", fmvCr: 15, gainCr: 4, irrPct: 16, vsNifty500Cr: 1.2, monthPct: -3.1, oneYearPct: 14.2, verdict: "strong", why: "1Y +14.2% vs −2.3% for the market; ₹1.2 cr ahead of the index fund.", action: "Add", decisionRef: "#5"),
                .init(name: "Manager B", type: "PMS", fmvCr: 9, gainCr: 2.1, irrPct: 12.4, vsNifty500Cr: 0.6, monthPct: -4.2, oneYearPct: 5.1, verdict: "strong", why: "Steady compounding; beat the market in 9 of the last 12 months.", action: "Hold"),
                .init(name: "Manager C", type: "PMS", fmvCr: 7, gainCr: 1.4, irrPct: 9.8, vsNifty500Cr: -0.2, monthPct: -2.6, oneYearPct: -7.9, verdict: "watch", why: "Held up this month, but 1Y −7.9% vs −2.3% at a full fee.", action: "Reduce", decisionRef: "#1"),
                .init(name: "Manager D", type: "Cat-III AIF", fmvCr: 3, gainCr: -0.2, irrPct: -2.1, vsNifty500Cr: -0.4, monthPct: -6.1, verdict: "lagging", why: "Negative since inception and behind the index fund.", action: "Exit", decisionRef: "#2"),
                .init(name: "Manager E", type: "Equity MF", fmvCr: 20, gainCr: 1.8, irrPct: 4.2, vsNifty500Cr: 0.3, monthPct: -5.5, verdict: "steady", why: "Moves with the market.", action: "Hold"),
                .init(name: "Liquid", type: "Liquid MF", fmvCr: 42, gainCr: 2, irrPct: 5.6, verdict: "cash", why: "Parked corpus awaiting deployment.", action: "Hold"),
            ],
            decisions: [
                .init(title: "#5 ₹20 cr deployment", status: "13 of 20 cr deployed", nextDate: "15-Nov-2026", kind: "add", needsDecision: false),
                .init(title: "#1 Manager C: reduce unless fees cut", status: "1Y alpha −5.6pp; no fee offer", nextDate: "13-Nov-2026", kind: "exit", needsDecision: false),
                .init(title: "#2 Manager D: exit at the window", status: "Notice by May 2027", nextDate: "21-May-2027", kind: "exit", needsDecision: false),
                .init(title: "#10 Manager fee change", status: "Billed at the old rate", nextDate: "10-Jan-2027", kind: "fees", needsDecision: false),
            ],
            history: [.init(date: "2026-09-18", fmvCr: 116, netInvestedCr: 98), .init(date: "2026-10-05", fmvCr: 118, netInvestedCr: 99), .init(date: "2026-10-18", fmvCr: 120.5, netInvestedCr: 100), .init(date: "2026-11-01", fmvCr: 120, netInvestedCr: 100)],
            period: "September 2026",
            monthSummary: "The market fell 5.6% in September. Four of five equity managers lost less; Manager D lost more. Value is down ₹0.5 cr since the last refresh. Nothing needs a decision this cycle.",
            benchmark: .init(name: "BSE 500 TRI", monthPct: -5.57, oneYearPct: -2.33),
            deployment: .init(title: "₹20 cr PMS deployment", targetCr: 20, items: [.init(name: "Manager A", plannedCr: 7, doneCr: 5), .init(name: "Manager B", plannedCr: 5.5, doneCr: 4), .init(name: "Manager C", plannedCr: 4.5, doneCr: 0), .init(name: "Manager E", plannedCr: 3, doneCr: 4)])
        )

        try? context.save()
    }
}
