import SwiftUI

struct TOTPView: View {
    @Environment(ClipboardService.self) private var clipboardService

    let config: TOTPConfiguration

    @State private var code: String = "------"
    @State private var remaining: Int = 30
    @State private var timer: Timer?
    @State private var showingDebug = false

    private var progress: CGFloat {
        CGFloat(remaining) / CGFloat(config.period)
    }

    private var isExpiring: Bool { remaining <= 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Two-Factor Authentication", systemImage: "lock.shield")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let issuer = config.issuer {
                HStack(spacing: 4) {
                    Text(issuer).font(.caption).foregroundStyle(.secondary)
                    if let account = config.account {
                        Text("•").font(.caption).foregroundStyle(.tertiary)
                        Text(account).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 5)
                        .frame(width: 72, height: 72)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(isExpiring ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: remaining)

                    VStack(spacing: 0) {
                        Text(code)
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.bold)
                            .tracking(2)
                        Text("\(remaining)s")
                            .font(.caption2)
                            .foregroundStyle(isExpiring ? .red : .secondary)
                            .monospacedDigit()
                    }
                }

                Spacer()

                Button("Copy", systemImage: "doc.on.doc") {
                    clipboardService.copy(code)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy code")
            }
            .padding(12)
            .background(.quaternary.opacity(0.3))
            .clipShape(.rect(cornerRadius: 8))

            // Time sync status indicator
            syncStatusRow
        }
        .onAppear {
            generateCode()
            // Sync clock on first TOTP view load; async, non-blocking
            Task { await TimeSyncService.sync() }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { self.generateCode() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        let status = TimeSyncService.status
        HStack(spacing: 6) {
            switch status {
            case .idle, .syncing:
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Syncing time...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            case .synced(let offset):
                let absDrift = abs(offset)
                if absDrift > 5 {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Drift: \(Int(absDrift))s")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Time synced")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            case .failed(let msg):
                Image(systemName: "xmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .onTapGesture {
            showingDebug.toggle()
        }
        .help(showingDebug ? debugInfo : "Tap for debug info")
    }

    private var debugInfo: String {
        let status = TimeSyncService.status
        let offset = TOTPService.timeOffset
        let adjustedTime = Date().timeIntervalSince1970 + offset
        let counter = UInt64(adjustedTime / Double(config.period))
        return """
        Counter: \(counter)
        Offset: \(offset)s
        Period: \(config.period)s
        Digits: \(config.digits)
        Status: \(status)
        """
    }

    private func generateCode() {
        if let newCode = TOTPService.generate(config: config) {
            code = newCode
        }
        remaining = TOTPService.remainingSeconds(config: config)
    }
}
