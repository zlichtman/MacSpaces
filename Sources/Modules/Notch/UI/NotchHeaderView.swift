import SwiftUI

/// Tab strip shown at the top of the expanded nook.
struct NotchHeaderView: View {
    @ObservedObject var viewModel: NotchViewModel
    // Observed separately so the Tray count follows drops and removals.
    @ObservedObject private var shelf: ShelfStore
    @ObservedObject private var theme = ThemeStore.shared
    @Namespace private var tabSelection

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.shelf = viewModel.shelf
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(NotchTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.075), in: Capsule())

            Spacer()

            HStack(spacing: 2) {
                if viewModel.selectedTab == .nook {
                    AddNookWidgetMenu(settings: viewModel.settings)
                        .fixedSize()

                    Menu {
                        SurfacePaletteMenuContent(surface: .notch) {
                            viewModel.collapse()
                            SettingsWindowController.shared.show(.appearance)
                        }
                    } label: {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.notch.accent)
                            .frame(width: 28, height: 26)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Change Nook Theme")

                    Button {
                        withAnimation(Design.spring()) {
                            viewModel.settings.showTeleprompterBar.toggle()
                        }
                    } label: {
                        Image(
                            systemName: viewModel.settings.showTeleprompterBar
                                ? "captions.bubble.fill"
                                : "captions.bubble"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            viewModel.settings.showTeleprompterBar
                                ? theme.notch.accent
                                : Color.secondary
                        )
                        .frame(width: 28, height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NookIconButtonStyle())
                    .help(
                        viewModel.settings.showTeleprompterBar
                            ? "Hide Teleprompter"
                            : "Show Teleprompter"
                    )
                }

                Button {
                    viewModel.collapse()
                    SettingsWindowController.shared.show(.widgets)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NookIconButtonStyle())
                .help("Nook Settings")

                Button {
                    viewModel.collapse()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NookIconButtonStyle())
                .help("Close Nook")
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.secondary)
            .background(Color.white.opacity(0.075), in: Capsule())
        }
    }

    private func tabButton(_ tab: NotchTab) -> some View {
        let isSelected = viewModel.selectedTab == tab
        let trayCount = tab == .tray ? shelf.items.count : 0
        return Button {
            guard viewModel.selectedTab != tab else { return }
            Haptics.tap()
            withAnimation(Design.spring()) {
                viewModel.selectedTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                if theme.compactControls {
                    Image(systemName: tab.systemImage)
                        .frame(width: 14)
                } else {
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.titleAndIcon)
                }
                if trayCount > 0 {
                    Text("\(trayCount)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(theme.notch.accent.opacity(isSelected ? 0.45 : 0.25), in: Capsule())
                        .foregroundStyle(Color.primary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.72))
                .background {
                    // One pill slides between tabs instead of only the
                    // label weight changing.
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .matchedGeometryEffect(id: "selectedTab", in: tabSelection)
                    }
                }
                .contentShape(Capsule())
                .animation(Design.spring(), value: trayCount)
        }
        .buttonStyle(PremiumPressButtonStyle())
        .help(trayCount > 0 ? "\(tab.title) · \(trayCount) \(trayCount == 1 ? "item" : "items")" : tab.title)
    }
}
