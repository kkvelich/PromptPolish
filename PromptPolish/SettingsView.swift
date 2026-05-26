import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared

    @State private var apiKey: String = ""
    @State private var savedNotice: String?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - API key
                Section("Anthropic API Key") {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save") {
                        KeychainHelper.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        savedNotice = "Saved."
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let savedNotice {
                        Text(savedNotice).font(.footnote).foregroundStyle(.green)
                    }
                    Text("Stored in iOS Keychain and shared with the keyboard extension via App Group.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Polish style
                Section {
                    Picker("Style", selection: $settings.polishStyle) {
                        ForEach(PolishStyle.allCases) { style in
                            Text(LocalizedStringKey(style.displayName)).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(LocalizedStringKey(settings.polishStyle.description))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Polish Style")
                } footer: {
                    Text("How much structure the polished prompt should have. Compact for quick questions, Detailed for complex asks.")
                }

                // MARK: - Target AI
                Section {
                    Picker("Target AI", selection: $settings.targetPlatform) {
                        ForEach(TargetPlatform.allCases) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                } header: {
                    Text("Target AI")
                } footer: {
                    Text("Different AI tools respond best to different prompt styles. PromptPolish tailors the output for your target.")
                }

                // MARK: - Language
                Section {
                    Picker("Input language", selection: $settings.inputLanguage) {
                        ForEach(InterfaceLanguage.allCases) { lang in
                            Text(LocalizedStringKey(lang.displayName)).tag(lang)
                        }
                    }
                    Picker("Output language", selection: $settings.outputLanguage) {
                        ForEach(OutputLanguage.allCases) { lang in
                            Text(LocalizedStringKey(lang.displayName)).tag(lang)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Input controls speech recognition locale. Output controls the language of the polished prompt. \"Auto\" matches your device language. \"Same as input\" keeps the polished prompt in the language you dictated.")
                }

                // MARK: - Personal facts
                Section {
                    TextField("Your name", text: $settings.personalFacts.name)
                        .textInputAutocapitalization(.words)
                    TextField("Family / context (one line)", text: $settings.personalFacts.familyAndContext, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Sign-off", text: $settings.personalFacts.signOff)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("About You")
                } footer: {
                    Text("Optional. PromptPolish uses these to make prompts more specific when relevant. Example context: \"Wife Suneeta, son Neil (12, in CUSD), based in Sun Lakes, AZ\". Sign-off: \"Kiran\" or \"Best, Kiran\".")
                }

                // MARK: - Model
                Section {
                    Picker("Model", selection: $settings.selectedModelRaw) {
                        ForEach(AnthropicModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Model")
                } footer: {
                    Text("Sonnet is recommended — prompt caching works (cheaper repeat calls) and Telugu quality is strong.")
                }

                // MARK: - Keyboard extension
                Section("Keyboard Extension") {
                    Link("Open iOS Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    Text("Settings → General → Keyboard → Keyboards → Add New Keyboard → PromptPolish. Then tap it and enable Allow Full Access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let existing = KeychainHelper.loadAPIKey() {
                    apiKey = existing
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
