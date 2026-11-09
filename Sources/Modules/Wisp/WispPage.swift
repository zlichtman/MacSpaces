import SwiftUI

/// Wisp's page (`NotchTab.wisp`), with no columns. Empty, the eyes are the hero in the middle
/// with "How can I help?" under them, the suggestions just above the ask field. Talking, the eyes
/// move up into a slim header band at the top centre, with the model tag at its left and Start
/// over at its right, and the conversation runs full width below, newest at the bottom, fading
/// under the header. The ask field always spans the page along the bottom. There's no status
/// line: the eyes show it (it's the face's accessibility value). The eyes watch the pointer,
/// react when poked, doze when left alone, and may grow past the header without moving anything.
struct WispPage: View {
    @AppStorage(WidgetOptions.Keys.wispCharacter) private var shownCharacter: WispCharacter = .wisp
    @ObservedObject var model: WispModel
    var onEditingChanged: (Bool) -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var faceCenter: CGPoint = .zero
    @State private var gaze: CGPoint?
    /// The last time anything happened on the page and the last gaze update, kept out of the
    /// view's state so pointer moves don't redraw the page.
    @State private var clock = PageClock()
    @State private var overFace = false
    /// The pointer is within reach of the eyes: they widen.
    @State private var pointerNear = false
    /// The Ask me before sharing card Return and Escape answer.
    @FocusState private var focusedCard: UUID?

    private final class PageClock {
        var activity = Date()
        var gazeChanged = Date.distantPast
    }

    /// What the empty page offers: a short label, and what it asks.
    private struct Suggestion: Identifiable {
        let label: String, symbol: String, ask: String
        var id: String { ask }
    }

    private static let suggestions = [
        Suggestion(label: "What's my day?", symbol: "calendar", ask: "What's my day?"),
        Suggestion(label: "Stretch in 30 minutes", symbol: "bell", ask: "Remind me to stretch in 30 minutes"),
        Suggestion(label: "Start a focus session", symbol: "moon", ask: "Start a focus session"),
    ]

    private var isEmpty: Bool { model.messages.isEmpty }

    private static let greetingTitle = "How can I help?"
    /// The header band's height while talking, and the eyes' scale there.
    private static let headerHeight: CGFloat = 58, headerScale: CGFloat = 0.68
    /// The face's footprint at full size (`WispFace` at 80 pt).
    private static let faceSize = CGSize(width: 116, height: 92)

    private static func greetingLine(_ engine: WispEngine) -> String {
        if let partner = engine.partner, engine.isModel {
            return "\(partner.title) answers; \(WispCharacter.current.title) keeps your data on this Mac."
        }
        return engine.isModel ? "Ask anything, or set a reminder, note, focus or timer." : "Reminders, notes, focus, timers and your day."
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = geometry.size.width, height = geometry.size.height
                // Empty: the eyes and the greeting (about 40 pt) centred together.
                let emptyY = max(Self.faceSize.height / 2, (height - Self.faceSize.height - 44) / 2 + Self.faceSize.height / 2)
                ZStack(alignment: .top) {
                    if isEmpty {
                        greeting
                            .frame(width: width)
                            .offset(y: emptyY + Self.faceSize.height / 2)
                            .transition(.opacity)
                        // Who you're talking to, picked before the first question.
                        WispPartnerMenu(model: model)
                            .padding(.horizontal, 6)
                            .frame(width: width, height: 24, alignment: .leading)
                    } else {
                        conversation
                            .padding(.top, Self.headerHeight - 10)
                            .frame(width: width, height: height)
                            .transition(.opacity)
                        header
                            .frame(width: width, height: Self.headerHeight)
                            .transition(.opacity)
                    }
                    // One face throughout, so it keeps its pose as it moves between the middle
                    // and the header; it draws over everything and may overflow both.
                    faceView
                        .scaleEffect(isEmpty ? 1 : Self.headerScale)
                        .position(x: width / 2, y: isEmpty ? emptyY : Self.headerHeight / 2)
                        .zIndex(1)
                }
                .frame(width: width, height: height)
            }
            if isEmpty {
                suggestionRow
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            WispAskField(model: model, onEditingChanged: { editing in
                onEditingChanged(editing)
                touch()
            })
        }
        .animation(theme.reduceMotion ? nil : Design.spring(), value: isEmpty)
        .padding(.vertical, 4)
        .coordinateSpace(name: "wispPage")
        .onContinuousHover(coordinateSpace: .named("wispPage")) { phase in
            switch phase {
            case let .active(point):
                touch()
                // Eyes turn to the pointer anywhere on the page: in steps, at most ten times a
                // second, and not at all under Reduce Motion.
                guard !theme.reduceMotion else { return }
                let now = Date()
                guard now.timeIntervalSince(clock.gazeChanged) >= 0.1 else { return }
                let close = hypot(point.x - faceCenter.x, point.y - faceCenter.y) < 130
                if close != pointerNear { pointerNear = close }
                func step(_ value: CGFloat) -> CGFloat { (max(-1, min(1, value)) * 4).rounded() / 4 }
                let next = CGPoint(x: step((point.x - faceCenter.x) / 220), y: step((point.y - faceCenter.y) / 160))
                guard next != gaze else { return }
                clock.gazeChanged = now
                gaze = next
            case .ended:
                gaze = nil
                pointerNear = false
            }
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { now in
            if now.timeIntervalSince(clock.activity) > 90 { model.doze() }
        }
        .onChange(of: model.messages.count) { _ in touch() }
    }

