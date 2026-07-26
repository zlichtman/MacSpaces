import SwiftUI

/// Unit and currency converter. Units convert offline via Foundation's
/// Measurement API; currency rates come from the free frankfurter.app API.
struct ConverterWidget: View {
    @StateObject private var model = ConverterModel()

    var body: some View {
        VStack(spacing: 5) {
            Picker("", selection: $model.category) {
                ForEach(ConverterModel.Category.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)

            HStack(spacing: 5) {
                TextField("0", text: $model.inputText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 58)

                Picker("", selection: $model.fromUnit) {
                    ForEach(model.unitOptions, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 52)

                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)

                Picker("", selection: $model.toUnit) {
                    ForEach(model.unitOptions, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 52)
            }

            Text(model.resultText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class ConverterModel: ObservableObject {
    enum Category: String, CaseIterable, Identifiable {
        case length, mass, temperature, currency

        var id: String { rawValue }

        var title: String {
            switch self {
            case .length: return "Len"
            case .mass: return "Mass"
            case .temperature: return "Temp"
            case .currency: return "$"
            }
        }
    }

    @Published var category: Category = .length {
        didSet { resetUnitsForCategory() }
    }
    @Published var inputText = "1"
    @Published var fromUnit = "m"
    @Published var toUnit = "ft"

    /// currency code -> rate relative to EUR (frankfurter's base).
    @Published private(set) var currencyRates: [String: Double] = [:]
    private var ratesFetched = false

    private static let lengthUnits: [String: UnitLength] = [
        "m": .meters, "km": .kilometers, "cm": .centimeters,
        "ft": .feet, "in": .inches, "mi": .miles,
    ]
    private static let massUnits: [String: UnitMass] = [
        "kg": .kilograms, "g": .grams, "lb": .pounds, "oz": .ounces,
    ]
    private static let temperatureUnits: [String: UnitTemperature] = [
        "°C": .celsius, "°F": .fahrenheit, "K": .kelvin,
    ]
    private static let currencyCodes = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "CNY"]

    var unitOptions: [String] {
        switch category {
        case .length: return Array(Self.lengthUnits.keys).sorted()
        case .mass: return Array(Self.massUnits.keys).sorted()
        case .temperature: return Array(Self.temperatureUnits.keys).sorted()
        case .currency: return Self.currencyCodes
        }
    }

    var resultText: String {
        guard let value = Double(inputText.replacingOccurrences(of: ",", with: ".")) else {
            return "—"
        }

        switch category {
        case .length:
            return convert(value, Self.lengthUnits)
        case .mass:
            return convert(value, Self.massUnits)
        case .temperature:
            return convert(value, Self.temperatureUnits)
        case .currency:
            fetchRatesIfNeeded()
            guard let fromRate = rate(for: fromUnit), let toRate = rate(for: toUnit) else {
                return "loading rates…"
            }
            let converted = value / fromRate * toRate
            return String(format: "%.2f %@", converted, toUnit)
        }
    }

    private func convert<U: Dimension>(_ value: Double, _ units: [String: U]) -> String {
        guard let from = units[fromUnit], let to = units[toUnit] else { return "—" }
        let converted = Measurement(value: value, unit: from).converted(to: to).value
        return String(format: "%.4g %@", converted, toUnit)
    }

    private func rate(for code: String) -> Double? {
        code == "EUR" ? 1.0 : currencyRates[code]
    }

    private func resetUnitsForCategory() {
        let options = unitOptions
        fromUnit = options.first ?? ""
        toUnit = options.count > 1 ? options[1] : options.first ?? ""
    }

    private func fetchRatesIfNeeded() {
        guard !ratesFetched else { return }
        ratesFetched = true

        Task {
            struct Response: Decodable {
                let rates: [String: Double]
            }
            guard let url = URL(string: "https://api.frankfurter.app/latest"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let response = try? JSONDecoder().decode(Response.self, from: data) else {
                // Allow a retry on the next conversion attempt.
                ratesFetched = false
                return
            }
            currencyRates = response.rates
        }
    }
}
