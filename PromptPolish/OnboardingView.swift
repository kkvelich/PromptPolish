import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var apiKey: String = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Welcome to PromptPolish")
                        .font(.largeTitle.bold())
                    Text("Dictate rough ideas. Get clean AI prompts.")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("1. Add your Anthropic API key")
                        .font(.headline)
                    Text("Get one at console.anthropic.com → Settings → API Keys. Fund $5 in credits; it will last months for personal use.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SecureField("sk-ant-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("2. Enable the PromptPolish keyboard")
                        .font(.headline)
                    Text("Settings → General → Keyboard → Keyboards → Add New Keyboard → PromptPolish. Then tap it and turn on \"Allow Full Access\" so it can call the Claude API.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Link("Open iOS Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                        .font(.footnote)

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if key.isEmpty {
                            error = "Paste an API key first."
                        } else {
                            KeychainHelper.saveAPIKey(key)
                            hasCompletedOnboarding = true
                        }
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
        }
    }
}
