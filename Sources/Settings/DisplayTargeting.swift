import AppKit
import CoreGraphics
import SwiftUI

enum DisplayTargetMode: String, Codable, CaseIterable, Identifiable {
    case primary
    case all
    case selected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary: return "Primary"
        case .all: return "All"
        case .selected: return "Choose…"
        }
    }
}

struct DisplayDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let isPrimary: Bool
}

@MainActor
enum DisplayTargeting {
    static var connectedDisplays: [DisplayDescriptor] {
        NSScreen.screens
            .map { screen in
                DisplayDescriptor(
                    id: stableID(for: screen),
                    name: screen.localizedName,
                    isBuiltIn: isBuiltIn(screen),
                    isPrimary: screen == primaryScreen
                )
            }
            .sorted { lhs, rhs in
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func screens(
        mode: DisplayTargetMode,
        selectedIDs: [String],
        preferBuiltIn: Bool
    ) -> [NSScreen] {
        switch mode {
        case .all:
            return NSScreen.screens
        case .selected:
            let ids = Set(selectedIDs)
            let selected = NSScreen.screens.filter { ids.contains(stableID(for: $0)) }
            return selected.isEmpty ? preferredScreens(preferBuiltIn: preferBuiltIn) : selected
        case .primary:
            return preferredScreens(preferBuiltIn: preferBuiltIn)
        }
    }

    static func preferredDisplayID(preferBuiltIn: Bool) -> String? {
        preferredScreens(preferBuiltIn: preferBuiltIn)
            .first
            .map { stableID(for: $0) }
    }

    /// The display that owns the menu bar. Deliberately not `NSScreen.main`,
    /// which tracks keyboard focus and therefore changes whenever the user
    /// clicks a window on another monitor.
    static var primaryScreen: NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { displayID(for: $0) == mainDisplayID }
            ?? NSScreen.screens.first
    }

    private static func preferredScreens(preferBuiltIn: Bool) -> [NSScreen] {
        if preferBuiltIn,
           let builtIn = NSScreen.screens.first(where: isBuiltIn) {
            return [builtIn]
        }
        return primaryScreen.map { [$0] } ?? []
    }

    private static func stableID(for screen: NSScreen) -> String {
        guard let displayID = displayID(for: screen) else {
            return "name:\(screen.localizedName)"
        }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let value = CFUUIDCreateString(nil, uuid) {
            return value as String
        }
        return "display:\(displayID)"
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let displayID = displayID(for: screen) else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}

struct DisplayTargetPicker: View {
    @Binding var mode: DisplayTargetMode
    @Binding var selectedIDs: [String]
    let preferBuiltIn: Bool

    @State private var displays: [DisplayDescriptor] = []

    init(
        mode: Binding<DisplayTargetMode>,
        selectedIDs: Binding<[String]>,
        preferBuiltIn: Bool
    ) {
        self._mode = mode
        self._selectedIDs = selectedIDs
        self.preferBuiltIn = preferBuiltIn
        // `View` initializers are nonisolated under Xcode 15.4. Read NSScreen
        // only after the view enters the main-actor UI lifecycle.
        self._displays = State(initialValue: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Displays", selection: $mode) {
                ForEach(DisplayTargetMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, newMode in
                if newMode == .selected, selectedIDs.isEmpty,
                   let preferred = DisplayTargeting.preferredDisplayID(
                       preferBuiltIn: preferBuiltIn
                   ) {
                    selectedIDs = [preferred]
                }
            }

            if mode == .selected {
                VStack(spacing: 0) {
                    ForEach(displays) { display in
                        Button {
                            toggle(display.id)
                        } label: {
                            HStack(spacing: 9) {
                                Image(
                                    systemName: selectedIDs.contains(display.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    selectedIDs.contains(display.id)
                                        ? Color.accentColor
                                        : Color.secondary
                                )
                                Text(display.name)
                                    .lineLimit(1)
                                Spacer()
                                if display.isBuiltIn {
                                    Text("Built-in")
                                        .foregroundStyle(.secondary)
                                } else if display.isPrimary {
                                    Text("Primary")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                        }
                        .buttonStyle(.plain)

                        if display.id != displays.last?.id {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
                .background(
                    Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            }
        }
        .onAppear(perform: refreshDisplays)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        ) { _ in
            refreshDisplays()
        }
    }

    @MainActor
    private func refreshDisplays() {
        displays = DisplayTargeting.connectedDisplays
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            guard selectedIDs.count > 1 else { return }
            selectedIDs.removeAll { $0 == id }
        } else {
            selectedIDs.append(id)
        }
    }
}
