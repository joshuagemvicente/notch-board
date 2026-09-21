import Foundation

/// Thin POST-to-GraphQL helper for the GitHub API.
struct GraphQLClient: Sendable {
    let token: String
    let session: URLSession

    private let endpoint = URL(string: "https://api.github.com/graphql")!

    func query<Response: Decodable>(_ query: String, variables: [String: Any] = [:]) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                throw ProviderError.invalidToken("bad or expired token")
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw ProviderError.server("HTTP \(http.statusCode)")
            }
            let envelope = try JSONDecoder().decode(GraphQLResponse<Response>.self, from: data)
            if let message = envelope.errors?.first?.message {
                throw ProviderError.server(message)
            }
            guard let payload = envelope.data else {
                throw ProviderError.server("empty GraphQL response")
            }
            return payload
        } catch let error as ProviderError {
            throw error
        } catch let error as DecodingError {
            throw ProviderError.server("Failed to decode GitHub response: \(error)")
        } catch {
            throw ProviderError.network(error)
        }
    }
}