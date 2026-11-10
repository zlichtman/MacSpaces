import SwiftUI

/// Settings → Tsukumo → Voice: the voice models' downloads and a link that opens the Nook on
/// Studio, where the voices are made and kept and the agent's voice is chosen
/// (`RecordedVoicesSettings`).
struct VoiceSettings: View {
    let agent: String

    var body: some View {
        RecordedVoicesSettings(agent: agent)
    }
}
