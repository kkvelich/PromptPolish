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

enum PolishEvent: Equatable {
    case chunk(String)
    case done(PolishResult)
}

extension PolishResult: Equatable {
    static func == (lhs: PolishResult, rhs: PolishResult) -> Bool {
        lhs.text == rhs.text
            && lhs.cacheReadTokens == rhs.cacheReadTokens
            && lhs.cacheCreationTokens == rhs.cacheCreationTokens
            && lhs.inputTokens == rhs.inputTokens
            && lhs.outputTokens == rhs.outputTokens
    }
}

/// Stateful SSE parser for Anthropic streaming responses.
/// Exposed for unit testing of the parsing logic without network I/O.
final class StreamingResponseParser {
    private(set) var accumulatedText = ""
    private(set) var cacheReadTokens = 0
    private(set) var cacheCreationTokens = 0
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0

    /// Process one line from the SSE stream. Returns a PolishEvent if the line produced one,
    /// or nil for lines that update internal state silently (message_start, message_delta, pings, etc.).
    func handle(line: String) -> PolishEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let jsonString = String(line.dropFirst(6))
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }

        switch type {
        case "message_start":
            if let message = json["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any] {
                cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
                cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
                inputTokens = usage["input_tokens"] as? Int ?? 0
                outputTokens = usage["output_tokens"] as? Int ?? 0
            }
            return nil

        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any],
               (delta["type"] as? String) == "text_delta",
               let text = delta["text"] as? String {
                accumulatedText += text
                return .chunk(text)
            }
            return nil

        case "message_delta":
            if let usage = json["usage"] as? [String: Any],
               let out = usage["output_tokens"] as? Int {
                outputTokens = out
            }
            return nil

        case "message_stop":
            return .done(PolishResult(
                text: accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines),
                cacheReadTokens: cacheReadTokens,
                cacheCreationTokens: cacheCreationTokens,
                inputTokens: inputTokens,
                outputTokens: outputTokens
            ))

        default:
            return nil
        }
    }
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

final class AnthropicClient {
    static let shared = AnthropicClient()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Non-streaming (used by keyboard extension)

    func polish(
        _ rawText: String,
        model: AnthropicModel,
        settings: AppSettings = .shared,
        now: Date = Date()
    ) async throws -> PolishResult {
        let request = try buildRequest(rawText: rawText, model: model, stream: false, settings: settings, now: now)
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
        return PolishResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0
        )
    }

    // MARK: - Streaming (used by host app)

    func polishStream(
        _ rawText: String,
        model: AnthropicModel,
        settings: AppSettings = .shared,
        now: Date = Date()
    ) -> AsyncThrowingStream<PolishEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(rawText: rawText, model: model, stream: true, settings: settings, now: now)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw AnthropicError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line + "\n"
                            if errorBody.count > 2000 { break }
                        }
                        throw AnthropicError.httpError(http.statusCode, errorBody)
                    }

                    let parser = StreamingResponseParser()
                    for try await line in bytes.lines {
                        if let event = parser.handle(line: line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Shared request builder

    private func buildRequest(
        rawText: String,
        model: AnthropicModel,
        stream: Bool,
        settings: AppSettings,
        now: Date
    ) throws -> URLRequest {
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            throw AnthropicError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // System is split into:
        //   [0] cached base — large, identical across calls, marked cache_control: ephemeral
        //   [1] variable suffix — per-call (style, target, language, personal facts, current date)
        let variableSuffix = SystemPrompt.variableSuffix(
            style: settings.polishStyle,
            targetPlatform: settings.targetPlatform,
            outputLanguageName: settings.resolvedOutputLanguageName,
            personalFacts: settings.personalFacts,
            now: now
        )

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 1024,
            "temperature": 0.3,
            "system": [
                [
                    "type": "text",
                    "text": SystemPrompt.cachedBase,
                    "cache_control": ["type": "ephemeral"]
                ],
                [
                    "type": "text",
                    "text": variableSuffix
                ]
            ],
            "messages": [
                ["role": "user", "content": rawText]
            ]
        ]
        if stream {
            body["stream"] = true
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
