import SwiftUI
import Combine

/// App navigation lives below the panel; Home retains the user's widget layout.
struct NotchHeaderView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings: NookSettings
    @ObservedObject private var theme = ThemeStore.shared
    @Namespace private var selection
    @State private var hasMusicPlaylist: Bool


    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
        _hasMusicPlaylist = State(initialValue: MusicDockControls.hasPlaylist(for: viewModel.nowPlaying.info))
    }

    var body: some View {
        let maximumWidth = min(NotchViewModel.standardPageWidth, viewModel.expandedSize.width) - 16
        let settingsButtons = 1 + (settings.showDockPin ? 1 : 0) + (settings.showDockClose ? 1 : 0)
        let settingsWidth = CGFloat(settingsButtons * 30 + (settingsButtons - 1) * 3 + 8)
        let hasProfiles = viewModel.selectedTab == .nook && settings.profiles.count > 1
        let hasMusic = viewModel.selectedTab == .music
        let hasWisp = viewModel.selectedTab == .wisp
        let naturalControlsWidth: CGFloat = hasMusic ? MusicViewButtons.width(for: viewModel.nowPlaying.info) : hasWisp ? 38 : hasProfiles ? CGFloat(settings.profiles.count * 33 + 5) : 0
        let controlsWidth = min(naturalControlsWidth, max(38, maximumWidth - settingsWidth - 90))
        let gapWidth: CGFloat = naturalControlsWidth > 0 ? 16 : 8
        let appWidth = min(CGFloat(settings.dockPages.count * 33 + 5), max(38, maximumWidth - settingsWidth - controlsWidth - gapWidth))
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(settings.dockPages) { tabButton($0) }
                }
                .padding(4)
            }
            .frame(width: appWidth, height: 38)
            .background(NookBackdrop(shape: Capsule()))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(theme.nookForeground.opacity(0.12), lineWidth: 0.75))
            .accessibilityLabel("App pages")

            if hasMusic {
                MusicViewButtons(nowPlaying: viewModel.nowPlaying)
                    .foregroundStyle(theme.nookForeground.opacity(0.65))
                    .padding(4)
                    .frame(width: controlsWidth, height: 38)
                    .background(NookBackdrop(shape: Capsule()))
                    .overlay(Capsule().strokeBorder(theme.nookForeground.opacity(0.12), lineWidth: 0.75))
                    .accessibilityLabel("Music controls")
            } else if hasProfiles {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(settings.profiles) { homeButton($0) }
                    }.padding(4)
                }
                .frame(width: controlsWidth, height: 38)
                .background(NookBackdrop(shape: Capsule()))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(theme.nookForeground.opacity(0.12), lineWidth: 0.75))
                .accessibilityLabel("Home profiles")
            }
            HStack(spacing: 3) {
                Button {
                    viewModel.collapse()
                    SettingsWindowController.shared.show()
                } label: { dockIcon("gearshape") }
                    .help("Settings").accessibilityLabel("Settings")
                if settings.showDockPin {
                    Button { viewModel.togglePin() } label: { dockIcon(viewModel.isPinned ? "pin.fill" : "pin") }
                        .foregroundStyle(viewModel.isPinned ? theme.notch.accent : theme.nookForeground)
                        .help(viewModel.isPinned ? "Unpin Nook" : "Keep Nook open").accessibilityLabel(viewModel.isPinned ? "Unpin Nook" : "Keep Nook open")
                }
                if settings.showDockClose {
                    Button { viewModel.collapse() } label: { dockIcon("chevron.up") }
                        .help("Close Nook").accessibilityLabel("Close Nook")
                }
            }
            .padding(4)
            .background(NookBackdrop(shape: Capsule()))
            .overlay(Capsule().strokeBorder(theme.nookForeground.opacity(0.12), lineWidth: 0.75))
            .accessibilityLabel("Nook settings and controls")
        }
        .buttonStyle(.plain)
        .onReceive(viewModel.nowPlaying.$info.map { MusicDockControls.hasPlaylist(for: $0) }.removeDuplicates()) {
            hasMusicPlaylist = $0
        }
        // Glass capsules skip the shadow, which would show through them.
        .shadow(color: .black.opacity(theme.family.glassTint == nil ? 0.22 : 0), radius: 6, y: 3)
        // Hiding the page you're on returns to Home. Tray stays reachable
        // because dropping a file on the notch always opens it.
        .onChange(of: settings.dockApps) { pages in
            let current = viewModel.selectedTab
            if current != .nook, current != .tray, !pages.contains(current) {
                withAnimation(Design.spring()) { viewModel.selectedTab = .nook }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    /// On Wisp's page: whether it answers out loud when you talk to it. Lit like the
    /// current Home profile while on.
    private var wispSpeaksButton: some View {
        let on = settings.wispSpeaks
        return Button {
            Haptics.tap()
            withAnimation(Design.spring()) { settings.wispSpeaks.toggle() }
            if !settings.wispSpeaks { WispModel.shared.voice.stopSpeaking() }
        } label: {
            dockIcon(on ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundStyle(on ? theme.notch.accent : theme.nookForeground.opacity(0.65))
                .background { if on { Circle().fill(theme.notch.accent.opacity(0.14)) } }
        }
        .help(on ? "Wisp answers out loud when you talk to it" : "Wisp answers only in writing")
        .accessibilityLabel("Answer out loud")
        .accessibilityValue(on ? "On" : "Off")
    }

    /// A page's dock icon: its symbol, or Wisp's little face.
    @ViewBuilder private func pageIcon(_ tab: NotchTab) -> some View {
        if tab == .wisp {
            WispGlyph(size: 14).frame(width: 30, height: 30).contentShape(Circle())
        } else {
            dockIcon(tab.systemImage)
        }
    }

    private func dockIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 12, weight: .medium))
            .frame(width: 30, height: 30).contentShape(Circle())
    }
    /// Shows that Home: switches the active profile and opens Home.
    private func homeButton(_ profile: NookProfile) -> some View {
        let current = viewModel.selectedTab == .nook && settings.activeProfileID == profile.id
        return Button {
            Haptics.tap()
            withAnimation(Design.spring()) {
                settings.activeProfileID = profile.id
                viewModel.selectedTab = .nook
            }
        } label: {
            dockIcon(settings.symbol(for: profile))
                .foregroundStyle(current ? theme.notch.accent : theme.nookForeground.opacity(0.65))
                .background {
                    if current {
                        Circle().fill(theme.notch.accent.opacity(0.14))
                            .matchedGeometryEffect(id: "profile", in: selection)
                    }
                }
        }
        .help(profile.name).accessibilityLabel("Home: \(profile.name)")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func tabButton(_ tab: NotchTab) -> some View {
        Button {
            Haptics.tap()
            viewModel.pageAnchor = .center
            withAnimation(Design.spring()) { viewModel.selectedTab = tab }
        } label: {
            pageIcon(tab)
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
