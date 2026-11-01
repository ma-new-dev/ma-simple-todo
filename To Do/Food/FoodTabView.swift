import SwiftUI
import SwiftData
import Charts

/// The whole day's food on one screen: every option for breakfast, lunch and dinner side
/// by side, tap one to have it, plus Prachi's 3:45 snack, a recovery snack on training
/// days, and where the day and week stand on protein and balance. Every pick, like and
/// "not today" feeds tomorrow's options.
struct FoodTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var allOptions: [MealOption]
    @Query private var images: [DishImage]
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]

    @State private var planner = FoodPlanService.shared
    @State private var imageService = DishImageService.shared
    @State private var day = Calendar.current.startOfDay(for: .now)
    /// Meals whose options are showing even though one is already picked.
    @State private var expanded: Set<MealSlot> = []
    @State private var detail: MealOption?

    private var calendar: Calendar { .current }
    private var todayStart: Date { calendar.startOfDay(for: .now) }
    private var tomorrowStart: Date { calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart }

    private var dayOptions: [MealOption] {
        allOptions.filter { $0.date == day }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private func visible(_ slot: MealSlot) -> [MealOption] {
        dayOptions.filter { $0.slot == slot && $0.decision != .skipped }
    }
    private func chosen(_ slot: MealSlot) -> MealOption? {
        dayOptions.first { $0.slot == slot && $0.decision == .chosen }
    }

    private var balance: WeekBalance {
        let week = WeekBalance.weekInterval(containing: day)
        return WeekBalance(chosen: allOptions.filter { week.contains($0.date) && $0.decision == .chosen })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Day", selection: $day) {
                        Text("Today").tag(todayStart)
                        Text("Tomorrow").tag(tomorrowStart)
                    }
                    .pickerStyle(.segmented)

                    plateCard
                    recoveryCard

                    if dayOptions.isEmpty {
                        emptyOrLoading
                    } else {
                        mealSection(.breakfast)
                        mealSection(.lunch)
                        snackCard
                        mealSection(.dinner)
                    }

                    WeekBalanceCard(balance: balance, week: WeekBalance.weekInterval(containing: day))
                }
                .padding()
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Food")
            .task(id: day) { await loadDay() }
            .sheet(item: $detail) { option in
                DishDetail(option: option, imageData: imageData(for: option)) { decide(option, $0) }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Loading

    private func loadDay() async {
        expanded = []
        guard !ProcessInfo.processInfo.arguments.contains("SCREENSHOT_MODE") else { return }
        await planner.ensurePlan(for: day, in: modelContext)
    }

    @ViewBuilder
    private var emptyOrLoading: some View {
        if planner.isGenerating {
            VStack(spacing: 12) {
                ProgressView()
                Text("Choosing \(day == todayStart ? "today's" : "tomorrow's") options from Prachi's plan…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            ContentUnavailableView {
                Label("No options yet", systemImage: "fork.knife")
            } description: {
                Text(planner.lastError ?? "Plan the day to see options.")
            } actions: {
                Button("Plan the day") {
                    Task { await planner.generate(for: day, slots: MealSlot.allCases, in: modelContext) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - The day's plate

    private var plateCard: some View {
        let picked = MealSlot.allCases.compactMap { chosen($0) }
        let protein = picked.reduce(0) { $0 + $1.proteinGrams } + (picked.isEmpty ? 0 : WeekBalance.assumedSnackProtein)
        let target = WeekBalance.dailyProteinTarget
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color(.tertiarySystemFill), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, protein / target))
                    .stroke(protein >= target ? Color.green : .blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(protein))").font(.title3.weight(.bold).monospacedDigit())
                    Text("of \(Int(target)) g").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 4) {
                Text(day == todayStart ? "Today's plate" : "Tomorrow's plate").font(.headline)
                Text("\(picked.count) of 3 meals picked" + (picked.isEmpty ? "" : " · includes the ~15 g snack"))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let nudge = balance.nudges.first {
                    Label(nudge, systemImage: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .card()
    }

    // MARK: - Training-day recovery snack

    @ViewBuilder
    private var recoveryCard: some View {
        let session = workouts.first { calendar.isDate($0.date, inSameDayAs: day) && ($0.strain ?? 0) >= 8 }
        if day == todayStart, let session, let advice = PlanText.afterExercise(in: FoodPlanService.foodPlan) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.heart.fill").font(.title2).foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("After today's \(session.type.lowercased()) (\(Int(session.durationMin)) min, strain \(String(format: "%.1f", session.strain ?? 0)))")
                        .font(.subheadline.weight(.semibold))
                    Text(Self.recoveryAdvice(advice)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pink.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Prachi's after-exercise line without its preamble: "Within an hour: recovery drink…".
    static func recoveryAdvice(_ text: String) -> String {
        guard let range = text.range(of: "within an hour: ") else { return text }
        return "Within an hour: " + text[range.upperBound...]
    }

    // MARK: - Snack

    @ViewBuilder
    private var snackCard: some View {
        let week = FoodPicker.planWeek(for: day)
        if let snack = PlanText.snack(in: FoodPlanService.foodPlan, week: week, weekday: FoodPicker.weekday(for: day)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cup.and.saucer.fill").font(.title3).foregroundStyle(.brown)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("3:45 snack").font(.subheadline.weight(.semibold))
                    Text(snack).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("From Prachi's Week \(week) plan · fruit before 4 PM").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .card()
        }
    }

    // MARK: - A meal

    private static let times: [MealSlot: String] = [.breakfast: "9:30", .lunch: "1:00", .dinner: "7:00"]

    @ViewBuilder
    private func mealSection(_ slot: MealSlot) -> some View {
        let options = visible(slot)
        let pick = chosen(slot)
        let showOptions = pick == nil || expanded.contains(slot)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(slot.title, systemImage: slot.icon).font(.title3.weight(.bold))
                Text(Self.times[slot] ?? "").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if pick != nil {
                    Button(expanded.contains(slot) ? "Done" : "Change") {
                        withAnimation(.snappy) {
                            if expanded.contains(slot) { expanded.remove(slot) } else { expanded.insert(slot) }
                        }
                    }
                    .font(.subheadline)
                } else {
                    Text("Tap to pick").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let pick, !showOptions {
                ChosenDish(option: pick, imageData: imageData(for: pick)) { detail = pick }
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(options) { option in
                        OptionCard(
                            option: option,
                            imageData: imageData(for: option),
                            onPick: { pickOrUnpick(option) },
                            onLike: { decide(option, option.decision == .liked ? .pending : .liked) },
                            onSkip: { decide(option, .skipped) },
                            onDetails: { detail = option }
                        )
                        .onAppear { imageService.request(for: option, in: modelContext) }
                    }
                }
                Button {
                    Task { await planner.generate(for: day, slots: [slot], in: modelContext) }
                } label: {
                    Label(options.count < 3 ? "Show more options" : "Different options", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(planner.isGenerating)
            }
        }
        .padding()
        .card()
    }

    private var columns: [GridItem] {
        sizeClass == .regular
            ? [GridItem(.adaptive(minimum: 200), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    // MARK: - Decisions

    private func pickOrUnpick(_ option: MealOption) {
        withAnimation(.snappy) {
            if option.decision == .chosen {
                planner.decide(option, .liked, in: modelContext)
            } else {
                planner.decide(option, .chosen, in: modelContext)
                expanded.remove(option.slot)
            }
        }
    }

    private func decide(_ option: MealOption, _ decision: MealDecision) {
        withAnimation(.snappy) {
            planner.decide(option, decision, in: modelContext)
            if decision == .chosen { expanded.remove(option.slot) }
        }
    }

    private func imageData(for option: MealOption) -> Data? {
        let key = option.dishKey
        return images.first { $0.dishKey == key }?.imageData
    }
}

// MARK: - Cards

private struct OptionCard: View {
    let option: MealOption
    let imageData: Data?
    let onPick: () -> Void
    let onLike: () -> Void
    let onSkip: () -> Void
    let onDetails: () -> Void

    private var isChosen: Bool { option.decision == .chosen }

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 0) {
                DishImageView(option: option, imageData: imageData)
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    if !option.reason.isEmpty {
                        Text(option.reason).font(.caption2).foregroundStyle(.tint).lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Chip(text: "\(Int(option.proteinGrams)) g", color: .blue)
                        if option.isGlutenMeal { Chip(text: "gluten", color: .orange) }
                        if let veg = option.vegetables.first { Chip(text: veg, color: .green) }
                    }
                }
                .padding(10)
            }
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isChosen ? Color.accentColor : .clear, lineWidth: 3))
            .overlay(alignment: .topLeading) {
                if isChosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onLike) {
                Image(systemName: option.decision == .liked ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(option.decision == .liked ? .pink : .white)
                    .padding(7)
                    .background(.black.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel(option.decision == .liked ? "Unlike" : "Like")
        }
        .contextMenu {
            Button(isChosen ? "Not having this" : "Having this", systemImage: "checkmark.circle", action: onPick)
            Button(option.decision == .liked ? "Unlike" : "Like", systemImage: "heart", action: onLike)
            Button("Not today", systemImage: "xmark.circle", role: .destructive, action: onSkip)
            Button("Details", systemImage: "info.circle", action: onDetails)
        }
        .accessibilityHint("Picks this for the meal")
    }
}

private struct ChosenDish: View {
    let option: MealOption
    let imageData: Data?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                DishImageView(option: option, imageData: imageData)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Label("Having this", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.green)
                    Text(option.name).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text(option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                    Text("\(Int(option.proteinGrams)) g protein").font(.caption.weight(.medium)).foregroundStyle(.blue)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DishDetail: View {
    let option: MealOption
    let imageData: Data?
    let onDecide: (MealDecision) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DishImageView(option: option, imageData: imageData)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text(option.name).font(.title2.weight(.bold))
                    if !option.reason.isEmpty {
                        Label(option.reason, systemImage: "sparkles").font(.subheadline).foregroundStyle(.tint)
                    }
                    Text(option.detail).font(.body)
                    FlowChips(items: [("\(Int(option.proteinGrams)) g protein", Color.blue)]
                              + option.proteinSources.map { ($0, Color.purple) }
                              + option.vegetables.map { ($0, Color.green) }
                              + option.grains.map { ($0, Color.brown) }
                              + (option.isGlutenMeal ? [("gluten meal", Color.orange)] : []))
                    HStack {
                        Button {
                            onDecide(.chosen); dismiss()
                        } label: { Label("Having this", systemImage: "checkmark").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        Button {
                            onDecide(.liked); dismiss()
                        } label: { Image(systemName: "heart") }
                        .buttonStyle(.bordered)
                        Button(role: .destructive) {
                            onDecide(.skipped); dismiss()
                        } label: { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

private struct FlowChips: View {
    let items: [(String, Color)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Chip(text: item.0, color: item.1)
            }
        }
    }
}

// MARK: - Images

/// The dish picture, or an illustrated stand-in while it's being drawn (or without
/// Apple Intelligence).
struct DishImageView: View {
    let option: MealOption
    let imageData: Data?

    var body: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var symbol: String {
        let sources = Set(option.proteinSources)
        if sources.contains("egg") { return "frying.pan.fill" }
        if option.name.lowercased().contains("soup") { return "cup.and.saucer.fill" }
        if option.grains.contains(where: { $0.contains("rice") }) { return "takeoutbag.and.cup.and.straw.fill" }
        return option.slot == .breakfast ? "sunrise.fill" : "fork.knife"
    }

    private var palette: [Color] {
        let all: [[Color]] = [[.orange, .pink], [.green, .teal], [.indigo, .purple], [.yellow, .orange], [.teal, .blue]]
        let seed = option.dishKey.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % all.count }
        return all[seed]
    }
}

private struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.13))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Week balance

private struct WeekBalanceCard: View {
    let balance: WeekBalance
    let week: DateInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("This week", systemImage: "calendar").font(.headline)
                Spacer()
                Text("\(balance.mealsChosen) meals picked").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(days, id: \.self) { day in
                    let protein = (balance.proteinByDay[day] ?? 0)
                    BarMark(x: .value("Day", day, unit: .day),
                            y: .value("Protein", protein > 0 ? protein + WeekBalance.assumedSnackProtein : 0))
                        .foregroundStyle(protein + WeekBalance.assumedSnackProtein >= WeekBalance.dailyProteinTarget ? Color.green : .blue)
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Target", WeekBalance.dailyProteinTarget))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(Int(WeekBalance.dailyProteinTarget)) g protein").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
            }
            .frame(height: 100)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                stat("Vegetables", "\(balance.vegetables.count)", "aim \(WeekBalance.vegetableFloor)+", balance.vegetables.count >= WeekBalance.vegetableFloor ? .green : .secondary)
                stat("Paneer days", "\(balance.paneerDays)", "max \(WeekBalance.paneerDayCap)", balance.paneerDays >= WeekBalance.paneerDayCap ? .orange : .secondary)
                stat("Tofu meals", "\(balance.tofuMeals)", "aim 3–4", WeekBalance.tofuMealRange.contains(balance.tofuMeals) ? .green : .secondary)
                stat("Gluten meals", "\(balance.glutenMeals)", "max 3", balance.glutenMeals >= WeekBalance.glutenMealRange.upperBound ? .orange : .secondary)
                stat("Egg days", "\(balance.eggDays)", "not every day", .secondary)
                stat("Rajma", "\(balance.rajmaMeals)", "twice in 4 weeks", balance.rajmaMeals > 0 ? .orange : .secondary)
            }
            if !balance.vegetables.isEmpty {
                Text("Vegetables so far: " + balance.vegetables.sorted().joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .card()
    }

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: week.start) }
    }

    private func stat(_ title: String, _ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color == .secondary ? .primary : color)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
