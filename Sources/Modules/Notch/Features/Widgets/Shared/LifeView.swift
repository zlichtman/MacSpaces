import SwiftUI
import AppKit

/// Life in weeks, with a birthday editor that stays entirely inside the Nook.
struct LifeView: View {
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var editing = false
    /// Debug captures: open on the birthday editor.
    var previewEditing = false
    @State private var setupCancelled = false
    @State private var draft = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var draftSpan = LifeProgress.defaultLifespan
    @State private var birthdayYearValid = true
    @State private var visible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Life in weeks")
                .font(.system(size: 12, weight: .bold))
                .frame(height: 20, alignment: .leading)
            if let birthday = options.birthday, !editing {
                if visible {
                    TimelineView(.periodic(from: .now, by: 3600)) { context in
                        life(LifeProgress(birthday: birthday, lifespan: options.lifespan, now: context.date))
                    }
                } else {
                    life(LifeProgress(birthday: birthday, lifespan: options.lifespan))
                }
            } else if editing || !setupCancelled {
                picker(first: options.birthday == nil)
            } else {
                VStack(spacing: 10) {
                    Text("Your life, one week at a time")
                        .font(.system(size: 12, weight: .bold))
                    Button("Set birthday") { beginEditing() }
                        .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(theme.nookForeground)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onAppear { if previewEditing { draft = options.birthday ?? draft; draftSpan = options.lifespan; editing = true } }
    }

    private func life(_ life: LifeProgress) -> some View {
        let percent = Int((life.fraction * 100).rounded(.down))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Age \(life.age)").font(.system(size: 12, weight: .bold))
                Text("\(percent)% of \(life.lifespan)-year span")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.nookForeground.opacity(0.6))
                Spacer(minLength: 8)
                Text("Born \(life.birthday.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.nookForeground.opacity(0.6))
                    .accessibilityLabel("Born \(life.birthday.formatted(date: .long, time: .omitted))")
            }
            .lineLimit(1)
            .padding(.top, 8)
            LifeBar(fraction: life.fraction).padding(.top, 6)
            HStack(alignment: .top, spacing: 20) {
                LifeWeeks(life: life, ink: theme.nookForeground, accent: theme.notch.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                lifeSummary(life).frame(width: 142, alignment: .leading)
            }
            .padding(.top, 12)
        }
    }

