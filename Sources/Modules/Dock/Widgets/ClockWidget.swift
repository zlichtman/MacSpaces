import SwiftUI

struct ClockWidget: View {
    let style: WidgetVisualStyle
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if compact {
                    VStack(spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(
                                .system(
                                    size: 15,
                                    weight: .bold,
                                    design: style == .terminal ? .monospaced : .rounded
                                )
                            )
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(context.date, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                } else if style == .terminal {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("$ date")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(context.date, format: .dateTime.hour().minute().second())
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }
                } else if style == .orbit {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.10), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: secondsFraction(context.date))
                            .stroke(
                                ThemeStore.shared.dock.accent,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(8)
                } else if style == .mono {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(context.date, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(ThemeStore.shared.dock.accent)
                    }
                } else if style == .frame {
                    HStack(spacing: 7) {
                        Rectangle()
                            .fill(ThemeStore.shared.dock.accent)
                            .frame(width: 2, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.date, format: .dateTime.hour().minute())
                                .font(.system(size: 19, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text(context.date, format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
            .padding(.horizontal, compact ? 8 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func secondsFraction(_ date: Date) -> CGFloat {
        CGFloat(Calendar.current.component(.second, from: date)) / 60
    }
}
