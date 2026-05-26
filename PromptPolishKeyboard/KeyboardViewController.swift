import UIKit

class KeyboardViewController: UIInputViewController {

    private let polishButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var lastReplacedRange: Int = 0
    private var originalTextBeforePolish: String = ""

    private var selectedModel: AnthropicModel {
        let raw = UserDefaults.standard.string(forKey: "selectedModel") ?? AnthropicModel.sonnet46.rawValue
        return AnthropicModel(rawValue: raw) ?? .sonnet46
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGray6
        buildUI()
    }

    private func buildUI() {
        polishButton.setTitle("✨ Polish", for: .normal)
        polishButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        polishButton.backgroundColor = .tintColor
        polishButton.setTitleColor(.white, for: .normal)
        polishButton.layer.cornerRadius = 10
        polishButton.addTarget(self, action: #selector(polishTapped), for: .touchUpInside)

        undoButton.setTitle("Undo", for: .normal)
        undoButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        undoButton.backgroundColor = .systemBackground
        undoButton.layer.cornerRadius = 10
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
        undoButton.isHidden = true

        nextKeyboardButton.setTitle("🌐", for: .normal)
        nextKeyboardButton.titleLabel?.font = .systemFont(ofSize: 20)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .left

        spinner.hidesWhenStopped = true

        let row = UIStackView(arrangedSubviews: [nextKeyboardButton, polishButton, undoButton, spinner])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.distribution = .fill
        polishButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [row, statusLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
            polishButton.heightAnchor.constraint(equalToConstant: 44),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 44),
            undoButton.heightAnchor.constraint(equalToConstant: 44),
            undoButton.widthAnchor.constraint(equalToConstant: 64)
        ])
    }

    @objc private func polishTapped() {
        guard let text = currentText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showStatus("Nothing to polish — type or dictate something first.")
            return
        }

        originalTextBeforePolish = text
        lastReplacedRange = text.count
        beginLoading()

        Task {
            do {
                let result = try await AnthropicClient.shared.polish(text, model: selectedModel)
                await MainActor.run {
                    self.replaceText(originalLength: text.count, with: result.text)
                    self.lastReplacedRange = result.text.count
                    self.undoButton.isHidden = false
                    self.endLoading(status: "in: \(result.inputTokens)  out: \(result.outputTokens)  cache read: \(result.cacheReadTokens)")
                }
            } catch {
                await MainActor.run {
                    self.endLoading(status: "Error: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func undoTapped() {
        guard lastReplacedRange > 0 else { return }
        replaceText(originalLength: lastReplacedRange, with: originalTextBeforePolish)
        undoButton.isHidden = true
        showStatus("Reverted.")
    }

    private func currentText() -> String? {
        let proxy = textDocumentProxy
        if let selected = proxy.selectedText, !selected.isEmpty {
            return selected
        }
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        let combined = before + after
        return combined.isEmpty ? nil : combined
    }

    private func replaceText(originalLength: Int, with newText: String) {
        let proxy = textDocumentProxy
        if let selected = proxy.selectedText, !selected.isEmpty {
            proxy.insertText(newText)
            return
        }
        let beforeLen = (proxy.documentContextBeforeInput ?? "").count
        let afterLen = (proxy.documentContextAfterInput ?? "").count
        for _ in 0..<afterLen { proxy.adjustTextPosition(byCharacterOffset: 1) }
        for _ in 0..<(beforeLen + afterLen) { proxy.deleteBackward() }
        proxy.insertText(newText)
    }

    private func beginLoading() {
        polishButton.isEnabled = false
        polishButton.alpha = 0.5
        spinner.startAnimating()
        statusLabel.text = "Polishing with Claude…"
    }

    private func endLoading(status: String) {
        polishButton.isEnabled = true
        polishButton.alpha = 1.0
        spinner.stopAnimating()
        statusLabel.text = status
    }

    private func showStatus(_ text: String) {
        statusLabel.text = text
    }
}
