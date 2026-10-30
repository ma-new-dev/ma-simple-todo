import Foundation
import SwiftData

/// Writes the morning brief: one headline plus going well / watch / today, grounded in the
/// last two weeks of WHOOP and Apple Health data. Generated on open when today's brief is
/// missing; pull-to-refresh forces a new one.
@Observable
@MainActor
final class HealthBriefService {
    static let shared = HealthBriefService()

    var isGenerating = false
    var lastError: String?

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

        do {
            let result = try await ClaudeClient.structured(
                BriefResult.self,
                system: Self.systemPrompt,
                user: Self.digest(in: context) + """


                Write this morning's brief as JSON. headline: the one thing that matters \
                today, one sentence, tied to a number. going_well, watch, today: 1-3 bullets \
                each, one sentence each. going_well and watch are verdicts grounded in a \
                number from the data. today is what to do today and tonight.
                """,
                schema: BriefResult.schema
            )

            let brief = HealthBrief(date: .now)
            brief.headline = result.headline
            brief.goingWell = result.goingWell
            brief.watch = result.watch
            brief.today = result.today
            context.insert(brief)
            try context.save()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Digest

    /// The data the model sees. Everything in the brief must come from here.
    static func digest(in context: ModelContext, now: Date = .now) -> String {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now)) ?? now
        let dayFormat = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)

        var lines = ["TODAY: \(now.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))"]

        let metrics = (try? context.fetch(FetchDescriptor<DailyMetric>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        lines.append("\nDAILY, last 14 days (recovery % / HRV ms / RHR / sleep h / sleep perf % / strain / steps / exercise min):")
        if metrics.isEmpty { lines.append("no data synced") }
        for m in metrics {
            let fields = [
                fmt(m.recovery), fmt(m.hrv), fmt(m.restingHR), fmt(m.sleepHours, 1),
                fmt(m.sleepPerformance), fmt(m.dayStrain, 1), fmt(m.steps), fmt(m.exerciseMinutes),
            ]
            lines.append("\(m.date.formatted(dayFormat)): " + fields.joined(separator: " / "))
        }

        let workouts = (try? context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        lines.append("\nWORKOUTS, last 14 days (WHOOP):")
        if workouts.isEmpty { lines.append("none recorded") }
        for w in workouts {
            var parts = ["\(w.date.formatted(dayFormat)): \(w.type.lowercased())", "\(Int(w.durationMin)) min"]
            if let strain = w.strain { parts.append(String(format: "strain %.1f", strain)) }
            if let hr = w.avgHR { parts.append("avg HR \(Int(hr))") }
            lines.append(parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private static func fmt(_ value: Double?, _ decimals: Int = 0) -> String {
        guard let value else { return "–" }
        return String(format: "%.\(decimals)f", value)
    }

    // MARK: - Prompt

    /// The boundary paragraph is carried over verbatim from Baseline's coach. Targets and
    /// rhythm reflect the 12 Oct 2026 Qualia session.
    static let systemPrompt = """
    You write the morning health brief in Compass, a personal app used by exactly one \
    person: Mukul, 42, male, ~66.5 kg (happy anywhere in 65-66.5 kg, not chasing loss), \
    vegetarian plus eggs, Delhi/Gurgaon (IST). Venture capital partner with high \
    cognitive load. He is coached by Qualia Health (nutrition, exercise, resilience) and \
    Dr. Molly (medical). You are instrumentation that helps him execute their protocol — \
    you are not a clinician.

    THE BOUNDARY, non-negotiable:
    You describe his own data against targets set by his clinical team. You do not \
    diagnose, do not prescribe, and do not recommend changes to any medication, \
    supplement dose, or clinical protocol. When a marker is out of range or a trend is \
    concerning, name it precisely, state what it is measured against, and say to raise \
    it with Qualia or Dr. Molly. Never propose the adjustment yourself.
    Within his existing protocol, day-to-day execution IS yours to direct: which session \
    to do today and how hard, dinner timing, bedtime, swapping a hard session for an easy \
    one, a recovery action. Training, food timing, and sleep scheduling: yes. Doses, \
    supplements, diagnoses: name and escalate only.

    HIS WEEK (Oct 2026): three gym (strength) days, one zone-2 run, padel on Saturday, \
    cricket on Sunday. He trains fasted, so a carb-based recovery food after a big \
    session matters more than extra protein. His goals, in order: no bloating, \
    heaviness or energy drops; then recovery for gym and sport.

    TARGETS: sleep 7.5 h+ with lights out by 22:30; dinner by 19:00-19:30 (late or \
    heavy dinners measurably hurt his deep sleep); HRV toward 55 ms; resting HR toward \
    52. Recovery zones: green 67+, yellow 34-66, red 33 or below.

    HIS FAILURE MODE: stacked high-strain days on low recovery have twice led to an HRV \
    crash and illness. Flag a third load day in a row on yellow or red recovery before \
    it happens. A rest day is a legitimate instruction.

    STYLE: specific and quantitative; every claim tied to a number in the data you are \
    given. Never invent data; if something is missing, say so. No praise, no \
    cheerleading, no exclamation marks. Prescriptive ("Easy 30 min walk, no padel \
    intensity, lights out 22:15"), not optional ("consider resting").
    """

    // MARK: - Wire

    private struct BriefResult: Decodable {
        let headline: String
        let goingWell: [String]
        let watch: [String]
        let today: [String]

        enum CodingKeys: String, CodingKey {
            case headline, watch, today
            case goingWell = "going_well"
        }

        static var schema: [String: Any] {
            let bullets: [String: Any] = ["type": "array", "items": ["type": "string"]]
            return [
                "type": "object",
                "properties": [
                    "headline": ["type": "string"],
                    "going_well": bullets,
                    "watch": bullets,
                    "today": bullets,
                ],
                "required": ["headline", "going_well", "watch", "today"],
                "additionalProperties": false,
            ]
        }
    }
}
