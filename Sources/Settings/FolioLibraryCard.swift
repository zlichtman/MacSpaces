import SwiftUI

/// Settings → Folio → Library: what the Tray and baskets' search knows, and Read Again.
struct FolioLibraryCard: View {
    @ObservedObject private var library = FolioIndex.shared

    var body: some View {
        SettingsCard("Library", systemImage: "books.vertical") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary)
                    SettingsCaption("Search finds words in pictures and PDFs and what photos show. Read on this Mac.",
                                    help: "Vision reads each file in the Tray and your baskets once, in the background, and again when it changes. Lines that look like passwords or keys are left out. Nothing leaves this Mac.")
                }
                Spacer(minLength: 8)
                Button("Read Again") { library.readAgain() }
                    .buttonStyle(.settings(.secondary))
                    .disabled(library.waitingCount > 0)
                    .help("Forget what was read and read every file in the Tray and baskets again")
            }
        }
    }

    private var summary: String {
        let pictures = library.records.values.filter { $0.print != nil }.count
        let files = library.records.count
        var text = files == 1 ? "1 file read" : "\(files) files read"
        if pictures > 0 { text += pictures == 1 ? ", 1 picture" : ", \(pictures) pictures" }
        if library.waitingCount > 0 { text += " · reading \(library.waitingCount) more" }
        return text
    }
}

/// Settings → Folio → Sources: what comes into Folio on its own: watched folders (each a place of
/// its own), completed downloads and new screenshots (both into the Tray).
struct FolioSourcesCard: View {
    @ObservedObject private var screenshots = ScreenshotWatcher.shared

    var body: some View {
        SettingsCard("Sources", systemImage: "tray.and.arrow.down") {
            FolioWatchedFoldersList()
            Divider()
            SettingsSection("Downloads") {
                CompletedDownloadsSettings()
            }
            Divider()
            SettingsSection("Screenshots") {
                Toggle("Add new screenshots to the Tray", isOn: Binding(
                    get: { screenshots.isEnabled }, set: { screenshots.setEnabled($0) }))
                SettingsCaption("The file stays where macOS saves it. The thumbnail beside the notch is under Activities.",
                                help: "Each screenshot waits in the Tray, ready to drag into an email, AirDrop, copy, or turn into text. If macOS saves them to the Desktop, it asks once for access.")
            }
        }
    }
}

/// Settings → Folio → File Converter: Shift-drag a file for a wheel of formats.
struct FileConverterCard: View {
    @ObservedObject private var app = AppSettings.shared
    @AppStorage(WidgetOptions.Keys.converterRevealResults) private var revealResults = false

    var body: some View {
        SettingsCard("File Converter", systemImage: "arrow.triangle.2.circlepath") {
            Toggle("Convert files by Shift-dragging", isOn: $app.fileConverterEnabled)
            Toggle("Reveal results in Finder", isOn: $revealResults)
            HStack(spacing: 10) {
                SettingsCaption("⌥⇧-drag for tools such as compress. Copies go beside the original.",
                                help: "Hold Shift while dragging a file for a wheel of formats; Option-Shift shows tools such as compress and remove metadata. Copies are saved beside the original, and nothing leaves your Mac.")
                Spacer(minLength: 8)
                Button("Open File Tools") { FileToolsModel.shared.open() }.buttonStyle(.settings())
            }
        }
    }
}
