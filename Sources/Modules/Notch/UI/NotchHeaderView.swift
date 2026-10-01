import SwiftUI

/// App navigation lives below the panel; Home retains the user's widget layout.
struct NotchHeaderView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings: NookSettings
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var tsukumo = TsukumoAgentsClient.shared
    @Namespace private var selection

    /// The Tsukumo page shows only while Tsukumo offers its agents channel.
    private var visiblePages: [NotchTab] {
        settings.dockApps.filter { $0 != .tsukumo || tsukumo.availability == .available || viewModel.selectedTab == .tsukumo }
    }

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
    }

    var body: some View {
        HStack(spacing: 8) {
            if !visiblePages.isEmpty {
                HStack(spacing: 3) {
                    ForEach(visiblePages) { tabButton($0) }
                }
                .padding(4)
                .background(theme.notch.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.nookForeground.opacity(0.12), lineWidth: 0.75))
            }
            HStack(spacing: 3) {
                tabButton(.nook)
                Button {
                    viewModel.collapse()
                    SettingsWindowController.shared.show()
                } label: { dockIcon("gearshape") }
                    .help("Settings").accessibilityLabel("Settings")
                Divider().frame(height: 16).padding(.horizontal, 3)
                Button { viewModel.collapse() } label: { dockIcon("chevron.up") }
                    .help("Close Nook").accessibilityLabel("Close Nook")
            }
            .padding(4)
            .background(theme.notch.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.nookForeground.opacity(0.12), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
        // Hiding the page you're on returns to Home. Tray stays reachable
        // because dropping a file on the notch always opens it.
        .onChange(of: settings.dockApps) { pages in
            let current = viewModel.selectedTab
            if current != .nook, current != .tray, !pages.contains(current) {
                withAnimation(Design.spring()) { viewModel.selectedTab = .nook }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .onAppear { if settings.dockApps.contains(.tsukumo) { tsukumo.refreshAvailability() } }
    }
    private func dockIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 12, weight: .medium))
            .frame(width: 30, height: 30).contentShape(Circle())
    }
    private func tabButton(_ tab: NotchTab) -> some View {
        Button {
            Haptics.tap()
            withAnimation(Design.spring()) { viewModel.selectedTab = tab }
        } label: {
            dockIcon(tab.systemImage)
                .foregroundStyle(viewModel.selectedTab == tab ? theme.notch.accent : theme.nookForeground.opacity(0.65))
                .background {
                    if viewModel.selectedTab == tab {
                        Circle().fill(theme.notch.accent.opacity(0.14))
                            .matchedGeometryEffect(id: "app", in: selection)
                    }
                }
        }.help(tab.title).accessibilityLabel(tab.title)
            .accessibilityAddTraits(viewModel.selectedTab == tab ? .isSelected : [])
    }
}
