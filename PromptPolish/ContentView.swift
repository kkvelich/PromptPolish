import SwiftUI

struct ContentView: View {
    @StateObject private var speech = SpeechService()
    @State private var transcript: String = ""
    @State private var polished: String = ""
    @State private var isPolishing: Bool = false
    @State private var statusLine: String = ""
    @State private var errorMessage: String?
    @State private var showSettings: Bool = false
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    recordButton
                    transcriptSection
                    polishButton
                    if !polished.isEmpty {
                        polishedSection
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if !statusLine.isEmpty {
                        Text(statusLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("PromptPolish")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: speech.transcript) { _, newValue in
                transcript = newValue
            }
            .onChange(of: speech.errorMessage) { _, newValue in
                if let newValue { errorMessage = newValue }
            }
        }
    }

    private var recordButton: some View {
        Button {
            if speech.isRecording {
                speech.stopRecording()
            } else {
                polished = ""
                errorMessage = nil
                statusLine = ""
                speech.startRecording()
            }
        } label: {
            HStack {
                Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 32))
                Text(speech.isRecording ? "Stop" : "Record")
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(speech.isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))
            .foregroundStyle(speech.isRecording ? Color.red : Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript")
                .font(.headline)
            TextEditor(text: $transcript)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var polishButton: some View {
        Button {
            polish()
        } label: {
            HStack {
                if isPolishing {
                    ProgressView().tint(.white)
                }
                Text(isPolishing ? "Polishing…" : "Improve with Claude")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPolishing)
    }

    private var polishedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Polished")
                    .font(.headline)
                Spacer()
                Button {
                    UIPasteboard.general.string = polished
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(polished)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func polish() {
        let model = AnthropicModel(rawValue: settings.selectedModelRaw) ?? .sonnet46
        let rawText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return }
        isPolishing = true
        errorMessage = nil
        polished = ""
        statusLine = ""

        Task {
            do {
                for try await event in AnthropicClient.shared.polishStream(rawText, model: model, settings: settings) {
                    switch event {
                    case .chunk(let text):
                        polished += text
                    case .done(let result):
                        statusLine = "in: \(result.inputTokens)  out: \(result.outputTokens)  cache read: \(result.cacheReadTokens)  cache create: \(result.cacheCreationTokens)"
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isPolishing = false
        }
    }
}

#Preview {
    ContentView()
}