    private func touch() {
        clock.activity = Date()
        model.wake()
    }

    /// Talking: the model tag at the header's left and Start over at its right, both quiet,
    /// with the eyes between them.
    private var header: some View {
        HStack(spacing: 0) {
            WispPartnerMenu(model: model)
            Spacer(minLength: 0)
            Button(action: model.clearConversation) {
                Label("Start over", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(WispQuietButtonStyle())
            .help("Clear the conversation")
        }
        .padding(.horizontal, 6)
    }

    /// The eyes, with the pointer, a poke and where they are on the page.
    private var faceView: some View {
        face
            .onHover { overFace = $0 }
            .background(GeometryReader { proxy in
                let center = CGPoint(x: proxy.frame(in: .named("wispPage")).midX, y: proxy.frame(in: .named("wispPage")).midY)
                // The eyes move between the layouts, so they follow the pointer from where they are.
                Color.clear
                    .onAppear { faceCenter = center }
                    .onChange(of: center) { faceCenter = $0 }
            })
            .contentShape(Rectangle())
            // KemoSabe takes no poke (the owner found it laggy): a click only counts as a touch.
            .onTapGesture { touch(); if shownCharacter == .wisp { model.poke() } }
            .help(shownCharacter == .wisp ? "Poke \(shownCharacter.title)" : shownCharacter.title)
            .accessibilityValue(status)
    }

    #if DEBUG
    /// The wisp scope's cost case: a plain still image in the face's place.
    static var plainFace = false
    #endif

    @ViewBuilder private var face: some View {
        #if DEBUG
        if Self.plainFace {
            Image(systemName: "face.smiling").font(.system(size: 60)).frame(width: Self.faceSize.width, height: Self.faceSize.height)
        } else {
            character
        }
        #else
        character
        #endif
    }

    /// Wisp's eyes, or KemoSabe in their place.
    @ViewBuilder private var character: some View {
        if shownCharacter != .wisp {
            KemoSabeAgentFace(mood: model.mood, size: Self.faceSize.height, gaze: gaze, near: pointerNear)
        } else {
            WispFace(mood: model.mood, size: 80, gaze: gaze, near: pointerNear, curious: overFace)
        }
    }

    /// What the eyes show, in words for VoiceOver.
    private var status: String {
        switch model.mood {
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Talking"
        case .sleepy: return "Dozing"
        case .surprised: return "Surprised"
        case .happy: return "Done"
        case .confused: return "Not sure"
        case .love: return "Pleased"
        case .celebrating: return "Celebrating"
        case .sad: return "Sorry"
        case .idle: return model.messages.isEmpty ? "Ready" : "Anything else?"
        }
    }

    /// "How can I help?" and what works with the current engine, under the eyes.
    private var greeting: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(Self.greetingTitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.nookForeground.opacity(0.9))
            Text(Self.greetingLine(model.engine))
                .font(.system(size: 12))
                .foregroundStyle(theme.nookForeground.opacity(0.5))
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .fixedSize()
    }

    /// The messages, full width under the header: a short conversation sits at the bottom, a
    /// long one scrolls, newest at the bottom, fading at the top under the header.
    private var conversation: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(model.messages) { message in
                            bubble(message, widest: min(geometry.size.width * 0.72, 420)).id(message.id)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(width: geometry.size.width)
                    .frame(minHeight: geometry.size.height, alignment: .bottom)
                }
                // Older lines fade at the top instead of being cut off.
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                             .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
            }
            .onChange(of: model.messages.count) { _ in
                if let last = model.messages.last { withAnimation(theme.reduceMotion ? nil : Design.spring()) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: waitingCards) { focusCard($0) }
            .onAppear {
                if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                focusCard(waitingCards)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Ask me before sharing's cards still waiting, oldest first.
    private var waitingCards: [UUID] { model.messages.compactMap { $0.role == .approval ? $0.approval?.id : nil } }

    /// Keyboard focus goes to the oldest waiting card, and on to the next once it's answered.
    private func focusCard(_ waiting: [UUID]) {
        guard let first = waiting.first else { return }
        if focusedCard.map(waiting.contains) != true { DispatchQueue.main.async { focusedCard = first } }
    }

    /// The suggestions sit just above the field, centred: quiet text, brighter on hover.
    private var suggestionRow: some View {
        HStack(spacing: 4) {
            ForEach(Self.suggestions) { suggestion in
                Button { model.send(suggestion.ask) } label: {
                    Label(suggestion.label, systemImage: suggestion.symbol)
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(WispQuietButtonStyle())
                .help(suggestion.ask)
            }
        }
    }

    /// One style for both sides: the same bubble, yours on the right and a little stronger,
    /// Wisp's on the left in the page's text colour with quoted items in the accent.
    @ViewBuilder private func bubble(_ message: WispMessage, widest: CGFloat) -> some View {
        switch message.role {
        case .user:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                bubbleText(Text(message.text), fill: 0.1)
                    .frame(maxWidth: widest, alignment: .trailing)
            }
        case .wisp:
            HStack(alignment: .top, spacing: 6) {
                // Claude and Codex appear as themselves: their mark beside what they wrote.
                if let partner = message.from {
                    AgentMark(partner: partner, size: 16)
                        .padding(.top, 6)
                        .help(partner.title)
                }
                bubbleText(Self.highlighted(message.text, accent: theme.notch.accent), fill: 0.05)
                    .textSelection(.enabled)
                    .frame(maxWidth: widest, alignment: .leading)
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .approval:
            if let card = message.approval {
                HStack(spacing: 0) {
                    GatewayApprovalCard(card: card, focused: focusedCard == card.id) { decision in
                        model.decide(card.id, decision)
                    }
                    .focused($focusedCard, equals: card.id)
                    .frame(maxWidth: widest, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        case .notice, .shared, .withheld:
            // The gateway's small lines: what was asked and what went, or that nothing did.
            Label(message.text, systemImage: message.role == .shared ? "checkmark.shield"
                  : message.role == .withheld ? "xmark.shield" : "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(theme.nookForeground.opacity(message.role == .withheld ? 0.7 : 0.55))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        }
    }

    private func bubbleText(_ text: Text, fill: Double) -> some View {
        text
            .font(.system(size: 13))
            .foregroundStyle(theme.nookForeground.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(theme.nookForeground.opacity(fill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    /// A reply with what it quotes (the item just added or checked off) in the accent.
    static func highlighted(_ text: String, accent: Color) -> Text {
        var result = Text(""), rest = Substring(text)
        while let open = rest.firstIndex(of: "“"),
              let close = rest[rest.index(after: open)...].firstIndex(of: "”") {
            result = result + Text(String(rest[..<open]))
                + Text(String(rest[open...close])).foregroundColor(accent).fontWeight(.medium)
            rest = rest[rest.index(after: close)...]
        }
        return result + Text(String(rest))
    }
}

/// Ask me before sharing: a cloud model's question to KemoSabe and exactly the answer that would
/// go, with Share and Don't share. Focused, Return shares and Escape declines. Left alone, it
/// declines when its time runs out, shown as a quiet countdown.
struct GatewayApprovalCard: View {
    let card: GatewayApproval
    let focused: Bool
    let decide: (GatewayApproval.Decision) -> Void
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Who asked and what, in one line: the question is the model's own words, shown as text.
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.notch.accent)
                (Text("\(card.service) asked ").foregroundColor(theme.nookForeground.opacity(0.6))
                    + Text(verbatim: "“\(card.question)”").fontWeight(.semibold).foregroundColor(theme.nookForeground.opacity(0.9)))
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                countdown
            }
            // Exactly what would be sent, never rewritten.
            Text(verbatim: card.draft)
                .font(.system(size: 13))
                .foregroundStyle(theme.nookForeground.opacity(0.92))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(theme.nookForeground.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 6) {
                Button { decide(.share) } label: { Label("Share", systemImage: "arrow.up.circle.fill").labelStyle(ChipLabelStyle()) }
                    .buttonStyle(WidgetChipStyle(prominent: true))
                    .keyboardShortcut(focused ? .defaultAction : nil)
                    .help("Send this answer to \(card.service)")
                Button { decide(.decline) } label: { Text("Don't share") }
                    .buttonStyle(WidgetChipStyle())
                    .keyboardShortcut(focused ? .cancelAction : nil)
                    .help("\(card.service) is told you declined")
                Spacer(minLength: 6)
                if focused {
                    Text("Return shares · Esc declines")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.nookForeground.opacity(0.42))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(theme.nookForeground.opacity(0.05), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(theme.notch.accent.opacity(focused ? 0.55 : 0.25), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .focusable()
        .approvalFocusRingHidden()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.service) asked \(card.agent) \(card.phrase). Share \(card.draft)?")
    }

    /// Seconds left before it declines by itself, once a second.
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("Declines in " + GatewayApproval.countdown(card.secondsLeft(at: context.date)))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(theme.nookForeground.opacity(0.42))
                .lineLimit(1)
        }
    }

    private struct ChipLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 4) { configuration.icon; configuration.title }
        }
    }
}

private extension View {
    /// The card draws its own focus as a brighter edge; macOS 13 keeps the system ring.
    @ViewBuilder func approvalFocusRingHidden() -> some View {
        if #available(macOS 14.0, *) { focusEffectDisabled() } else { self }
    }
}

/// Names the model answering plain-language chat ("Apple Intelligence", or "Offline"
/// when none can); its tooltip says what that means. Other engines show here too.
struct WispModelTag: View {
    let engine: WispEngine
    /// It's the talk-to menu's label: a small chevron says it opens.
    var menu = false
    @ObservedObject private var theme = ThemeStore.shared

    init(engine: WispEngine, menu: Bool = false) {
        self.engine = engine
        self.menu = menu
    }

    var body: some View {
        HStack(spacing: 4) {
            if let partner = engine.partner {
                // Claude and Codex as themselves, in their own colours even when not connected.
                AgentMark(partner: partner, size: 12).opacity(engine.isModel ? 1 : 0.6)
            } else {
                Image(systemName: engine.symbol)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(engine.name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            if menu {
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
        }
        .foregroundStyle(theme.nookForeground.opacity(engine.isModel ? 0.6 : 0.45))
        .help(engine.detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Model: \(engine.name). \(engine.detail)")
    }
}

/// Small text buttons that stay quieter than the conversation until pointed at.
private struct WispQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WispQuietLabel(configuration: configuration)
    }

    private struct WispQuietLabel: View {
        let configuration: ButtonStyleConfiguration
        @ObservedObject private var theme = ThemeStore.shared
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .regular))
                .labelStyle(WispSuggestionLabelStyle())
                .foregroundStyle(theme.nookForeground.opacity(hovering || configuration.isPressed ? 0.85 : 0.5))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(theme.nookForeground.opacity(hovering ? 0.07 : 0), in: Capsule())
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(Design.hoverAnimation, value: hovering)
        }
    }
}

private struct WispSuggestionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10, weight: .medium))
            configuration.title
        }
    }
}

