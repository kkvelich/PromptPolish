import Foundation
import Observation

/// User-configurable settings for PromptPolish.
/// Persisted to App Group UserDefaults so the host app and keyboard extension see the same values.
/// Marked @Observable so SwiftUI views re-render automatically when settings change.

enum PolishStyle: String, CaseIterable, Identifiable {
    case compact
    case standard
    case detailed

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .detailed: return "Detailed"
        }
    }

    var description: String {
        switch self {
        case .compact: return "Short, conversational. Best for quick questions."
        case .standard: return "Balanced structure. Good default for most prompts."
        case .detailed: return "Full structure with sections. Best for complex asks."
        }
    }
}

enum TargetPlatform: String, CaseIterable, Identifiable {
    case claude
    case chatgpt
    case gemini
    case grok
    case generic

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .generic: return "Generic"
        }
    }

    /// Guidance the system prompt uses to tailor output for this platform.
    var styleHint: String {
        switch self {
        case .claude:
            return "Claude responds well to conversational framing with clear context. Prefer prose-first prompts with structured sections only when needed. Claude handles nuance and ambiguity well."
        case .chatgpt:
            return "ChatGPT prefers explicit numbered steps and clear constraints. Lead with the task, then provide context. Be specific about output format."
        case .gemini:
            return "Gemini prefers concise prompts with clear structure. Avoid unnecessary preamble. Be direct."
        case .grok:
            return "Grok handles direct, conversational prompts well. No special formatting required. Plain language works."
        case .generic:
            return "Use a balanced style that works across major AI tools: clear task, supporting context, desired output format."
        }
    }
}

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case auto
    case english
    case telugu

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: return "Auto (match device)"
        case .english: return "English"
        case .telugu: return "Telugu (తెలుగు)"
        }
    }

    /// Speech recognition locale identifier. For .auto, the caller resolves from Locale.current.
    var speechLocaleIdentifier: String? {
        switch self {
        case .auto: return nil
        case .english: return "en-US"
        case .telugu: return "te-IN"
        }
    }

    var promptLanguageName: String? {
        switch self {
        case .auto: return nil
        case .english: return "English"
        case .telugu: return "Telugu"
        }
    }
}

enum OutputLanguage: String, CaseIterable, Identifiable {
    case sameAsInput
    case english
    case telugu

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .sameAsInput: return "Same as input"
        case .english: return "English"
        case .telugu: return "Telugu (తెలుగు)"
        }
    }

    var promptLanguageName: String? {
        switch self {
        case .sameAsInput: return nil
        case .english: return "English"
        case .telugu: return "Telugu"
        }
    }
}

struct PersonalFacts: Codable, Equatable {
    var name: String = ""
    var familyAndContext: String = ""
    var signOff: String = ""

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && familyAndContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && signOff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func renderedBlock() -> String? {
        guard !isEmpty else { return nil }
        var lines: [String] = ["About the user (use these facts when relevant; do not fabricate beyond them):"]
        if !name.isEmpty { lines.append("- Name: \(name)") }
        if !familyAndContext.isEmpty { lines.append("- Context: \(familyAndContext)") }
        if !signOff.isEmpty { lines.append("- Preferred sign-off: \(signOff)") }
        return lines.joined(separator: "\n")
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    var polishStyle: PolishStyle {
        didSet { defaults.set(polishStyle.rawValue, forKey: Key.polishStyle) }
    }

    var targetPlatform: TargetPlatform {
        didSet { defaults.set(targetPlatform.rawValue, forKey: Key.targetPlatform) }
    }

    var inputLanguage: InterfaceLanguage {
        didSet { defaults.set(inputLanguage.rawValue, forKey: Key.inputLanguage) }
    }

    var outputLanguage: OutputLanguage {
        didSet { defaults.set(outputLanguage.rawValue, forKey: Key.outputLanguage) }
    }

    var personalFacts: PersonalFacts {
        didSet {
            if let data = try? JSONEncoder().encode(personalFacts) {
                defaults.set(data, forKey: Key.personalFacts)
            }
        }
    }

    var selectedModelRaw: String {
        didSet { defaults.set(selectedModelRaw, forKey: Key.selectedModel) }
    }

    private enum Key {
        static let polishStyle = "polishStyle"
        static let targetPlatform = "targetPlatform"
        static let inputLanguage = "inputLanguage"
        static let outputLanguage = "outputLanguage"
        static let personalFacts = "personalFacts"
        static let selectedModel = "selectedModel"
    }

    private init() {
        let store = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        self.defaults = store

        self.polishStyle = PolishStyle(rawValue: store.string(forKey: Key.polishStyle) ?? "") ?? .standard
        self.targetPlatform = TargetPlatform(rawValue: store.string(forKey: Key.targetPlatform) ?? "") ?? .generic
        self.inputLanguage = InterfaceLanguage(rawValue: store.string(forKey: Key.inputLanguage) ?? "") ?? .auto
        self.outputLanguage = OutputLanguage(rawValue: store.string(forKey: Key.outputLanguage) ?? "") ?? .sameAsInput

        if let data = store.data(forKey: Key.personalFacts),
           let decoded = try? JSONDecoder().decode(PersonalFacts.self, from: data) {
            self.personalFacts = decoded
        } else {
            self.personalFacts = PersonalFacts()
        }

        self.selectedModelRaw = store.string(forKey: Key.selectedModel) ?? AnthropicModel.sonnet46.rawValue
    }

    // MARK: - Computed convenience

    /// Resolves "Auto" input language against the device locale.
    var resolvedInputLanguage: InterfaceLanguage {
        switch inputLanguage {
        case .auto:
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            return code == "te" ? .telugu : .english
        case .english, .telugu:
            return inputLanguage
        }
    }

    /// The resolved output language name to inject into the system prompt.
    var resolvedOutputLanguageName: String {
        switch outputLanguage {
        case .english: return "English"
        case .telugu: return "Telugu"
        case .sameAsInput: return resolvedInputLanguage.promptLanguageName ?? "English"
        }
    }
}
