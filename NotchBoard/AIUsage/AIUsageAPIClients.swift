import Foundation

enum AIUsageAPIError: LocalizedError {
    case unauthorized
    case http(Int, String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Key rejected — an organization Admin key is required."
        case .http(let status, let message):
            if let message, !message.isEmpty { return "HTTP \(status): \(message)" }
            return "HTTP \(status)"
        case .decoding:
            return "Unexpected response from the cost endpoint."
        }
    }
}

/// One day of billed cost (bucket start is UTC midnight).
struct AIDailyCost: Equatable, Sendable {
    var start: Date
    var costUSD: Double
}

/// Daily billed cost from a provider's organization cost endpoint.
protocol AIUsageCostClient: Sendable {
    func dailyCosts(since: Date, adminKey: String) async throws -> [AIDailyCost]
}

// MARK: - Anthropic (GET /v1/organizations/cost_report)

struct AnthropicCostClient: AIUsageCostClient {
    var session: URLSession = .shared
    var baseURL = URL(string: "https://api.anthropic.com")!

    private struct Page: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable {
                /// Decimal string in **cents** (e.g. "123.45" = $1.2345).
                var amount: String?
                var currency: String?
            }
            var starting_at: String
            var results: [Result]
        }
        var data: [Bucket]
        var has_more: Bool?
        var next_page: String?
    }

    func dailyCosts(since: Date, adminKey: String) async throws -> [AIDailyCost] {
        var buckets: [AIDailyCost] = []
        var page: String?
        repeat {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("v1/organizations/cost_report"),
                resolvingAgainstBaseURL: false
            )!
            var items = [
                URLQueryItem(name: "starting_at", value: AIUsageAPIDates.rfc3339(AIUsageAPIDates.utcStartOfDay(since))),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "31"),
            ]
            if let page { items.append(URLQueryItem(name: "page", value: page)) }
            components.queryItems = items

            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 20
            request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let data = try await AIUsageHTTP.send(request, session: session)
            guard let decoded = try? JSONDecoder().decode(Page.self, from: data) else {
                throw AIUsageAPIError.decoding
            }
            for bucket in decoded.data {
                guard let start = AIUsageLogParsers.parseISODate(bucket.starting_at) else { continue }
                let cents = bucket.results
                    .filter { ($0.currency ?? "USD").uppercased() == "USD" }
                    .compactMap { $0.amount.flatMap { Double($0) } }
                    .reduce(0, +)
                buckets.append(AIDailyCost(start: start, costUSD: cents / 100))
            }
            page = decoded.has_more == true ? decoded.next_page : nil
        } while page != nil
        return buckets
    }
}

// MARK: - OpenAI (GET /v1/organization/costs)

struct OpenAICostClient: AIUsageCostClient {
    var session: URLSession = .shared
    var baseURL = URL(string: "https://api.openai.com")!

    private struct Page: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable {
                struct Amount: Decodable {
                    var value: Double?
                    var currency: String?
                }
                var amount: Amount?
            }
            var start_time: TimeInterval
            var results: [Result]
        }
        var data: [Bucket]
        var has_more: Bool?
        var next_page: String?
    }

    func dailyCosts(since: Date, adminKey: String) async throws -> [AIDailyCost] {
        var buckets: [AIDailyCost] = []
        var page: String?
        repeat {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("v1/organization/costs"),
                resolvingAgainstBaseURL: false
            )!
            var items = [
                URLQueryItem(name: "start_time", value: String(Int(AIUsageAPIDates.utcStartOfDay(since).timeIntervalSince1970))),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "31"),
            ]
            if let page { items.append(URLQueryItem(name: "page", value: page)) }
            components.queryItems = items

            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 20
            request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")

            let data = try await AIUsageHTTP.send(request, session: session)
            guard let decoded = try? JSONDecoder().decode(Page.self, from: data) else {
                throw AIUsageAPIError.decoding
            }
            for bucket in decoded.data {
                let usd = bucket.results
                    .compactMap(\.amount)
                    .filter { ($0.currency ?? "usd").lowercased() == "usd" }
                    .compactMap(\.value)
                    .reduce(0, +)
                buckets.append(AIDailyCost(start: Date(timeIntervalSince1970: bucket.start_time), costUSD: usd))
            }
            page = decoded.has_more == true ? decoded.next_page : nil
        } while page != nil
        return buckets
    }
}

// MARK: - Shared

enum AIUsageHTTP {
    static func send(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 401, 403:
            throw AIUsageAPIError.unauthorized
        default:
            throw AIUsageAPIError.http(status, errorMessage(from: data))
        }
    }

    /// Both providers return `{"error": {"message": "..."}}`.
    private static func errorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { var message: String? }
            var error: Inner?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
    }
}

enum AIUsageAPIDates {
    static func utcStartOfDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: date)
    }

    static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
