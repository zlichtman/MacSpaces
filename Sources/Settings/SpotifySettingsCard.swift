import SwiftUI

/// Music's Stats and Backups use your own Spotify developer app: its Client ID, the redirect
/// URI to add to it, and Connect, in the same shape as Wisp's model card.
struct SpotifySettingsCard: View {
    @ObservedObject private var spotify = SpotifyLibrary.shared
    @State private var clientID = SpotifyLibrary.shared.clientID
    @State private var copied = false

    var body: some View {
        SettingsCard("Spotify", systemImage: "music.note") {
            if let account = spotify.account {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Connected as \(account)")
                    Spacer()
                    Button("Disconnect") { spotify.disconnect() }.buttonStyle(.settings(.destructive))
                }
            } else {
                row("Redirect") {
                    Text(SpotifyLibrary.redirectURI).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SpotifyLibrary.redirectURI, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.settings())
                }
                row("Client ID") {
                    TextField("From your app in Spotify's dashboard", text: $clientID).settingsTextField().onSubmit(connect)
                    Button(spotify.connecting ? "Waiting" : "Connect", action: connect)
                        .buttonStyle(.settings())
                        .disabled(spotify.connecting || clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let problem = spotify.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
            HStack(spacing: 4) {
                Text("For Music's Stats and Backups. Create an app with Web API in")
                Link("Spotify's dashboard", destination: SpotifyLibrary.dashboard)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 64, alignment: .leading)
            content()
        }
    }

    private func connect() {
        spotify.clientID = clientID
        spotify.connect()
    }
}
