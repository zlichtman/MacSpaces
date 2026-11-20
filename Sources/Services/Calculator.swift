import Foundation

/// Answers what you type in the Calculator widget: arithmetic ("12*(3+4)",
/// "2^10", "sqrt 2", "15% of 80"), units ("5 km in mi", "350 f to c", "2 gb to mb")
/// and currencies ("100 usd to eur"). Everything but currencies is worked out
/// here; currency rates come from the European Central Bank (frankfurter.app).
enum Calculator {
    enum Answer: Equatable {
        case number(Double)
        case measurement(Double, unit: String)
        /// A currency conversion still needs the day's rate.
        case currency(amount: Double, from: String, to: String)
    }

    static func evaluate(_ input: String) -> Answer? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if let conversion = conversion(text) { return conversion }
        return Expression.evaluate(text).map(Answer.number)
    }

    /// A readable number: grouped digits, up to ten significant places, no trailing zeros.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "Not a number" : (value > 0 ? "∞" : "−∞") }
        if abs(value) >= 1e15 || (abs(value) < 1e-6 && value != 0) {
            return String(format: "%.6g", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumSignificantDigits = 10
        formatter.usesSignificantDigits = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: Conversions

    private static func conversion(_ text: String) -> Answer? {
        // "<amount> <from> to|in|as <to>"
        let pattern = #"^(.+?)\s*([a-z°$€£¥"' ]+?)\s+(?:to|in|as|into)\s+([a-z°$€£¥"' ]+)$"#
        guard let match = (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text),
              let fromRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text),
              let amount = Expression.evaluate(String(text[amountRange])) else { return nil }
        let from = text[fromRange].trimmingCharacters(in: .whitespaces)
        let to = text[toRange].trimmingCharacters(in: .whitespaces)
        if let source = currency(from), let target = currency(to) {
            return .currency(amount: amount, from: source, to: target)
        }
        guard let source = units[from], let target = units[to], type(of: source) == type(of: target) else { return nil }
        let value = Measurement(value: amount, unit: source).converted(to: target).value
        return .measurement(value, unit: target.symbol)
    }

    private static func currency(_ name: String) -> String? {
        let symbols = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "dollars": "USD", "dollar": "USD",
                       "euros": "EUR", "euro": "EUR", "pounds": "GBP", "pound": "GBP", "yen": "JPY"]
        if let code = symbols[name] { return code }
        let code = name.uppercased()
        return currencies.contains(code) ? code : nil
    }

    /// Currencies the ECB publishes rates for.
    static let currencies: Set<String> = ["AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF",
                                          "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN",
                                          "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR"]

    private static let units: [String: Dimension] = {
        var table: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ names: String...) { for name in names { table[name] = unit } }
        add(UnitLength.millimeters, "mm", "millimeter", "millimeters"); add(UnitLength.centimeters, "cm", "centimeter", "centimeters")
        add(UnitLength.meters, "m", "meter", "meters", "metre", "metres"); add(UnitLength.kilometers, "km", "kilometer", "kilometers", "kilometre", "kilometres")
        add(UnitLength.inches, "in", "inch", "inches", "\""); add(UnitLength.feet, "ft", "foot", "feet", "'")
        add(UnitLength.yards, "yd", "yard", "yards"); add(UnitLength.miles, "mi", "mile", "miles")
        add(UnitLength.nauticalMiles, "nmi", "nautical mile", "nautical miles")
        add(UnitMass.grams, "g", "gram", "grams"); add(UnitMass.kilograms, "kg", "kilogram", "kilograms", "kilo", "kilos")
        add(UnitMass.milligrams, "mg", "milligram", "milligrams"); add(UnitMass.ounces, "oz", "ounce", "ounces")
        add(UnitMass.pounds, "lb", "lbs", "pound mass"); add(UnitMass.stones, "st", "stone", "stones")
        add(UnitTemperature.celsius, "c", "°c", "celsius"); add(UnitTemperature.fahrenheit, "f", "°f", "fahrenheit")
        add(UnitTemperature.kelvin, "k", "kelvin")
        add(UnitVolume.milliliters, "ml", "milliliter", "milliliters"); add(UnitVolume.liters, "l", "liter", "liters", "litre", "litres")
        add(UnitVolume.cups, "cup", "cups"); add(UnitVolume.fluidOunces, "fl oz", "floz")
        add(UnitVolume.gallons, "gal", "gallon", "gallons"); add(UnitVolume.tablespoons, "tbsp", "tablespoon", "tablespoons")
        add(UnitVolume.teaspoons, "tsp", "teaspoon", "teaspoons")
        add(UnitSpeed.kilometersPerHour, "kph", "km/h", "kmh"); add(UnitSpeed.milesPerHour, "mph"); add(UnitSpeed.metersPerSecond, "m/s")
        add(UnitSpeed.knots, "knot", "knots", "kn")
        add(UnitDuration.seconds, "s", "sec", "secs", "second", "seconds"); add(UnitDuration.minutes, "min", "mins", "minute", "minutes")
        add(UnitDuration.hours, "h", "hr", "hrs", "hour", "hours")
        add(UnitArea.squareMeters, "m2", "sq m", "square meters"); add(UnitArea.squareFeet, "ft2", "sq ft", "square feet")
        add(UnitArea.acres, "acre", "acres"); add(UnitArea.hectares, "ha", "hectare", "hectares")
        add(UnitArea.squareKilometers, "km2", "sq km"); add(UnitArea.squareMiles, "mi2", "sq mi")
        add(UnitInformationStorage.bytes, "b", "byte", "bytes"); add(UnitInformationStorage.kilobytes, "kb", "kilobyte", "kilobytes")
        add(UnitInformationStorage.megabytes, "mb", "megabyte", "megabytes"); add(UnitInformationStorage.gigabytes, "gb", "gigabyte", "gigabytes")
        add(UnitInformationStorage.terabytes, "tb", "terabyte", "terabytes")
        add(UnitEnergy.kilocalories, "kcal", "calories", "cal"); add(UnitEnergy.kilojoules, "kj", "kilojoule", "kilojoules")
        return table
    }()

    // MARK: Arithmetic

    /// A small recursive-descent parser: + − × ÷ ^ %, parentheses, functions and
    /// constants. Never throws or traps on bad input; it just answers nil.
    enum Expression {
        static func evaluate(_ text: String) -> Double? {
            var normalised = text.lowercased()
                .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: "")
            // "15% of 80" is 15% × 80.
            normalised = normalised.replacingOccurrences(of: "% of", with: "%*")
            var parser = Parser(Array(normalised.filter { !$0.isWhitespace }))
            guard let value = parser.expression(), parser.atEnd, value.isFinite else { return nil }
            return value
        }

        private struct Parser {
            let characters: [Character]
            var index = 0
            init(_ characters: [Character]) { self.characters = characters }
            var atEnd: Bool { index == characters.count }
            var peek: Character? { index < characters.count ? characters[index] : nil }

            mutating func take(_ character: Character) -> Bool {
                guard peek == character else { return false }
                index += 1
                return true
            }

            mutating func expression() -> Double? {
                guard var value = term() else { return nil }
                while let operation = peek, operation == "+" || operation == "-" {
                    index += 1
                    guard let right = term() else { return nil }
                    value = operation == "+" ? value + right : value - right
                }
                return value
            }

            mutating func term() -> Double? {
                guard var value = unary() else { return nil }
                while let operation = peek, operation == "*" || operation == "/" || operation == "x" {
                    // "x" multiplies only between numbers, not as the start of a word.
                    if operation == "x", index + 1 < characters.count, characters[index + 1].isLetter { break }
                    index += 1
                    guard let right = unary() else { return nil }
                    value = operation == "/" ? value / right : value * right
                }
                return value
            }

            /// Unary minus binds looser than ^, so -3^2 is -9.
            mutating func unary() -> Double? {
                if take("-") { return unary().map { -$0 } }
                if take("+") { return unary() }
                return power()
            }

            mutating func power() -> Double? {
                guard let base = postfix() else { return nil }
                if take("^") {
                    guard let exponent = unary() else { return nil }
                    return pow(base, exponent)
                }
                return base
            }

            mutating func postfix() -> Double? {
                guard var value = primary() else { return nil }
                while take("%") { value /= 100 }
                while take("!") {
                    guard value >= 0, value <= 170, value == value.rounded() else { return nil }
                    value = (1...max(1, Int(value))).reduce(1.0) { $0 * Double($1) }
                }
                return value
            }

            mutating func primary() -> Double? {
                if take("(") {
                    guard let value = expression(), take(")") else { return nil }
                    return value
                }
                if let character = peek, character.isNumber || character == "." { return number() }
                if let character = peek, character.isLetter || character == "π" { return word() }
                return nil
            }

            mutating func number() -> Double? {
                let start = index
                while let character = peek, character.isNumber || character == "." { index += 1 }
                if let e = peek, e == "e", index + 1 < characters.count,
                   characters[index + 1].isNumber || characters[index + 1] == "-" || characters[index + 1] == "+" {
                    index += 1
                    if peek == "-" || peek == "+" { index += 1 }
                    while let character = peek, character.isNumber { index += 1 }
                }
                return Double(String(characters[start..<index]))
            }

            mutating func word() -> Double? {
                if take("π") { return .pi }
                let start = index
                while let character = peek, character.isLetter { index += 1 }
                let name = String(characters[start..<index])
                switch name {
                case "pi": return .pi
                case "e": return M_E
                case "tau": return 2 * .pi
                default: break
                }
                let functions: [String: (Double) -> Double] = [
                    "sqrt": { $0.squareRoot() }, "abs": { abs($0) }, "round": { $0.rounded() }, "floor": { $0.rounded(.down) },
                    "ceil": { $0.rounded(.up) }, "ln": { Foundation.log($0) }, "log": { log10($0) }, "exp": { Foundation.exp($0) },
                    "sin": { Foundation.sin($0) }, "cos": { Foundation.cos($0) }, "tan": { Foundation.tan($0) },
                ]
                guard let function = functions[name], let argument = unary() else { return nil }
                return function(argument)
            }
        }
    }
}

/// The day's exchange rates, fetched only when a currency conversion is typed
/// and cached for an hour.
actor CurrencyRates {
    static let shared = CurrencyRates()
    private var cache: [String: (rates: [String: Double], fetched: Date)] = [:]

    func rate(from: String, to: String) async throws -> Double {
        if from == to { return 1 }
        if let cached = cache[from], Date().timeIntervalSince(cached.fetched) < 3600, let rate = cached.rates[to] { return rate }
        var components = URLComponents(string: "https://api.frankfurter.app/latest")!
        components.queryItems = [URLQueryItem(name: "from", value: from)]
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2"
        request.setValue("MacSpaces \(version) (https://github.com/zlichtman/MacSpaces)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Payload: Decodable { let rates: [String: Double] }
        let rates = try JSONDecoder().decode(Payload.self, from: data).rates
        cache[from] = (rates, Date())
        guard let rate = rates[to] else { throw URLError(.cannotParseResponse) }
        return rate
    }
}
