import SwiftUI
import SwiftData

/// Today's meals as a deck per slot: swipe right to like, left to skip, "Having this" to
/// pick. Liked dishes collect in a shortlist; the week's balance sits underneath so the
/// next pick can fill a gap. Every decision feeds tomorrow's plan.
struct FoodTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allOptions: [MealOption]
    @Query private var images: [DishImage]

    @State private var planner = FoodPlanService.shared
    @State private var imageService = DishImageService.shared
    @State private var slot: MealSlot = .current()
    @State private var day = Calendar.current.startOfDay(for: .now)

    private var todays: [MealOption] {
        allOptions.filter { $0.date == day }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private func options(_ slot: MealSlot) -> [MealOption] { todays.filter { $0.slot == slot } }
    private var deck: [MealOption] { options(slot).filter { $0.decision == .pending } }
    private var shortlist: [MealOption] { options(slot).filter { $0.decision == .liked } }
    private var chosen: MealOption? { options(slot).first { $0.decision == .chosen } }

    private var balance: WeekBalance {
        let week = WeekBalance.weekInterval(containing: day)
        return WeekBalance(chosen: allOptions.filter { week.contains($0.date) && $0.decision == .chosen })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Meal", selection: $slot) {
                        ForEach(MealSlot.allCases) { s in
                            Label(s.title, systemImage: s.icon).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let chosen {
                        chosenBanner(chosen)
                    }

                    if todays.isEmpty {
                        emptyOrLoading
                    } else if !deck.isEmpty {
                        deckView
                    } else {
                        deckDone
                    }

                    if !shortlist.isEmpty {
                        shortlistView
                    }

                    WeekBalanceCard(balance: balance, today: day)
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .toolbar { toolbar }
            .task(id: day) { await loadDay() }
        }
    }

    private var navigationTitle: String {
        Calendar.current.isDateInToday(day) ? "Food" : day.formatted(.dateTime.weekday(.wide))
    }

    // MARK: - Loading

    private func loadDay() async {
        guard !ProcessInfo.processInfo.arguments.contains("SCREENSHOT_MODE") else { return }
        await planner.ensurePlan(for: day, in: modelContext)
    }

    @ViewBuilder
    private var emptyOrLoading: some View {
        if planner.isGenerating {
            VStack(spacing: 12) {
                ProgressView()
                Text("Planning \(Calendar.current.isDateInToday(day) ? "today's" : "tomorrow's") meals from Prachi's plan…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
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

    // MARK: - Deck

    private var deckView: some View {
        VStack(spacing: 14) {
            ZStack {
                // Draw the next two behind the top card for depth.
                ForEach(Array(deck.prefix(3).enumerated().reversed()), id: \.element.persistentModelID) { index, option in
                    SwipeCard(
                        option: option,
                        imageData: imageData(for: option),
                        isTop: index == 0,
                        onDecide: { decide(option, $0) }
                    )
                    .scaleEffect(1 - CGFloat(index) * 0.04)
                    .offset(y: CGFloat(index) * 10)
                    .allowsHitTesting(index == 0)
                    .onAppear { imageService.request(for: option, in: modelContext) }
                }
            }
            .frame(height: 440)

            if let top = deck.first {
                HStack(spacing: 18) {
                    roundButton("xmark", color: .red, label: "Skip") { decide(top, .skipped) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button {
                        decide(top, .chosen)
                    } label: {
                        Label("Having this", systemImage: "checkmark")
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    roundButton("heart.fill", color: .pink, label: "Like") { decide(top, .liked) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
                Text("\(deck.count) of \(options(slot).count) left · swipe right to like, left to skip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func roundButton(_ icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var deckDone: some View {
        VStack(spacing: 10) {
            Text(shortlist.isEmpty && chosen == nil ? "Nothing caught your eye?" : "That's all the \(slot.title.lowercased()) options.")
                .font(.headline)
            Button {
                Task { await planner.generate(for: day, slots: [slot], in: modelContext) }
            } label: {
                if planner.isGenerating {
                    ProgressView()
                } else {
                    Label("Show \(FoodPlanService.optionsPerSlot) more", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.bordered)
            .disabled(planner.isGenerating)
            if let error = planner.lastError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Chosen + shortlist

    private func chosenBanner(_ option: MealOption) -> some View {
        HStack(spacing: 12) {
            DishThumbnail(option: option, imageData: imageData(for: option), size: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("Having for \(slot.title.lowercased())").font(.caption).foregroundStyle(.secondary)
                Text(option.name).font(.headline)
            }
            Spacer()
            Button("Change") { decide(option, .liked) }
                .font(.subheadline)
        }
        .padding(12)
        .background(Color.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var shortlistView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Liked for \(slot.title.lowercased())").font(.subheadline.weight(.semibold))
            ForEach(shortlist) { option in
                HStack(spacing: 12) {
                    DishThumbnail(option: option, imageData: imageData(for: option), size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.name).font(.subheadline.weight(.medium))
                        Text("\(Int(option.proteinGrams)) g protein").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Having this") { decide(option, .chosen) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Day", selection: $day) {
                    Text("Today").tag(Calendar.current.startOfDay(for: .now))
                    if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) {
                        Text("Tomorrow").tag(tomorrow)
                    }
                }
                Divider()
                Button("New \(slot.title.lowercased()) options", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await planner.generate(for: day, slots: [slot], in: modelContext) }
                }
                .disabled(planner.isGenerating)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Helpers

    private func decide(_ option: MealOption, _ decision: MealDecision) {
        withAnimation(.snappy) {
            planner.decide(option, decision, in: modelContext)
        }
    }

    private func imageData(for option: MealOption) -> Data? {
        let key = option.dishKey
        return images.first { $0.dishKey == key }?.imageData
    }
}

// MARK: - Swipe card

private struct SwipeCard: View {
    let option: MealOption
    let imageData: Data?
    let isTop: Bool
    let onDecide: (MealDecision) -> Void

    @State private var drag: CGSize = .zero
    private let threshold: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DishImageView(option: option, imageData: imageData)
                .frame(height: 250)
                .clipped()
                .overlay(alignment: .topLeading) { stamp }

            VStack(alignment: .leading, spacing: 8) {
                Text(option.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                if !option.reason.isEmpty {
                    Label(option.reason, systemImage: "sparkles")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
                Text(option.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(option.reason.isEmpty ? 3 : 2)
                HStack(spacing: 6) {
                    Chip(text: "\(Int(option.proteinGrams)) g protein", color: .blue)
                    if option.isGlutenMeal { Chip(text: "gluten", color: .orange) }
                    ForEach(option.vegetables.prefix(2), id: \.self) { Chip(text: $0, color: .green) }
                }
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 430)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(isTop ? 0.12 : 0.05), radius: 12, y: 4)
        .offset(x: drag.width, y: drag.height * 0.2)
        .rotationEffect(.degrees(Double(drag.width / 22)))
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    if value.translation.width > threshold {
                        fly(to: 600, then: .liked)
                    } else if value.translation.width < -threshold {
                        fly(to: -600, then: .skipped)
                    } else {
                        withAnimation(.spring) { drag = .zero }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Like") { onDecide(.liked) }
        .accessibilityAction(named: "Skip") { onDecide(.skipped) }
        .accessibilityAction(named: "Having this") { onDecide(.chosen) }
    }

    private func fly(to x: CGFloat, then decision: MealDecision) {
        withAnimation(.easeOut(duration: 0.2)) { drag = CGSize(width: x, height: drag.height) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDecide(decision) }
    }

    @ViewBuilder
    private var stamp: some View {
        if drag.width > 30 {
            Text("LIKE").stampStyle(.green).opacity(min(1, drag.width / threshold))
        } else if drag.width < -30 {
            Text("SKIP").stampStyle(.red).opacity(min(1, -drag.width / threshold))
        }
    }
}

private extension Text {
    func stampStyle(_ color: Color) -> some View {
        self.font(.title.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(-12))
            .padding(20)
    }
}

// MARK: - Images

/// The dish photo, or an illustrated stand-in while it's being drawn (or with no key).
struct DishImageView: View {
    let option: MealOption
    let imageData: Data?

    var body: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 54, weight: .semibold))
                    Text(option.proteinSources.prefix(2).joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var symbol: String {
        let sources = Set(option.proteinSources)
        if sources.contains("egg") { return "frying.pan.fill" }
        if option.name.lowercased().contains("soup") { return "cup.and.saucer.fill" }
        if option.grains.contains(where: { $0.contains("rice") || $0.contains("khichdi") }) { return "takeoutbag.and.cup.and.straw.fill" }
        return option.slot == .breakfast ? "sunrise.fill" : "fork.knife"
    }

    private var palette: [Color] {
        let all: [[Color]] = [[.orange, .pink], [.green, .teal], [.indigo, .purple], [.yellow, .orange], [.teal, .blue]]
        let seed = option.dishKey.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % all.count }
        return all[seed]
    }
}

struct DishThumbnail: View {
    let option: MealOption
    let imageData: Data?
    let size: CGFloat

    var body: some View {
        DishImageView(option: option, imageData: imageData)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.13))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Week balance

private struct WeekBalanceCard: View {
    let balance: WeekBalance
    let today: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(balance.mealsChosen) meals picked").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                stat("Protein today", "\(Int(proteinToday))", "of \(Int(WeekBalance.dailyProteinTarget)) g", proteinToday >= WeekBalance.dailyProteinTarget ? .green : .orange)
                stat("Vegetables", "\(balance.vegetables.count)", "aim \(WeekBalance.vegetableFloor)+", balance.vegetables.count >= WeekBalance.vegetableFloor ? .green : .secondary)
                stat("Paneer days", "\(balance.paneerDays)", "max \(WeekBalance.paneerDayCap)", balance.paneerDays >= WeekBalance.paneerDayCap ? .orange : .secondary)
                stat("Tofu meals", "\(balance.tofuMeals)", "aim 3–4", WeekBalance.tofuMealRange.contains(balance.tofuMeals) ? .green : .secondary)
                stat("Gluten meals", "\(balance.glutenMeals)", "max 3", balance.glutenMeals >= WeekBalance.glutenMealRange.upperBound ? .orange : .secondary)
                stat("Egg days", "\(balance.eggDays)", "not every day", .secondary)
            }
            if let nudge = balance.nudges.first {
                Label(nudge, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Chosen meals plus the plan's ~15 g afternoon snack, once something is picked.
    private var proteinToday: Double {
        let meals = balance.proteinByDay[today] ?? 0
        return meals > 0 ? meals + WeekBalance.assumedSnackProtein : 0
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