    private func lifeSummary(_ life: LifeProgress) -> some View {
        let inSpan = life.weeksLived < life.totalWeeks
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(theme.notch.accent).frame(width: 4, height: 4)
                Text(inSpan ? "This week" : "Span complete")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(theme.notch.accent)
            Text(inSpan ? "Week \(life.lived.weeks + 1) of 52" : "\(life.lifespan) years in view")
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .padding(.top, 4)
            Rectangle().fill(theme.nookForeground.opacity(0.12)).frame(height: 1)
                .padding(.vertical, 10)
            VStack(spacing: 8) {
                count(life.weeksLived, label: "weeks lived")
                count(life.weeksLeft, label: "weeks left")
                count(life.weekendsLeft, label: "weekends left")
                count(life.birthdaysLeft, label: "birthdays left")
            }
            if life.daysToNextBirthday == 0 {
                Text("Birthday today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.notch.accent)
                    .padding(.top, 8)
            }
            Spacer(minLength: 8)
            Button(action: beginEditing) {
                Label("Edit birthday", systemImage: "pencil")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(WidgetChipStyle(height: 22))
            .accessibilityLabel("Edit birthday and lifespan")
        }
        .padding(.bottom, 2)
    }

    private func count(_ count: Int, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(count.formatted())
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
            Spacer(minLength: 0)
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.nookForeground.opacity(0.6))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func beginEditing() {
        draft = options.birthday ?? draft
        draftSpan = options.lifespan
        editing = true
    }

    /// 228 pt including all controls, plus the page's 20 pt title.
    private func picker(first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BirthdayPicker(date: $draft, onYearValidityChange: { birthdayYearValid = $0 })
            lifespanControl
            HStack(spacing: 8) {
                if !first {
                    Button("Remove birthday") {
                        options.birthday = nil
                        editing = false
                        setupCancelled = true
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.nookForeground.opacity(0.6))
                    .buttonStyle(.plain)
                } else {
                    Text("Stored only on this Mac")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.nookForeground.opacity(0.6))
                }
                Spacer(minLength: 4)
                Button("Cancel") {
                    editing = false
                    setupCancelled = true
                }
                .buttonStyle(WidgetChipStyle(height: 26))
                .keyboardShortcut(.cancelAction)
                Button("Done") {
                    options.birthday = draft
                    options.lifespan = draftSpan
                    editing = false
                    setupCancelled = false
                }
                .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
                .disabled(!birthdayYearValid)
                .keyboardShortcut(.defaultAction)
            }
            .frame(height: 26)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if first { draftSpan = options.lifespan } }
    }

    private var lifespanControl: some View {
        HStack(spacing: 6) {
            Text("Lifespan").font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.nookForeground.opacity(0.6))
            ForEach([70, 80, 90, 100], id: \.self) { years in
                Button("\(years)") { draftSpan = years }
                    .buttonStyle(WidgetChipStyle(prominent: draftSpan == years, height: 24))
                    .accessibilityLabel("\(years)-year lifespan")
                    .accessibilityAddTraits(draftSpan == years ? .isSelected : [])
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                adjustButton("minus", label: "Decrease lifespan", enabled: draftSpan > LifeProgress.lifespans.lowerBound) {
                    changeSpan(-1)
                }
                Text("\(draftSpan) years")
                    .font(.system(size: 12, weight: .bold)).monospacedDigit()
                    .frame(width: 66)
                adjustButton("plus", label: "Increase lifespan", enabled: draftSpan < LifeProgress.lifespans.upperBound) {
                    changeSpan(1)
                }
            }
            .background(theme.nookForeground.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .modifier(LifeScrollAdjustment(step: changeSpan))
            .help("Scroll to adjust lifespan")
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Lifespan, \(draftSpan) years")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: changeSpan(1)
                case .decrement: changeSpan(-1)
                @unknown default: break
                }
            }
        }
        .frame(height: 28)
    }

    private func changeSpan(_ amount: Int) {
        draftSpan = min(LifeProgress.lifespans.upperBound, max(LifeProgress.lifespans.lowerBound, draftSpan + amount))
    }

    private func adjustButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .frame(width: 26, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .hoverHighlight()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

/// The Calendar's thin progress bar, using the theme's ink for its track and ticks.
private struct LifeBar: View {
    let fraction: Double
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.nookForeground.opacity(0.1))
                Capsule().fill(theme.notch.accent)
                    .frame(width: min(proxy.size.width, max(0, proxy.size.width * fraction)))
                ForEach([0.25, 0.5, 0.75], id: \.self) { quarter in
                    Rectangle().fill(theme.nookForeground.opacity(0.22))
                        .frame(width: 1, height: 7).offset(x: proxy.size.width * quarter)
                }
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel("Life progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

/// Every row is one year of 52 weeks. Two banks keep the dots legible inside a
/// short panel; both end at decade boundaries, except the final partial decade.
private struct LifeWeeks: View {
    let life: LifeProgress
    let ink: Color
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let decades = (life.lifespan + 9) / 10
            let split = ((decades + 1) / 2) * 10
            let rows = max(split, life.lifespan - split)
            let bankGap: CGFloat = 14
            let gutter: CGFloat = 19
            let bankWidth = max(1, (size.width - bankGap) / 2)
            let xPitch = max(0.1, (bankWidth - gutter - 4) / 51)
            let top: CGFloat = 20
            let available = max(1, size.height - top - 3)
            let decadeGap = min(5, available / CGFloat(rows) * 1.2)
            let yPitch = max(0.1, (available - CGFloat((rows - 1) / 10) * decadeGap) / CGFloat(rows))
            let diameter = max(0.5, min(2.5, min(xPitch * 0.67, yPitch * 0.72)))
            var passed = Path()
            var ahead = Path()
            var current: CGPoint?

            for bank in 0..<2 {
                let origin = CGFloat(bank) * (bankWidth + bankGap)
                context.draw(Text("Age").font(.system(size: 8, weight: .medium))
                    .foregroundColor(ink.opacity(0.45)),
                    at: CGPoint(x: origin, y: 5), anchor: .leading)
                context.draw(Text("Weeks 1–52").font(.system(size: 8, weight: .medium))
                    .foregroundColor(ink.opacity(0.45)),
                    at: CGPoint(x: origin + gutter, y: 5), anchor: .leading)
                let startYear = bank == 0 ? 0 : split
                let endYear = min(startYear + split, life.lifespan)
                for year in startYear..<endYear {
                    let row = year - startYear
                    let y = top + CGFloat(row) * yPitch + CGFloat(row / 10) * decadeGap + yPitch / 2
                    if row % 10 == 0 {
                        context.draw(Text("\(year)").font(.system(size: 9, weight: .medium)).monospacedDigit()
                            .foregroundColor(ink.opacity(0.55)),
                            at: CGPoint(x: origin + gutter - 7, y: y), anchor: .trailing)
                    }
                    for week in 0..<LifeProgress.weeksPerYear {
                        let index = year * LifeProgress.weeksPerYear + week
                        let point = CGPoint(x: origin + gutter + CGFloat(week) * xPitch, y: y)
                        let dot = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                         width: diameter, height: diameter)
                        if index < life.weeksLived { passed.addEllipse(in: dot) }
                        else if index == life.weeksLived { current = point }
                        else { ahead.addEllipse(in: dot) }
                    }
                }
            }
            context.fill(ahead, with: .color(ink.opacity(0.18)))
            context.fill(passed, with: .color(ink.opacity(0.75)))
            if let current {
                let radius = diameter * 0.66
                let dot = CGRect(x: current.x - radius, y: current.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: dot.insetBy(dx: -1.8, dy: -1.8)), with: .color(accent.opacity(0.18)))
                context.stroke(Path(ellipseIn: dot.insetBy(dx: -1.2, dy: -1.2)), with: .color(accent), lineWidth: 0.7)
                context.fill(Path(ellipseIn: dot), with: .color(accent))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Life in weeks. Each row is one year, grouped by decade. Read down the left block, then the right.")
        .accessibilityValue("\(life.weeksLived.formatted()) weeks lived, \(life.weeksLeft.formatted()) weeks left. "
            + (life.weeksLived < life.totalWeeks ? "This week is highlighted." : "The chosen span is complete."))
    }
}

