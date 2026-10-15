import SwiftUI

struct WeatherWidget: View {
    @ObservedObject var service: WeatherService
    var compact = false
    var showsForecast = false

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
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: weather.symbolName)
                                .font(.system(size: 26))
                                .symbolRenderingMode(.multicolor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(Int(weather.temperature.rounded()))°")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                Text(weather.conditionName)
                                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                        Text("H \(Int(weather.high.rounded()))°  L \(Int(weather.low.rounded()))°")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        if showsForecast, !weather.upcoming.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(weather.upcoming.prefix(4)) { day in
                                    VStack(spacing: 3) {
                                        Text(day.date, format: .dateTime.weekday(.abbreviated))
                                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                                        Image(systemName: day.symbolName).symbolRenderingMode(.multicolor)
                                            .font(.system(size: 13)).frame(height: 16)
                                        Text("\(Int(day.high.rounded()))°").font(.system(size: 10, weight: .semibold))
                                        Text("\(Int(day.low.rounded()))°").font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                    .padding(.bottom, 6)
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
        .nookAfterOpening { service.startIfNeeded() }
    }
}