/// Type or talk to Wisp. Return sends; the mic listens until you pause.
struct WispAskField: View {
    @ObservedObject var model: WispModel
    var autofocus = false
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var voice: WispVoice
    @ObservedObject private var theme = ThemeStore.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    init(model: WispModel, autofocus: Bool = false, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.model = model
        self.autofocus = autofocus
        self.onEditingChanged = onEditingChanged
        voice = model.voice
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(WispModel.placeholder, text: voice.isListening ? .constant(voice.transcript) : $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .disabled(voice.isListening)
                .onSubmit(submit)
            if model.isThinking {
                ProgressView().controlSize(.small)
            }
            Button { model.toggleListening() } label: {
                Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(voice.isListening ? Color.black.opacity(0.85) : theme.notch.accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(voice.isListening ? theme.notch.accent : theme.nookForeground.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(voice.isListening ? "Stop listening" : "Talk to \(WispModel.partnerName)")
            .accessibilityLabel(voice.isListening ? "Stop listening" : "Talk to \(WispModel.partnerName)")
        }
        .padding(.leading, 13).padding(.trailing, 4)
        .frame(height: 36)
        .background(theme.nookForeground.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? theme.notch.accent.opacity(0.5) : theme.nookForeground.opacity(0.1)))
        // Only words in the field, or an answer on its way, hold the Nook open. An empty field
        // with the cursor in it doesn't: the Nook closes when the pointer leaves.
        .onChange(of: focused) { _ in reportEditing() }
        .onChange(of: text) { _ in reportEditing() }
        .onChange(of: model.isThinking) { _ in reportEditing() }
        .onChange(of: model.awaitsApproval) { _ in reportEditing() }
        .onExitCommand { focused = false }
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }

    private func reportEditing() {
        // A card waiting on Share or Don't share holds it open too, wherever the focus is.
        onEditingChanged((focused && (!text.isEmpty || model.isThinking)) || model.awaitsApproval)
    }

    private func submit() {
        // While Wisp is still answering, the text stays in the field.
        if model.send(text) { text = "" }
    }
}
