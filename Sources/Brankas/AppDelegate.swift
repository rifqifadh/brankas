import AppKit
import SwiftUI
import SwiftData
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let currentSchemaVersion = 4
    static private(set) var isVaultUnlocked = false

    private static var storeBase: String {
        #if DEBUG
        "brankas-debug.store"
        #else
        "brankas.store"
        #endif
    }

    let clipboardService = ClipboardService()

    lazy var container: ModelContainer = {
        Self.handleSchemaMigration()
        return Self.createContainer()
    }()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard authenticateVault() else {
            NSApplication.shared.terminate(nil)
            return
        }

        VaultBackupService.createBackup()
        let syncContext = ModelContext(container)
        VaultSyncService.syncAll(context: syncContext)

        setupMenuBar()

        NotificationService.requestAuthorization()
        let context = ModelContext(container)
        NotificationService.scheduleExpiryNotifications(context: context)
        startNotificationRefreshTimer(context: context)
    }

    private func startNotificationRefreshTimer(context: ModelContext) {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor [self] in
                guard Self.isVaultUnlocked else { return }
                let ctx = ModelContext(self.container)
                NotificationService.scheduleExpiryNotifications(context: ctx)
            }
        }
    }

    private func authenticateVault() -> Bool {
        #if DEBUG
        try? VaultService.load(password: "debug")
        Self.isVaultUnlocked = true
        return true
        #else
        if UserDefaults.standard.bool(forKey: "biometricUnlock") {
            do {
                let password = try KeychainService.readVaultPassword()
                try VaultService.load(password: password)
                Self.isVaultUnlocked = true
                return true
            } catch {
                NSLog("Brankas: Biometric unlock failed: \(error.localizedDescription)")
            }
        }

        let isFirst = VaultService.isFirstLaunch()

        if isFirst {
            return showSetPasswordDialog()
        } else {
            return showUnlockDialog()
        }
        #endif
    }

    private func showSetPasswordDialog() -> Bool {
        while true {
            let panel = MasterPasswordPanel(mode: .set)
            guard let pw = panel.runModal() else { return false }

            guard !pw.isEmpty else { continue }

            do {
                try VaultService.load(password: pw)
                Self.isVaultUnlocked = true
                return true
            } catch {
                let alert = NSAlert()
                alert.messageText = "Error: \(error.localizedDescription)"
                alert.runModal()
            }
        }
    }

    private func showUnlockDialog() -> Bool {
        for attempt in 1...3 {
            let panel = MasterPasswordPanel(mode: .unlock)
            guard let pw = panel.runModal() else { return false }

            guard !pw.isEmpty else { continue }

            do {
                try VaultService.load(password: pw)
                Self.isVaultUnlocked = true
                return true
            } catch {
                if attempt < 3 {
                    let alert = NSAlert()
                    alert.messageText = "Wrong password. Try again."
                    alert.runModal()
                }
            }
        }

        let alert = NSAlert()
        alert.messageText = "Too many incorrect attempts."
        alert.informativeText = "Brankas will now quit."
        alert.runModal()
        return false
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Brankas")
            button.action = #selector(handleMenuBarClick)
        }

        let contentView = MenuBarPopover()
            .environment(clipboardService)
            .environment(\.appDelegate, self)
            .modelContainer(container)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 360, height: 480)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func handleMenuBarClick() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openMainWindow() {
        if let existing = mainWindow, existing.isVisible {
            popover?.performClose(nil)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        popover?.performClose(nil)
        NSApp.setActivationPolicy(.regular)

        let contentView = ContentView()
            .environment(clipboardService)
            .modelContainer(container)

        let controller = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Brankas"
        window.setContentSize(NSSize(width: 800, height: 600))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        mainWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettings() {
        let settingsView = SettingsView()
            .environment(clipboardService)
            .modelContainer(container)

        let controller = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Brankas Settings"
        window.setContentSize(NSSize(width: 450, height: 300))
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) == mainWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Schema Migration

    private static func handleSchemaMigration() {
        let previousVersion = UserDefaults.standard.integer(forKey: "schemaVersion")
        let currentVersion = currentSchemaVersion

        guard previousVersion != 0, previousVersion != currentVersion else {
            if previousVersion == 0 {
                UserDefaults.standard.set(currentVersion, forKey: "schemaVersion")
            }
            return
        }

        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupDir = desktop.appendingPathComponent("Brankas-backup-v\(previousVersion)-\(timestamp)", isDirectory: true)

        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        for suffix in ["", "-wal", "-shm"] {
            let name = storeBase + suffix
            let src = URL.applicationSupportDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.copyItem(at: src, to: backupDir.appendingPathComponent(name))
            }
            try? FileManager.default.removeItem(at: src)
        }

        UserDefaults.standard.set(currentVersion, forKey: "schemaVersion")

        NSLog("Brankas: Schema v\(previousVersion) → v\(currentVersion). Metadata backed up to: \(backupDir.path)")
    }

    private static func createContainer() -> ModelContainer {
        let schema = Schema([SecretItem.self, Category.self, Tag.self, Service.self, Account.self])
        let storeURL = URL.applicationSupportDirectory.appendingPathComponent(storeBase)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

private struct AppDelegateKey: EnvironmentKey {
    static let defaultValue: AppDelegate? = nil
}

extension EnvironmentValues {
    var appDelegate: AppDelegate? {
        get { self[AppDelegateKey.self] }
        set { self[AppDelegateKey.self] = newValue }
    }
}
