import SwiftUI

/// A full-width, low-profile readout beneath the Nook widget row. It keeps the
/// current line centered and the next line visible at lower contrast so the
/// eye can move naturally without turning the Nook into another card.
struct TeleprompterBarView: View {
    @ObservedObject var service: TeleprompterService
    @ObservedObject var settings: NookSettings
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if service.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(
                        systemName: service.source?.systemImage
                            ?? "captions.bubble"
                    )
                    .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(theme.notch.accent)
            .frame(width: 24, height: 24)
            .background(theme.notch.accent.opacity(0.1), in: Circle())

            VStack(alignment: .center, spacing: 1) {
                Text(primaryText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(service.currentText.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .id(primaryText)
                    .transition(.opacity)

                if !service.upcomingText.isEmpty {
                    Text(service.upcomingText)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: primaryText)

            Button {
                withAnimation(Design.spring()) {
                    settings.showTeleprompterBar = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide Teleprompter")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.notch.control.opacity(0.92))
                .overlay {
                    LinearGradient(
                        colors: [
                            theme.notch.accent.opacity(0.08),
                            .clear,
                            theme.notch.secondaryAccent.opacity(0.06),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.notch.accent.opacity(0.18), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            service.source.map { "\($0.rawValue): \(primaryText)" }
                ?? primaryText
        )
    }

    private var primaryText: String {
        if !service.currentText.isEmpty {
            return service.currentText
        }
        return service.statusText
    }
}
