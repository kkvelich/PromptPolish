import Foundation

enum AnthropicModel: String, CaseIterable, Identifiable {
    case sonnet46 = "claude-sonnet-4-6"
    case haiku45 = "claude-haiku-4-5"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .sonnet46: return "Sonnet 4.6 (recommended)"
        case .haiku45: return "Haiku 4.5 (cheaper, no cache)"
        }
    }
}

struct PolishResult {
    let text: String
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let inputTokens: Int
    let outputTokens: Int
}

enum AnthropicError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int, String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No API key set. Open the host app to add one."
        case .invalidResponse: return "Invalid response from Claude."
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .decodingError(let detail): return "Decoding error: \(detail)"
        }
    }
}

actor AnthropicClient {
    static let shared = AnthropicClient()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func polish(_ rawText: String, model: AnthropicModel) async throws -> PolishResult {
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            throw AnthropicError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 1024,
            "temperature": 0.3,
            "system": [
                [
                    "type": "text",
                    "text": SystemPrompt.text,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": [
                ["role": "user", "content": rawText]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AnthropicError.httpError(http.statusCode, bodyString)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicError.decodingError("not a JSON object")
        }

        guard let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AnthropicError.decodingError("missing content[0].text")
        }

        let usage = json["usage"] as? [String: Any] ?? [:]
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0

        return PolishResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreate,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
