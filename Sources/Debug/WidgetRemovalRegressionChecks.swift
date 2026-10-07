#if DEBUG
import AppKit
import SwiftUI

@MainActor enum WidgetRemovalRegressionChecks {
    static func run() async {
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.FeatureQA")
        let settings = NookSettings.shared
        settings.widgets = [.clock, .calculator, .timer]
        SettingsWindowController.shared.show(.widgets)
        let model = NotchViewModel(geometry: .synthetic, availableWidth: 1440, settings: settings,
            shelf: ShelfStore.shared, nowPlaying: AppServices.shared.nowPlaying,
            powerMonitor: AppServices.shared.powerMonitor, timerService: AppServices.shared.timerService,
            bluetoothMonitor: AppServices.shared.bluetooth, systemActivityMonitor: AppServices.shared.systemActivity,
            teleprompter: AppServices.shared.teleprompter)
        model.state = .expanded
        let frame = NSRect(x: 100, y: 400, width: 1250, height: 430)
        let window = NotchWindow(contentRect: frame)
        window.owner = model
        let host = NotchHostingView(rootView: NotchContainerView(viewModel: model))
        window.installNookContent(host)
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close(); SettingsWindowController.shared.window?.close() }
        for index in 0..<60 {
            if index.isMultiple(of: 5) {
                settings.setSize(index.isMultiple(of: 10) ? .large : .medium, for: .calculator)
                model.state = .collapsed
                model.expand(to: .nook)
                try? await Task.sleep(for: .milliseconds(180))
                if let field = textField(in: host) {
                    window.makeFirstResponder(field)
                    try? await Task.sleep(for: .milliseconds(80))
                }
                SettingsWindowController.shared.window?.makeKeyAndOrderFront(nil)
            }
            if index.isMultiple(of: 2) { model.collapse() }
            model.selectedWidget = .calculator
            model.removeSelectedWidget()
            if index.isMultiple(of: 2) { model.expand(to: .nook) }
            try? await Task.sleep(for: .milliseconds(index.isMultiple(of: 5) ? 650 : 180))
            precondition(window.frame == frame, "Widget removal cannot resize the AppKit-owned Nook host")
            precondition(!settings.widgets.contains(.calculator))
            precondition(!model.isPageEditing, "Removing a focused calculator releases the editing guard")
            model.undoRemoveWidget()
            try? await Task.sleep(for: .milliseconds(180))
            precondition(window.frame == frame, "Undo cannot resize the Nook host")
            if index.isMultiple(of: 3) {
                model.collapse()
                withAnimation(Design.spring()) { settings.setEnabled(false, for: .calculator) }
                // Opening while both windows consume the removal transaction
                // is the owner's reported intermittent trigger.
                model.expand(to: .nook)
                try? await Task.sleep(for: .milliseconds(180))
                settings.setEnabled(true, for: .calculator)
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
        precondition(host.superview === window.contentView && window.contentView !== host)
        print("Widget removal checks passed: Settings and Nook open, calculator removal/Undo and settings-side removal, stable host frame")
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        for child in view.subviews { if let field = textField(in: child) { return field } }
        return nil
    }
}
#endif
