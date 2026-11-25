import AppKit
import SwiftUI

@MainActor
final class MusicPlaylist: ObservableObject {
    struct Track: Identifiable { let id: String; let title: String; let artist: String }
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var name = "Current playlist"
    @Published private(set) var shuffled = false
    @Published private(set) var repeatMode = "off"
    @Published private(set) var busy = false
    @Published private(set) var problem: String?
    private var playlistID = ""
    private var generation = UUID()
    func refresh() {
        guard !busy else { return }
        generation = UUID(); let token = generation
        busy = true; problem = nil
        AppleScriptRunner.runHandler(Self.script, name: "readplaylist", arguments: []) { [weak self] result in
            guard let self, self.generation == token else { return }
            self.busy = false
            guard !result.failed, let value = result.descriptor, value.numberOfItems == 5,
                  let id = value.atIndex(1)?.stringValue, !id.isEmpty else {
                self.tracks = []; self.playlistID = ""; self.problem = "Open a track in Music, then refresh. Allow Automation if asked."; return
            }
            self.playlistID = id; self.name = value.atIndex(2)?.stringValue ?? "Current playlist"
            self.shuffled = value.atIndex(3)?.booleanValue ?? false; self.repeatMode = value.atIndex(4)?.stringValue ?? "off"
            guard let list = value.atIndex(5) else { self.tracks = []; return }
            self.tracks = (1...max(1, list.numberOfItems)).compactMap { index in
                guard index <= list.numberOfItems, let row = list.atIndex(index), let id = row.atIndex(1)?.stringValue, let title = row.atIndex(2)?.stringValue else { return nil }
                return Track(id: id, title: title, artist: row.atIndex(3)?.stringValue ?? "")
            }
        }
    }
    func perform(_ action: String, track: String = "") {
        guard !busy, !playlistID.isEmpty,
              AppServices.shared.nowPlaying.info.sourceBundleID == "com.apple.Music" || AppServices.shared.nowPlaying.info.sourceName == "Music" else {
            problem = "The playback source changed. Open Music and refresh before using its controls."; return
        }
        busy = true
        AppleScriptRunner.runHandler(Self.script, name: "changeplaylist", arguments: [.text(action), .text(playlistID), .text(track)]) { [weak self] result in
            guard let self else { return }; self.busy = false
            if result.failed { self.problem = "Music couldn't apply that action. The playlist may have changed; refresh first." }
            else { self.refresh() }
        }
    }
    static let script = """
    on readplaylist()
        if application id "com.apple.Music" is not running then return missing value
        tell application id "com.apple.Music"
            set p to current playlist
            set firstIndex to index of current track
            set lastIndex to firstIndex + 20
            set total to count of tracks of p
            if lastIndex > total then set lastIndex to total
            set rows to {}
            if firstIndex < lastIndex then
                repeat with i from (firstIndex + 1) to lastIndex
                    set t to track i of p
                    set end of rows to {persistent ID of t, name of t, artist of t}
                end repeat
            end if
            return {persistent ID of p, name of p, shuffle enabled, song repeat as text, rows}
        end tell
    end readplaylist
    on changeplaylist(actionName, expectedPlaylist, trackID)
        if application id "com.apple.Music" is not running then error "Music closed"
        tell application id "com.apple.Music"
            set p to current playlist
            if persistent ID of p is not expectedPlaylist then error "Playlist changed"
            if actionName is "play" then
                play (first track of p whose persistent ID is trackID)
            else if actionName is "shuffle" then
                set shuffle enabled to not shuffle enabled
            else if actionName is "repeat" then
                if song repeat is off then
                    set song repeat to all
                else if song repeat is all then
                    set song repeat to one
                else
                    set song repeat to off
                end if
            end if
        end tell
    end changeplaylist
    """
}

struct MusicQueueView: View {
    let sourceBundleID: String?
    @StateObject private var music = MusicPlaylist()
    private var isSpotify: Bool { sourceBundleID == "com.spotify.client" }
    private var isMusic: Bool { sourceBundleID == "com.apple.Music" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isSpotify ? "Spotify queue" : isMusic ? music.name : "Playback queue").font(.headline).lineLimit(1)
                Spacer()
                if isMusic { Button("Refresh") { music.refresh() }.disabled(music.busy) }
            }
            if isSpotify {
                Text("Manage what's next in Spotify. Playback controls and lyrics remain available here.").font(.caption).foregroundStyle(.secondary)
                Button("Open Spotify") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
            } else if isMusic {
                Text("Playlist order, not Music's private Up Next queue. Shuffle may play a different order.").font(.caption).foregroundStyle(.secondary)
                if let problem = music.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(music.tracks.enumerated()), id: \.offset) { _, track in
                            Button { music.perform("play", track: track.id) } label: {
                                VStack(alignment: .leading, spacing: 1) { Text(track.title).font(.system(size: 12, weight: .medium)); Text(track.artist).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                            }.buttonStyle(.plain).disabled(music.busy)
                        }
                        if music.tracks.isEmpty && music.problem == nil { Text(music.busy ? "Loading…" : "End of playlist").font(.caption).foregroundStyle(.secondary) }
                    }
                }.frame(maxHeight: 230)
                HStack { Button(music.shuffled ? "Shuffle on" : "Shuffle off") { music.perform("shuffle") }; Button("Repeat: " + music.repeatMode) { music.perform("repeat") } }.disabled(music.busy)
                Button("Open Music") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Music.app"), configuration: .init()) }
            } else {
                Text("This player doesn't provide a supported queue. Open its app to manage what's next.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).frame(width: 380)
        .task(id: sourceBundleID) { if isMusic { music.refresh() } }
    }
}
