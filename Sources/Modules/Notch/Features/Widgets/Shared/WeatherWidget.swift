import SwiftUI

struct WeatherWidget: View {
    @ObservedObject var service: WeatherService
    var compact = false
    var surface: ThemeSurface = .dock
    var onDetailsChanged: (Bool) -> Void = { _ in }
    @State private var showingDetails = false
    @State private var widgetHovered = false
    @State private var popoverHovered = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let weather = service.snapshot {
                if compact {
                    VStack(spacing: 5) {
                        HStack(spacing: 7) {
                            Image(systemName: weather.symbolName).symbolRenderingMode(.multicolor)
                            Text("\(Int(weather.temperature.rounded()))°")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                        }
                        Text("H \(Int(weather.high.rounded()))°  L \(Int(weather.low.rounded()))°")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }.padding(.horizontal, 8)

                } else {
                    VStack(spacing: 3) {
                        Image(systemName: weather.symbolName)
                            .font(.system(size: 18))
                            .symbolRenderingMode(.multicolor)
                        Text("\(Int(weather.temperature.rounded()))°")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("H \(Int(weather.high.rounded()))°  L \(Int(weather.low.rounded()))°")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = service.errorText {
                VStack(spacing: 4) {
                    Image(systemName: "cloud.slash")
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { service.startIfNeeded() }
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetails.toggle()
        }
        .onHover { hovering in
            widgetHovered = hovering
            if hovering {
                dismissTask?.cancel()
                showingDetails = true
            } else {
                scheduleDismiss()
            }
        }
        .popover(isPresented: $showingDetails, arrowEdge: .top) {
            if let weather = service.snapshot {
                WeatherDetailsView(weather: weather, surface: surface)
                    .onHover { hovering in
                        popoverHovered = hovering
                        if hovering {
                            dismissTask?.cancel()
                        } else {
                            scheduleDismiss()
                        }
                    }
            }
        }
        .onChange(of: showingDetails) { onDetailsChanged($0) }
        .onDisappear {
            onDetailsChanged(false)
            dismissTask?.cancel()
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled,
                  !widgetHovered,
                  !popoverHovered else { return }
            showingDetails = false
        }
    }
}

struct WeatherDetailsView: View {
    let weather: WeatherSnapshot
    var surface: ThemeSurface = .notch
    private var tokens: ThemeTokens { surface == .notch ? theme.notch : theme.dock }
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 26, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(weather.conditionName)
                        .font(.system(size: 14, weight: .semibold))
                    Text("Local forecast")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(weather.temperature.rounded()))°")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }

            HStack(spacing: 8) {
                weatherMetric(
                    "High",
                    value: "\(Int(weather.high.rounded()))°",
                    symbol: "arrow.up"
                )
                weatherMetric(
                    "Low",
                    value: "\(Int(weather.low.rounded()))°",
                    symbol: "arrow.down"
                )
                weatherMetric(
                    "Range",
                    value: "\(Int((weather.high - weather.low).rounded()))°",
                    symbol: "arrow.up.and.down"
                )
            }
        }
        .padding(16)
        .frame(width: 300)
        .background {
            ZStack {
                VisualEffectView(material: .popover)
                tokens.surface.opacity(0.76)
            }
        }
        .environment(\.colorScheme, tokens.colorScheme)
    }

    private func weatherMetric(
        _ title: String,
        value: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            tokens.control.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}
