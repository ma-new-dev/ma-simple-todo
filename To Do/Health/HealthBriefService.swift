import Foundation
import FoundationModels
import SwiftData

/// Writes the morning brief: a headline plus going well / watch / work on, the same three
/// columns as the Health Dashboard artifact. `HealthFacts` works out every comparison in
/// code; Apple's on-device model then rewrites them as short, readable bullets. Nothing
/// leaves the phone and nothing is paid for. If the model is unavailable, declines, or
/// writes a number that isn't in the facts, the facts are shown as they are.
@Observable
@MainActor
final class HealthBriefService {
    static let shared = HealthBriefService()

    var isGenerating = false
    var lastError: String?
    /// True when today's brief is the plain facts because the on-device model couldn't help.
    var usedFallback = false

    func todaysBrief(in context: ModelContext) -> HealthBrief? {
        let today = Calendar.current.startOfDay(for: .now)
        var descriptor = FetchDescriptor<HealthBrief>(
            predicate: #Predicate { $0.date == today },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func generate(in context: ModelContext) async {
        guard !isGenerating else { return }
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        let facts = Self.facts(in: context)
        let written = await rewriteOnDevice(facts)
        usedFallback = written == nil
        let result = written ?? facts

        let brief = HealthBrief(date: .now)
        brief.headline = result.headline
        brief.goingWell = result.goingWell
        brief.watch = result.watch
        brief.today = result.workOn
        context.insert(brief)
        do {
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    static func facts(in context: ModelContext, now: Date = .now) -> HealthFacts {
        let cutoff = Calendar.current.date(byAdding: .day, value: -62, to: Calendar.current.startOfDay(for: now)) ?? now
        let metrics = (try? context.fetch(FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.date >= cutoff }))) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.date >= cutoff }))) ?? []
        return HealthFacts(metrics: metrics, workouts: workouts, now: now)
    }

    // MARK: - On-device rewrite

    private func rewriteOnDevice(_ facts: HealthFacts) async -> HealthFacts? {
        guard OnDeviceModel.isAvailable, !facts.goingWell.isEmpty || !facts.watch.isEmpty else { return nil }
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: """
                Rewrite these facts as this morning's brief. Keep every number exactly as \
                written and add none. Merge overlapping points; drop nothing important.

                \(facts.asPromptText)
                """,
                generating: WrittenBrief.self
            )
            return Self.accept(response.content, against: facts)
        } catch {
            return nil
        }
    }

    /// Keeps each part of the model's answer only if every number in it appears in the
    /// facts; otherwise that part falls back to the computed lines.
    static func accept(_ written: WrittenBrief, against facts: HealthFacts) -> HealthFacts {
        let allowed = HealthFacts.numbers(in: facts.asPromptText)
        func valid(_ lines: [String]) -> Bool {
            !lines.isEmpty && lines.allSatisfy { HealthFacts.numbers(in: $0).isSubset(of: allowed) }
        }
        let headline = written.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        return HealthFacts(
            headline: valid([headline]) ? headline : facts.headline,
            goingWell: facts.goingWell.isEmpty || !valid(written.goingWell) ? facts.goingWell : written.goingWell,
            watch: facts.watch.isEmpty || !valid(written.watch) ? facts.watch : written.watch,
            workOn: valid(written.workOn) ? written.workOn : facts.workOn
        )
    }

    /// The boundary is carried over from Baseline's coach; the rest is kept short because
    /// the on-device model has a small context window.
    static let instructions = """
    You write a morning health brief for Mukul, 42, coached by Qualia Health and Dr. Molly. \
    You only reword facts you are given. Never diagnose, never suggest medication, \
    supplements or dose changes; if something looks medical, say to raise it with Qualia or \
    Dr. Molly. Be specific and plain: short sentences, every claim tied to a number, no \
    praise, no exclamation marks. Work-on items are direct instructions for today.
    """
}

@Generable
struct WrittenBrief {
    @Guide(description: "One sentence: the single thing that matters most this morning, with its numbers")
    var headline: String
    @Guide(description: "What is going well, one short sentence each", .count(1...3))
    var goingWell: [String]
    @Guide(description: "What to watch, one short sentence each", .count(1...3))
    var watch: [String]
    @Guide(description: "What to do today and tonight, one short instruction each", .count(1...3))
    var workOn: [String]
}
