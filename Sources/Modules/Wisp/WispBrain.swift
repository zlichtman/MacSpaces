#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Apple's on-device model (macOS 26 with Apple Intelligence), with tools that go through
/// the same actions as Wisp's plain requests. Nothing is sent off the Mac.
@available(macOS 26, *)
@MainActor
final class WispBrain {
    private let box: WispActionsBox
    private var session: LanguageModelSession?
    private var started = Date.distantPast

    init(actions: WispModel) {
        box = WispActionsBox(actions)
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to chat in plain language. Requests like “remind me to call Sam tomorrow” work now."
        case .unavailable(.deviceNotEligible):
            return "This Mac can't run Apple's on-device model. Requests like “remind me to call Sam tomorrow” still work."
        case .unavailable(.modelNotReady):
            return "Apple's on-device model is still getting ready. Plain requests work meanwhile."
        case .unavailable:
            return "Apple's on-device model isn't available right now. Plain requests still work."
        }
    }

    func respond(to prompt: String) async throws -> String {
        do {
            return try await current().respond(to: prompt).content
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error else { throw error }
            session = nil
            return try await current().respond(to: prompt).content
        }
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal: return "I can't help with that one."
            case .unsupportedLanguageOrLocale: return "I can't work in this language yet."
            case .rateLimited, .concurrentRequests: return "One thing at a time. Try again in a moment."
            default: break
            }
        }
        return "Something went wrong with the on-device model."
    }

    /// A session lasts half an hour, so the time in its instructions stays true.
    private func current() -> LanguageModelSession {
        if let session, Date().timeIntervalSince(started) < 30 * 60 { return session }
        let tools: [any Tool] = [ReminderTool(box: box), CompleteTool(box: box), NoteTool(box: box),
                                 FocusTool(box: box), TimerTool(box: box), DayTool(box: box)]
        let now = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
        let session = LanguageModelSession(tools: tools, instructions: """
            You are Wisp, a small, cheerful assistant living in the notch of the user's Mac, inside MacSpaces.
            Reply in one or two short sentences of plain text, no lists or markdown.
            Use your tools to add or check off reminders, save notes, start or stop focus, set timers \
            and read the user's day. Only say something is done when a tool confirms it.
            If a request is unclear, ask one short question. It is now \(now).
            """)
        self.session = session
        started = Date()
        return session
    }
}

/// Lets sendable tools reach Wisp on the main actor.
final class WispActionsBox: @unchecked Sendable {
    @MainActor private weak var model: WispModel?
    @MainActor init(_ model: WispModel) { self.model = model }

    func run(_ body: @escaping @MainActor (WispModel) async -> String) async -> String {
        guard let model = await current() else { return "Wisp isn't ready." }
        return await body(model)
    }

    @MainActor private func current() -> WispModel? { model }
}

@available(macOS 26, *)
private struct ReminderTool: Tool {
    let name = "addReminder"
    let description = "Add a reminder to the user's Apple Reminders, optionally due at a time."
    let box: WispActionsBox

    @Generable struct Arguments {
        @Guide(description: "What to be reminded of, short, without the time")
        var title: String
        @Guide(description: "When, in plain words like 'tomorrow', 'in 20 minutes' or 'friday 3pm', if the user said")
        var when: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let due = arguments.when.flatMap { WispWhen.parse($0) }
        return await box.run { await $0.addReminder(title: arguments.title, due: due) }
    }
}

@available(macOS 26, *)
private struct CompleteTool: Tool {
    let name = "completeReminder"
    let description = "Check off one of the user's open reminders."
    let box: WispActionsBox

    @Generable struct Arguments {
        @Guide(description: "Words from the reminder's title")
        var title: String
    }

    func call(arguments: Arguments) async throws -> String {
        await box.run { await $0.completeReminder(matching: arguments.title) }
    }
}

@available(macOS 26, *)
private struct NoteTool: Tool {
    let name = "saveNote"
    let description = "Save a note to the user's MacSpaces Notes."
    let box: WispActionsBox

    @Generable struct Arguments {
        @Guide(description: "The note's text, in the user's words")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        await box.run { $0.addNote(arguments.text) }
    }
}

@available(macOS 26, *)
private struct FocusTool: Tool {
    let name = "focus"
    let description = "Start or stop the user's focus session."
    let box: WispActionsBox

    @Generable struct Arguments {
        @Guide(description: "True to start focusing, false to stop")
        var start: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await box.run { arguments.start ? $0.startFocus() : $0.stopFocus() }
    }
}

@available(macOS 26, *)
private struct TimerTool: Tool {
    let name = "startTimer"
    let description = "Start a countdown timer."
    let box: WispActionsBox

    @Generable struct Arguments {
        @Guide(description: "Length in minutes", .range(1...600))
        var minutes: Int
        @Guide(description: "A short name like 'Tea', if the user gave one")
        var name: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await box.run { $0.startTimer(seconds: TimeInterval(arguments.minutes * 60), name: arguments.name) }
    }
}

@available(macOS 26, *)
private struct DayTool: Tool {
    let name = "readDay"
    let description = "Read today's calendar events, reminders due and focus sessions."
    let box: WispActionsBox

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await box.run { await $0.describeDay() }
    }
}
#endif
