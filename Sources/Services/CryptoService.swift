import Foundation

struct CryptoQuote: Identifiable, Equatable {
    let id: String
    let symbol: String
    let price: Double
    let change24Hours: Double
}

/// Lightweight public market snapshot via CoinGecko. No account, API key, or
/// user data is involved.
@MainActor
final class CryptoService: ObservableObject {
    @Published private(set) var quotes: [CryptoQuote] = []
    @Published private(set) var errorText: String?

    private var started = false
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    /// Shared session with a bounded timeout so a stalled request cannot hang
    /// past the 90-second refresh cadence.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    func startIfNeeded() {
        guard !started else { return }
        started = true
        scheduleRefresh()
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
    }

    func stop() {
        started = false
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func scheduleRefresh() {
        guard started else { return }
        refreshTask?.cancel()
        refreshTask = Task { await refresh() }
    }

    func refresh() async {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd&include_24hr_change=true") else {
            return
        }

        struct Price: Decodable {
            let usd: Double
            let usd_24h_change: Double?
        }

        do {
            let (data, response) = try await Self.session.data(from: url)
            guard started, !Task.isCancelled else { return }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let values = try JSONDecoder().decode([String: Price].self, from: data)
            let definitions = [("bitcoin", "BTC"), ("ethereum", "ETH"), ("solana", "SOL")]
            quotes = definitions.compactMap { id, symbol in
                guard let value = values[id] else { return nil }
                return CryptoQuote(
                    id: id,
                    symbol: symbol,
                    price: value.usd,
                    change24Hours: value.usd_24h_change ?? 0
                )
            }
            errorText = nil
        } catch {
            guard started, !Task.isCancelled else { return }
            errorText = "Prices unavailable"
        }
    }

    deinit {
        timer?.invalidate()
        refreshTask?.cancel()
    }
}
