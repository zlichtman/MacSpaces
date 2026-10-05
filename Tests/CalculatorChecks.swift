import Foundation

@main
enum CalculatorChecks {
    static func number(_ input: String) -> Double? {
        if case .number(let value)? = Calculator.evaluate(input) { return value }
        return nil
    }

    static func close(_ a: Double?, _ b: Double, _ label: String) {
        guard let a, abs(a - b) < 1e-6 * max(1, abs(b)) else { preconditionFailure("\(label): got \(String(describing: a)), wanted \(b)") }
    }

    static func main() {
        close(number("2+3*4"), 14, "precedence")
        close(number("(2+3)*4"), 20, "parentheses")
        close(number("2^10"), 1024, "power")
        close(number("2^3^2"), 512, "power is right-associative")
        close(number("-3^2"), -9, "unary minus")
        close(number("15% of 80"), 12, "percent of")
        close(number("50%"), 0.5, "percent")
        close(number("sqrt 16 + 1"), 5, "function")
        close(number("5!"), 120, "factorial")
        close(number("1,234.5 * 2"), 2469, "grouping commas")
        close(number("3 × 4 ÷ 2 − 1"), 5, "typographic operators")
        close(number("2x3"), 6, "x multiplies")
        close(number("1e3 + 1"), 1001, "exponent notation")
        close(number("pi"), .pi, "constant")
        for bad in ["2+", "((1)", "abc", "1/0", "", "sqrt", "2..3", "171!"] {
            precondition(number(bad) == nil, "\(bad) is not an answer")
        }
        if case .measurement(let value, let unit)? = Calculator.evaluate("5 km in mi") {
            close(value, 3.1068559612, "km to mi"); precondition(unit == "mi")
        } else { preconditionFailure("km to mi") }
        if case .measurement(let value, _)? = Calculator.evaluate("212 f to c") { close(value, 100, "f to c") } else { preconditionFailure("f to c") }
        if case .measurement(let value, _)? = Calculator.evaluate("2 gb to mb") { close(value, 2000, "gb to mb") } else { preconditionFailure("gb") }
        if case .measurement(let value, _)? = Calculator.evaluate("3 in to cm") { close(value, 7.62, "in to cm") } else { preconditionFailure("in") }
        precondition(Calculator.evaluate("5 km in kg") == nil, "units of different kinds don't convert")
        precondition(Calculator.evaluate("100 usd to eur") == .currency(amount: 100, from: "USD", to: "EUR"))
        precondition(Calculator.evaluate("20 € in £") == .currency(amount: 20, from: "EUR", to: "GBP"))
        precondition(Calculator.format(1234567.891) == "1,234,567.891" && Calculator.format(0.1 + 0.2) == "0.3")
        print("Calculator checks passed: arithmetic, precedence, percent, functions, factorial, bad input, units and currencies")
    }
}
