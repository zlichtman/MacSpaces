import SwiftUI

/// Tab strip shown at the top of the expanded nook.
struct NotchHeaderView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var theme = ThemeStore.shared

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
                    if !viewModel.settings.widgets.isEmpty {
                        AddNookWidgetMenu(settings: viewModel.settings)
                    }

                    Menu {
                        SurfacePaletteMenuContent(surface: .notch) {
                            viewModel.collapse()
                            SettingsWindowController.shared.show(.notch)
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
                    .help("Change OpenNotch Palette")

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
                    .buttonStyle(.plain)
                    .help(
                        viewModel.settings.showTeleprompterBar
                            ? "Hide Teleprompter"
                            : "Show Teleprompter"
                    )
                }

                Button {
                    viewModel.collapse()
                    SettingsWindowController.shared.show(.notch)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Nook Settings")

                Button {
                    viewModel.collapse()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Nook")
            }
            .foregroundStyle(.secondary)
            .background(Color.white.opacity(0.075), in: Capsule())
        }
    }

    private func tabButton(_ tab: NotchTab) -> some View {
        let isSelected = viewModel.selectedTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                viewModel.selectedTab = tab
            }
        } label: {
            Group {
                if theme.compactControls {
                    Image(systemName: tab.systemImage)
                        .frame(width: 14)
                } else {
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.titleAndIcon)
                }
            }
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.72))
        }
        .buttonStyle(.plain)
    }
}
