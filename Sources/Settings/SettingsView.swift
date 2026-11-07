import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreLocation
import ApplicationServices
import UserNotifications
import CoreBluetooth

@MainActor
final class SettingsNavigationModel: ObservableObject {
    static let shared = SettingsNavigationModel()
    @Published var selection: SettingsDestination = .general
    @Published var searchTarget: String?
    @Published var searchQuery = ""

    func open(_ destination: SettingsDestination, card: String? = nil) {
        searchQuery = ""
        selection = destination
        searchTarget = card
    }
}

struct SettingsView: View {
    static let titleBarHeight: CGFloat = 28
    @ObservedObject private var navigation = SettingsNavigationModel.shared
    @ObservedObject private var appearance = ThemeStore.shared

    private var query: String {
        get { navigation.searchQuery }
        nonmutating set { navigation.searchQuery = newValue }
    }
    @State private var resultIndex = 0
    @State private var compactSearch = false
    @FocusState private var searchFocused: Bool

    private var results: [SettingsSearchEntry] { SettingsSearch.matches(query) }

    /// Always fills the window it's given, pinned to the leading edge. macOS
    /// window tiling can make a window narrower than its minimum size; the
    /// sidebar then shrinks to icons instead of the layout overflowing.
    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 720
            HStack(spacing: 0) {
                sidebar(compact: compact)
                    .frame(width: compact ? 60 : 214)

                Rectangle()
                    .fill(appearance.settings.border)
                    .frame(width: 1)

                detail
                    // Pages start below the title bar but scroll up under it,
                    // fading out, so there's no separate strip across the top.
                    .scrollContentTopMargin(Self.titleBarHeight)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [appearance.settings.surface, appearance.settings.surface.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.titleBarHeight + 8)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        // The whole window, title bar included: the sidebar and its divider run to the top edge.
        .ignoresSafeArea(.container, edges: .top)
        .background(appearance.settings.surface)
        .foregroundStyle(appearance.settingsForeground)
        .preferredColorScheme(appearance.settings.colorScheme)
        .tint(appearance.settings.accent)
        .background {
            Button { compactSearch = true; searchFocused = true } label: { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .onChange(of: query) { _ in resultIndex = 0 }
        .onChange(of: navigation.selection) { _ in query = ""; compactSearch = false }
    }

    private var searchField: some View {
        SettingsSearchField(text: $navigation.searchQuery, focused: searchFocused,
                            onClear: { navigation.searchTarget = nil }) {
            TextField("Search settings", text: $navigation.searchQuery)
                .focused($searchFocused)
                .accessibilityLabel("Search settings")
                .onSubmit { if results.indices.contains(resultIndex) { openResult(results[resultIndex]) } }
                .textFieldKeys(up: { resultIndex = max(0, resultIndex - 1) },
                               down: { resultIndex = min(max(0, results.count - 1), resultIndex + 1) },
                               escape: { query = ""; searchFocused = false; compactSearch = false })
        }
    }

    private func openResult(_ result: SettingsSearchEntry) {
        query = ""; compactSearch = false; searchFocused = false
        navigation.open(result.destination, card: result.card)
    }

    private var searchResults: some View {
        SettingsPage(title: "Search", subtitle: "\(results.count) matching section\(results.count == 1 ? "" : "s")",
                     scrollAnchor: results.indices.contains(resultIndex) ? "search." + results[resultIndex].id : nil) {
            if results.isEmpty {
                NoSearchResultsView(text: query)
            } else {
                VStack(spacing: 6) {
                    ForEach(results.indices, id: \.self) { index in
                        let result = results[index]
                        Button { openResult(result) } label: {
                            HStack(spacing: 12) {
                                pageIcon(result.destination).frame(width: 22)
                                    .foregroundStyle(appearance.settings.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.card).font(.system(size: 14, weight: .semibold))
                                    Text(result.destination.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12).contentShape(Rectangle())
                            .background(index == resultIndex ? appearance.settings.selected : appearance.settings.tile,
                                        in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).id("search." + result.id)
                    }
                }
            }
        }
    }

    private func sidebar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                MacSpacesMark(size: compact ? 30 : 34)
                if !compact {
                    Text("MacSpaces")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 15 : 16)
            .padding(.top, 20 + Self.titleBarHeight)
            .padding(.bottom, 16)

            Group {
                if compact {
                    Button { compactSearch = true } label: { Image(systemName: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 30) }
                        .buttonStyle(.plain).accessibilityLabel("Search settings")
                        .popover(isPresented: $compactSearch) {
                            searchField.frame(width: 240).padding(12).onAppear { searchFocused = true }
                        }
                } else { searchField }
            }
            .padding(.horizontal, compact ? 8 : 10).padding(.bottom, 12)

            VStack(spacing: 3) {
                // Small labels group the pages, like macOS sidebars; they don't collapse.
                let pages = SettingsDestination.allCases
                ForEach(Array(pages.enumerated()), id: \.element) { index, destination in
                    let previous = index > 0 ? pages[index - 1] : nil
                    if destination.section != previous?.section {
                        if !compact {
                            Text(destination.section.uppercased())
                                .font(.system(size: 10, weight: .semibold)).tracking(0.4)
                                .foregroundStyle(appearance.settingsForeground.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 10).padding(.top, index > 0 ? 12 : 0).padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        } else if index > 0 {
                            Spacer().frame(height: 8)
                        }
                    }
                    sidebarItem(destination, compact: compact)
                }
            }
            .padding(.horizontal, compact ? 8 : 10)

            Spacer(minLength: 14)
        }
        .background(appearance.settings.tile)
    }

    /// An SF Symbol, except Tape, Tsukumo and Folio, which wear their own marks; all in the
    /// sidebar's colours, like every other page.
    @ViewBuilder
    private func pageIcon(_ destination: SettingsDestination) -> some View {
        switch destination {
        case .tape: Image(nsImage: TapeMark.image(size: 17)).renderingMode(.template)
        case .tsukumo: TsukumoGlyph(size: 17)
        case .folio: FolioGlyph(size: 13)
        default: Image(systemName: destination.symbol)
        }
    }

    private func sidebarItem(_ destination: SettingsDestination, compact: Bool) -> some View {
        let selected = navigation.selection == destination
        return Button {
            query = ""; compactSearch = false
            navigation.open(destination)
        } label: {
            HStack(spacing: 10) {
                pageIcon(destination)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? appearance.settings.accent : appearance.settingsForeground.opacity(0.65))
                    .frame(width: 19)
                if !compact {
                    Text(destination.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: compact ? .infinity : nil)
            .padding(.horizontal, compact ? 0 : 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(
                selected ? appearance.settings.selected : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(compact ? destination.title : "")
        .accessibilityLabel(destination.title)
    }

    @ViewBuilder
    private var detail: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults
        } else {
        switch navigation.selection {
        case .general: GeneralSettingsPane()
        case .dock: SettingsPage(title: "Dock", subtitle: "The app pages under the Nook.") {
            DockAppsCard(settings: NookSettings.shared)
        }
        case .widgets: NookSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .permissions: SettingsPage(title: "Permissions", subtitle: "See what each widget can access, and why.") { WidgetAccessSettings() }
        case .activities: ActivitiesSettingsPane()
        case .heartable: HeartableSettingsPane()
        case .tape: TapeSettingsPane()
        case .tsukumo: TsukumoSettingsPane()
        case .folio: FolioSettingsPane()
        }
        }
    }
}

private struct AppearanceSettingsPane: View {
    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Choose a theme. The Nook takes care of its size and styling.") {
            NookThemePicker()
        }
    }
}

/// Automatic update preferences and the manual check, shown in General.
struct SoftwareUpdateCard: View {
    @ObservedObject private var updater = UpdateService.shared

    private var updateAvailable: Bool {
        if case .available = updater.status { return true }
        return false
    }
    private var channel: String {
        updater.followsPrereleases ? "Pre-release · gets every new build" : "Stable release"
    }
    var body: some View {
        SettingsCard("Updates", systemImage: "arrow.triangle.2.circlepath") {
            HStack(spacing: 12) {
                MacSpacesMark(size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacSpaces \(installedVersion)").font(.system(size: 14, weight: .semibold))
                        .help(installedBuild.map { "Build \($0)" } ?? "")
                    Text(updater.status == .idle ? channel : updater.status.label)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(updater.actionLabel) { updater.performPrimaryAction() }
                    .buttonStyle(.settings(updateAvailable ? .primary : .secondary)).disabled(updater.isBusy)
            }
            Divider()
            Toggle("Check automatically", isOn: $updater.automaticallyCheckForUpdates)
            if updater.automaticallyCheckForUpdates {
                Toggle("Download updates when available", isOn: $updater.automaticallyInstallUpdates)
            }
        }
    }

    /// Just the version ("3.0"). The build number only orders updates, so it's kept
    /// out of sight and shown on hover (owner, after 3.0).
    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var installedBuild: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}

struct MacSpacesMark: View {
    let size: CGFloat

    var body: some View {
        Group {
            if
                let url = Bundle.main.url(
                    forResource: "MacSpacesIcon-master",
                    withExtension: "png"
                ),
                let image = NSImage(contentsOf: url)
            {
                // The master artwork is full-bleed; round it like a Dock icon.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(ThemeStore.shared.accent)
                    .overlay {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: size * 0.25, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.22), radius: size * 0.12, y: size * 0.06)
    }
}
