import SwiftUI

/// Wisp's page (`NotchTab.wisp`), with no columns. Empty, the eyes are the hero in the middle
/// with "How can I help?" under them, the suggestions just above the ask field. Talking, the eyes
/// move up into a slim header band at the top centre, with the model tag at its left and Start
/// over at its right, and the conversation runs full width below, newest at the bottom, fading
/// under the header. The ask field always spans the page along the bottom. There's no status
/// line: the eyes show it (it's the face's accessibility value). The eyes watch the pointer,
/// react when poked, doze when left alone, and may grow past the header without moving anything.
struct WispPage: View {
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
        Suggestion(label: "Tea timer, 4 minutes", symbol: "timer", ask: "Tea timer 4 minutes"),
    ]

    private var isEmpty: Bool { model.messages.isEmpty }

    private static let greetingTitle = "How can I help?"
    /// The header band's height while talking, and the eyes' scale there.
    private static let headerHeight: CGFloat = 58, headerScale: CGFloat = 0.68
    /// The face's footprint at full size (`WispFace` at 80 pt).
    private static let faceSize = CGSize(width: 116, height: 92)

    private static func greetingLine(_ engine: WispEngine) -> String {
        engine.isModel ? "Ask anything, or set a reminder, note, focus or timer." : "Reminders, notes, focus, timers and your day."
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
            WispModelTag(engine: model.engine)
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
            .onTapGesture { touch(); model.poke() }
            .help("Poke Wisp")
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
            WispFace(mood: model.mood, size: 80, gaze: gaze, near: pointerNear, curious: overFace)
        }
        #else
        WispFace(mood: model.mood, size: 80, gaze: gaze, near: pointerNear, curious: overFace)
        #endif
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
                if let last = model.messages.last { withAnimation(Design.spring()) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onAppear { if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            HStack(spacing: 0) {
                bubbleText(Self.highlighted(message.text, accent: theme.notch.accent), fill: 0.05)
                    .textSelection(.enabled)
                    .frame(maxWidth: widest, alignment: .leading)
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .notice:
            Label(message.text, systemImage: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(theme.nookForeground.opacity(0.55))
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

/// Names the model answering plain-language chat ("Apple Intelligence", or "Offline"
/// when none can); its tooltip says what that means. Other engines show here too.
struct WispModelTag: View {
    let engine: WispEngine
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: engine.symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(engine.name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
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
            .help(voice.isListening ? "Stop listening" : "Talk to Wisp")
            .accessibilityLabel(voice.isListening ? "Stop listening" : "Talk to Wisp")
        }
        .padding(.leading, 13).padding(.trailing, 4)
        .frame(height: 36)
        .background(theme.nookForeground.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? theme.notch.accent.opacity(0.5) : theme.nookForeground.opacity(0.1)))
        .onChange(of: focused) { onEditingChanged($0) }
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }

    private func submit() {
        let message = text
        text = ""
        model.send(message)
    }
}
