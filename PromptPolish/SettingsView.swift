import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var savedNotice: String?
    @AppStorage("selectedModel") private var selectedModelRaw: String = AnthropicModel.sonnet46.rawValue

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("Stored in the iOS Keychain and shared with the keyboard extension via App Group.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Model") {
                    Picker("Model", selection: $selectedModelRaw) {
                        ForEach(AnthropicModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Keyboard Extension") {
                    Link("Open iOS Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    Text("In Settings → General → Keyboard → Keyboards → Add New Keyboard, add PromptPolish, then tap it and enable Allow Full Access.")
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
