import Foundation

/// Anthropic Messages API client with tool-use support.
///
/// The model is given a small toolbox (mark_complied, snooze_alarm,
/// mark_overridden, escalate_ring) and decides which one to call based
/// on the conversation. No client-side intent regex.
final class ClaudeAPIService {
    static let shared = ClaudeAPIService()
    private init() {}

    // MARK: - Public response shape

    struct Response: Sendable {
        let text: String
        let toolUses: [ToolUse]
        let stopReason: String?
    }

    struct ToolUse: Sendable {
        let id: String
        let name: String
        let input: JSONValue
    }

    // MARK: - Send

    func sendMessage(
        systemPrompt: String,
        messages: [APIMessage],
        tools: [Tool]
    ) async throws -> Response {
        guard let url = URL(string: Constants.apiEndpoint) else {
            throw ClaudeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Constants.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(APIKeys.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 30

        let apiRequest = APIRequest(
            model: Constants.apiModel,
            max_tokens: 512,
            system: systemPrompt,
            tools: tools.isEmpty ? nil : tools,
            messages: messages
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(apiRequest)

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

        var text = ""
        var toolUses: [ToolUse] = []
        for block in apiResponse.content {
            switch block.type {
            case "text":
                if let t = block.text { text += t }
            case "tool_use":
                if let id = block.id, let name = block.name, let input = block.input {
                    toolUses.append(ToolUse(id: id, name: name, input: input))
                }
            default:
                break
            }
        }

        return Response(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            toolUses: toolUses,
            stopReason: apiResponse.stop_reason
        )
    }

    // MARK: - Request types

    struct APIRequest: Codable, Sendable {
        let model: String
        let max_tokens: Int
        let system: String
        let tools: [Tool]?
        let messages: [APIMessage]
    }

    /// One message in the conversation. Content can be a plain string OR a list
    /// of content blocks (text, tool_use, tool_result).
    struct APIMessage: Codable, Sendable {
        let role: String
        let content: MessageContent

        init(role: String, text: String) {
            self.role = role
            self.content = .text(text)
        }
        init(role: String, blocks: [ContentBlock]) {
            self.role = role
            self.content = .blocks(blocks)
        }
    }

    enum MessageContent: Codable, Sendable {
        case text(String)
        case blocks([ContentBlock])

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .text(let s):    try c.encode(s)
            case .blocks(let bs): try c.encode(bs)
            }
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .text(s) }
            else { self = .blocks(try c.decode([ContentBlock].self)) }
        }
    }

    /// A single content block. Anthropic uses a discriminator `type` field with
    /// per-type fields. Encoding writes only the fields that apply.
    struct ContentBlock: Codable, Sendable {
        let type: String
        var text: String? = nil
        var id: String? = nil
        var name: String? = nil
        var input: JSONValue? = nil
        var tool_use_id: String? = nil
        var content: String? = nil
        var is_error: Bool? = nil

        static func text(_ s: String) -> ContentBlock {
            ContentBlock(type: "text", text: s)
        }
        static func toolUse(id: String, name: String, input: JSONValue) -> ContentBlock {
            ContentBlock(type: "tool_use", id: id, name: name, input: input)
        }
        static func toolResult(id: String, content: String, isError: Bool = false) -> ContentBlock {
            ContentBlock(type: "tool_result", tool_use_id: id, content: content, is_error: isError)
        }
    }

    struct Tool: Codable, Sendable {
        let name: String
        let description: String
        let input_schema: JSONValue
    }

    // MARK: - Response types

    struct APIResponse: Codable, Sendable {
        let content: [ContentBlock]
        let stop_reason: String?
    }

    struct APIError: Codable, Sendable {
        let error: ErrorDetail
        struct ErrorDetail: Codable, Sendable { let message: String }
    }

    // MARK: - Errors

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

// MARK: - JSONValue (small JSON sum type)

enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)    { self = .int(v);    return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.typeMismatch(JSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:        try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v):  try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    // Typed accessors
    var string: String? { if case .string(let v) = self { return v } else { return nil } }
    var int: Int?       { if case .int(let v)    = self { return v } else if case .double(let d) = self { return Int(d) } else { return nil } }
    var bool: Bool?     { if case .bool(let v)   = self { return v } else { return nil } }
    subscript(_ key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }
}
