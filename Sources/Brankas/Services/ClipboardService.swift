import AppKit
import Observation

@MainActor
@Observable
final class ClipboardService {
    private(set) var isCountingDown = false
    private(set) var remainingSeconds: Int = 0
    private var timer: Timer?
    private var clearTask: DispatchWorkItem?

    var autoClearDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(autoClearDuration, forKey: "clipboardAutoClearDuration")
        }
    }

    init() {
        let saved = UserDefaults.standard.double(forKey: "clipboardAutoClearDuration")
        autoClearDuration = saved > 0 ? saved : 30
    }

    func copy(_ value: String) {
        cancelPendingClear()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        startCountdown()
    }

    private func startCountdown() {
        isCountingDown = true
        remainingSeconds = Int(autoClearDuration)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    self.clearClipboard()
                }
            }
        }

        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.clearClipboard()
            }
        }
        clearTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + autoClearDuration, execute: task)
    }

    func cancelPendingClear() {
        timer?.invalidate()
        timer = nil
        clearTask?.cancel()
        clearTask = nil
        isCountingDown = false
    }

    private func clearClipboard() {
        NSPasteboard.general.clearContents()
        cancelPendingClear()
    }
}
