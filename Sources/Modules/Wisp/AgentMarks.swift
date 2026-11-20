import AppKit
import SwiftUI

/// Claude's and Codex's own mark in the chat: their app's icon when it's installed (Claude, Codex
/// or ChatGPT), else a drawn stand-in: Claude's coral spark, Codex's prompt on black. The
/// on-device agent shows the Apple logo, since Apple Intelligence answers.
struct AgentMark: View {
    let partner: WispProvider
    var size: CGFloat = 14

    @MainActor private static var icons: [WispProvider: NSImage?] = [:]

    @MainActor private static func icon(_ partner: WispProvider) -> NSImage? {
        if let cached = icons[partner] { return cached }
        let brands: [String]
        switch partner {
        case .claude: brands = ["com.anthropic.claudefordesktop"]
        case .openAI: brands = ["com.openai.codex", "com.openai.chat"]
        default: brands = []
        }
        let icon = brands.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[partner] = icon
        return icon
    }

    var body: some View {
        Group {
            if let icon = Self.icon(partner) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                switch partner {
                case .claude:
                    ClaudeSpark().fill(Color(red: 0.85, green: 0.47, blue: 0.34))
                case .openAI:
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Color.black)
                        .overlay(Text(">_").font(.system(size: size * 0.5, weight: .bold, design: .monospaced)).foregroundStyle(.white))
                case .apple:
                    Image(systemName: "apple.logo").resizable().scaledToFit()
                case .compatible:
                    Image(systemName: "key.horizontal").resizable().scaledToFit()
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Claude's spark: rays of a few lengths around a small centre.
struct ClaudeSpark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let lengths: [CGFloat] = [1, 0.78, 0.92, 0.7, 0.98, 0.8, 0.9, 0.74, 1, 0.82, 0.88, 0.72]
        for (index, length) in lengths.enumerated() {
            let angle = CGFloat(index) / CGFloat(lengths.count) * 2 * .pi - .pi / 2
            let tip = CGPoint(x: centre.x + cos(angle) * radius * length, y: centre.y + sin(angle) * radius * length)
            let side = radius * 0.11
            let normal = CGPoint(x: -sin(angle) * side, y: cos(angle) * side)
            path.move(to: CGPoint(x: centre.x + normal.x, y: centre.y + normal.y))
            path.addLine(to: tip)
            path.addLine(to: CGPoint(x: centre.x - normal.x, y: centre.y - normal.y))
            path.closeSubpath()
        }
        path.addEllipse(in: CGRect(x: centre.x - radius * 0.2, y: centre.y - radius * 0.2, width: radius * 0.4, height: radius * 0.4))
        return path
    }
}

/// The chat's "talk to" menu, at the page's top left: the on-device agent, Claude or Codex (and
/// another service once one is set up), then the model for Claude or Codex. Its label is the tag
/// naming who answers.
struct WispPartnerMenu: View {
    @ObservedObject var model: WispModel
    @ObservedObject private var connections = AgentConnections.shared
    @AppStorage(WispProvider.key) private var provider: WispProvider = .apple
    @AppStorage(WispProvider.addressKey) private var address = ""
    @AppStorage(WidgetOptions.Keys.wispCharacter) private var character: WispCharacter = .wisp

    init(model: WispModel) {
        self.model = model
    }

    private var choices: [WispProvider] {
        [.apple, .claude, .openAI] + (provider == .compatible || !address.isEmpty ? [.compatible] : [])
    }

    var body: some View {
        Menu {
            Picker("Talk to", selection: Binding(get: { provider }, set: { provider = $0; model.providerChanged() })) {
                ForEach(choices) { Text(row($0)).tag($0) }
            }
            .pickerStyle(.inline)
            if provider.cli != nil {
                Picker("Model", selection: Binding(get: { provider.modelInUse }, set: { provider.setModel($0); model.providerChanged() })) {
                    ForEach(provider.modelChoices, id: \.self) { Text(WispProvider.modelTitle($0)).tag($0) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            WispModelTag(engine: model.engine, menu: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Who you're talking to")
        .onAppear { connections.refresh() }
    }

    private func row(_ choice: WispProvider) -> String {
        _ = character; _ = connections.status
        if choice == .apple { return "\(choice.title), on this Mac" }
        return choice.setupProblem == nil ? choice.title : "\(choice.title) (not connected)"
    }
}
