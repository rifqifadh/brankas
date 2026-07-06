import AppKit

final class MasterPasswordPanel: NSPanel {
    enum Mode {
        case set, unlock
    }

    private let mode: Mode
    private let passwordField = NSSecureTextField()
    private let confirmField = NSSecureTextField()
    private let errorLabel = NSTextField(labelWithString: "")
    private var resultPassword: String?
    private var hasCompleted = false

    init(mode: Mode) {
        self.mode = mode

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: mode == .set ? 260 : 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "Brankas"
        self.isFloatingPanel = true
        self.isMovable = false
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.center()

        setupViews()
    }

    required init?(coder: NSCoder) { nil }

    private func setupViews() {
        let cv = contentView!

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            root.topAnchor.constraint(equalTo: cv.topAnchor),
            root.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        let titleField = NSTextField(wrappingLabelWithString: mode == .set ? "Set Master Password" : "Unlock Brankas")
        titleField.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize(for: .regular) + 2)
        titleField.alignment = .center
        titleField.setContentHuggingPriority(.required, for: .vertical)

        let descText = mode == .set
            ? "Choose a master password to encrypt your vault. This is the only password you'll need."
            : "Enter your master password to unlock the vault."
        let descField = NSTextField(wrappingLabelWithString: descText)
        descField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        descField.textColor = .secondaryLabelColor
        descField.setContentHuggingPriority(.required, for: .vertical)

        root.addArrangedSubview(titleField)
        root.addArrangedSubview(descField)

        passwordField.placeholderString = "Master password"
        passwordField.heightAnchor.constraint(equalToConstant: 24).isActive = true
        root.addArrangedSubview(passwordField)

        if mode == .set {
            confirmField.placeholderString = "Confirm password"
            confirmField.heightAnchor.constraint(equalToConstant: 24).isActive = true
            root.addArrangedSubview(confirmField)
        }

        errorLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        errorLabel.setContentHuggingPriority(.required, for: .vertical)
        root.addArrangedSubview(errorLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(spacer)

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 8

        let quitBtn = NSButton(title: "Quit", target: self, action: #selector(quitAction))
        quitBtn.keyEquivalent = "\u{1b}"

        let primaryTitle = mode == .set ? "Set Password" : "Unlock"
        let primaryBtn = NSButton(title: primaryTitle, target: self, action: #selector(primaryAction))
        primaryBtn.keyEquivalent = "\r"

        btnRow.addArrangedSubview(quitBtn)
        btnRow.addArrangedSubview(primaryBtn)
        root.addArrangedSubview(btnRow)

        initialFirstResponder = passwordField
    }

    @objc private func primaryAction() {
        let pw = passwordField.stringValue

        if mode == .set {
            guard pw == confirmField.stringValue else {
                showError("Passwords don\u{2019}t match")
                return
            }
        }

        guard !pw.isEmpty else {
            showError("Password cannot be empty")
            return
        }

        hasCompleted = true
        resultPassword = pw
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
        close()
    }

    @objc private func quitAction() {
        hasCompleted = true
        resultPassword = nil
        NSApp.stopModal(withCode: .alertSecondButtonReturn)
        close()
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        passwordField.stringValue = ""
        confirmField.stringValue = ""
    }

    func runModal() -> String? {
        NSApp.runModal(for: self)
        return resultPassword
    }
}

extension MasterPasswordPanel: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !hasCompleted else { return }
        resultPassword = nil
        NSApp.stopModal(withCode: .alertSecondButtonReturn)
    }
}
