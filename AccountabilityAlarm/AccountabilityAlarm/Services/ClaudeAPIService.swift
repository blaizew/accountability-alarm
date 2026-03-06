import Foundation

final class ClaudeAPIService {
    static let shared = ClaudeAPIService()

    private init() {}

    struct APIMessage: Codable, Sendable {
        let role: String
        let content: String
    }

    struct APIRequest: Codable, Sendable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [APIMessage]
    }

    struct APIResponse: Codable, Sendable {
        let content: [ContentBlock]

        struct ContentBlock: Codable, Sendable {
            let type: String
            let text: String?
        }
    }

    struct APIError: Codable, Sendable {
        let error: ErrorDetail

        struct ErrorDetail: Codable, Sendable {
            let message: String
        }
    }

    func sendMessage(
        systemPrompt: String,
        messages: [ConversationMessage]
    ) async throws -> String {
        guard let url = URL(string: Constants.apiEndpoint) else {
            throw ClaudeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Constants.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(APIKeys.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 30

        let apiMessages = messages.map { msg in
            APIMessage(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.content
            )
        }

        let apiRequest = APIRequest(
            model: Constants.apiModel,
            max_tokens: 256,
            system: systemPrompt,
            messages: apiMessages
        )

        request.httpBody = try JSONEncoder().encode(apiRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw ClaudeError.apiError(apiError.error.message)
            }
            throw ClaudeError.httpError(httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let text = apiResponse.content.first?.text else {
            throw ClaudeError.emptyResponse
        }

        return text
    }

    enum ClaudeError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(Int)
        case apiError(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid API URL"
            case .invalidResponse: "Invalid response from server"
            case .httpError(let code): "HTTP error: \(code)"
            case .apiError(let msg): "API error: \(msg)"
            case .emptyResponse: "Empty response from AI"
            }
        }
    }
}