/// Month buttons and a real month calendar; the year accepts typing, arrows and
/// scrolling. Dates are clamped to valid days, including leap years, and today.
struct BirthdayPicker: View {
    @Binding var date: Date
    var onYearValidityChange: ((Bool) -> Void)? = nil
    @ObservedObject private var theme = ThemeStore.shared
    @State private var yearText = ""
    @FocusState private var yearFocused: Bool
    private let calendar = Calendar.current

    private var parts: DateComponents { calendar.dateComponents([.year, .month, .day], from: date) }
    private var currentYear: Int { calendar.component(.year, from: Date()) }
    private var monthStart: Date {
        calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)) ?? date
    }
    private var daysInMonth: Int { calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31 }
    private var leadingDays: Int { (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7 }
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Birthday").font(.system(size: 12, weight: .bold))
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.nookForeground.opacity(0.6))
                Spacer(minLength: 4)
                Text("Year").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.nookForeground.opacity(0.6))
                yearControl
            }
            .frame(height: 26)
            HStack(alignment: .top, spacing: 20) {
                months.frame(maxWidth: .infinity)
                days.frame(maxWidth: .infinity)
            }
            .frame(height: 126, alignment: .top)
        }
        .onAppear { syncYear(); reportYearValidity() }
        .onChange(of: date) { _ in syncYear() }
        .onChange(of: yearFocused) { focused in if !focused { commitYear() } }
    }

    private var yearControl: some View {
        HStack(spacing: 0) {
            yearArrow("chevron.left", amount: -1, enabled: (parts.year ?? 1900) > 1900)
            TextField("Year", text: $yearText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(width: 46)
                .focused($yearFocused)
                .accessibilityLabel("Birthday year")
                .onSubmit { commitYear(); yearFocused = false }
                .onChange(of: yearText) { value in
                    let digits = String(value.filter(\.isNumber).prefix(4))
                    if digits != value { yearText = digits }
                    if digits.count == 4, let year = Int(digits), (1900...currentYear).contains(year) {
                        update(year: year)
                    }
                    reportYearValidity()
                }
            yearArrow("chevron.right", amount: 1, enabled: (parts.year ?? currentYear) < currentYear)
        }
        .frame(height: 26)
        .background(theme.nookForeground.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(theme.notch.accent.opacity(yearFocused ? 0.7 : 0), lineWidth: 1)
        }
        .modifier(LifeScrollAdjustment { amount in changeYear(amount) })
        .help("Type a year or scroll to adjust")
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: changeYear(1)
            case .decrement: changeYear(-1)
            @unknown default: break
            }
        }
    }

    private var months: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Month").font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.nookForeground.opacity(0.6))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(1...12, id: \.self) { month in
                    let selected = month == parts.month
                    let enabled = (parts.year ?? currentYear) < currentYear || month <= calendar.component(.month, from: Date())
                    Button { yearFocused = false; update(month: month) } label: {
                        Text(calendar.shortMonthSymbols[month - 1])
                            .font(.system(size: 11, weight: selected ? .bold : .medium))
                            .frame(maxWidth: .infinity).frame(height: 28)
                            .background(selected ? theme.notch.accent.opacity(0.2) : theme.nookForeground.opacity(0.045),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(selected ? theme.notch.accent.opacity(0.65) : .clear, lineWidth: 1)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled).opacity(enabled ? 1 : 0.3)
                    .accessibilityLabel(calendar.monthSymbols[month - 1])
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var days: some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.nookForeground.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 12)
            // Six fixed rows avoid a layout jump when the month or year changes.
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        dayCell(row * 7 + column - leadingDays + 1)
                    }
                }
                .frame(height: 18)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        if (1...daysInMonth).contains(day) {
            let selected = day == parts.day
            let candidate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? date
            let enabled = calendar.startOfDay(for: candidate) <= calendar.startOfDay(for: Date())
            Button { yearFocused = false; update(day: day) } label: {
                Text("\(day)")
                    .font(.system(size: 11, weight: selected ? .bold : .medium)).monospacedDigit()
                    .frame(width: 23, height: 18)
                    .background(selected ? theme.notch.accent.opacity(0.25) : .clear, in: Capsule())
                    .overlay { Capsule().strokeBorder(selected ? theme.notch.accent : .clear, lineWidth: 0.7) }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled).opacity(enabled ? 1 : 0.25)
            .accessibilityLabel(candidate.formatted(date: .complete, time: .omitted))
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 18).accessibilityHidden(true)
        }
    }

    private func yearArrow(_ symbol: String, amount: Int, enabled: Bool) -> some View {
        Button { changeYear(amount) } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .frame(width: 24, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .hoverHighlight()
        .disabled(!enabled).opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(amount > 0 ? "Next year" : "Previous year")
    }

    private func syncYear() { yearText = String(parts.year ?? 2000) }

    private func reportYearValidity() {
        let valid = yearText.count == 4 && (1900...currentYear).contains(Int(yearText) ?? 0)
        onYearValidityChange?(valid)
    }

    private func commitYear() {
        if let year = Int(yearText) { update(year: min(currentYear, max(1900, year))) }
        syncYear()
    }

    private func changeYear(_ amount: Int) {
        update(year: min(currentYear, max(1900, (parts.year ?? 2000) + amount)))
        syncYear()
    }

    private func update(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        var next = parts
        if let year { next.year = year }
        if let month { next.month = month }
        if let day { next.day = day }
        var first = next; first.day = 1
        if let start = calendar.date(from: first), let range = calendar.range(of: .day, in: .month, for: start) {
            next.day = min(max(next.day ?? 1, 1), range.count)
        }
        next.hour = 12
        guard let result = calendar.date(from: next) else { return }
        let clamped = min(result, Date())
        if date != clamped { date = clamped }
    }
}

/// Install the local monitor only during hover and remove it on disappearance.
/// The text field stays native and editable; scroll events elsewhere pass through.
private struct LifeScrollAdjustment: ViewModifier {
    let step: (Int) -> Void
    @State private var input = LifeScrollInput()

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside { input.start(step: step) } else { input.stop() }
            }
            .onDisappear { input.stop() }
    }
}

private final class LifeScrollInput {
    private var monitor: Any?
    private var accumulated: CGFloat = 0

    func start(step: @escaping (Int) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            // Ignore inertial tails so a year doesn't drift after fingers lift.
            guard event.momentumPhase.isEmpty else { return nil }
            if event.phase == .began { self.accumulated = 0 }
            let delta = event.scrollingDeltaY
            if delta == 0 { return event }
            if event.hasPreciseScrollingDeltas {
                self.accumulated += delta
                let steps = Int(self.accumulated / 12)
                if steps != 0 {
                    self.accumulated -= CGFloat(steps) * 12
                    step(steps)
                }
            } else {
                step(delta > 0 ? 1 : -1)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        accumulated = 0
    }

    deinit { stop() }
}
