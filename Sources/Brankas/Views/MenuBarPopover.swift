import SwiftUI
import SwiftData

struct MenuBarPopover: View {
  @Environment(ClipboardService.self) private var clipboardService
  @Environment(\.modelContext) private var modelContext
  @Environment(\.appDelegate) private var appDelegate
  @Query(sort: \SecretItem.updatedAt, order: .reverse) private var secrets: [SecretItem]
  @Query(sort: \Service.name) private var services: [Service]
  @Query(sort: \Account.updatedAt, order: .reverse) private var allAccounts: [Account]
  
  @State private var selectedTab: Tab = .accounts
  @State private var searchText = ""
  @State private var expandedServices: Set<UUID> = []
  @State private var totpConfigs: [UUID: TOTPConfiguration] = [:]
  @State private var passwordCache: [UUID: String] = [:]
  @State private var now: Date = Date()
  
  enum Tab: String, CaseIterable {
    case vault = "Vault"
    case accounts = "Accounts"
  }
  
  private var filteredSecrets: [SecretItem] {
    guard !searchText.isEmpty else { return secrets }
    return secrets.filter { item in
      item.name.localizedStandardContains(searchText)
      || item.tags.contains { $0.name.localizedStandardContains(searchText)
        || item.type.displayName.localizedStandardContains(searchText)
      }
    }
  }
  
  private var filteredServices: [Service] {
    guard !searchText.isEmpty else { return services }
    return services.filter { svc in
      svc.name.localizedStandardContains(searchText)
      || svc.accounts.contains { $0.identifier.localizedStandardContains(searchText) }
    }
  }
  
  private func accounts(for service: Service) -> [Account] {
    let result = allAccounts.filter { $0.service.id == service.id }
    guard !searchText.isEmpty else { return result }
    if service.name.localizedStandardContains(searchText) {
      return result
    }
    return result.filter { $0.identifier.localizedStandardContains(searchText) }
  }
  
  var body: some View {
    VStack(spacing: 0) {
      SearchBar(text: $searchText)
        .padding()
      
      Picker("", selection: $selectedTab) {
        ForEach(Tab.allCases, id: \.self) { tab in
          Text(tab.rawValue).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .padding(.bottom, 8)
      
      Divider()
      
      if selectedTab == .vault {
        vaultContent
      } else {
        accountsContent
      }
      
      Divider()
      
      HStack {
        if clipboardService.isCountingDown {
          HStack(spacing: 4) {
            Image(systemName: "clock")
              .font(.caption)
            Text("Clears in \(clipboardService.remainingSeconds)s")
              .font(.caption)
              .monospacedDigit()
          }
          .foregroundStyle(.secondary)
          
          Button("Clear Now", systemImage: "xmark.circle") {
            clipboardService.cancelPendingClear()
            NSPasteboard.general.clearContents()
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
        }
        
        Spacer()
        
        Button("Open Brankas", systemImage: "arrow.up.forward.app") {
          openMainApp()
        }
        .buttonStyle(.plain)
        .font(.callout)
        
        Divider()
          .frame(height: 16)
        
        Button("Settings", systemImage: "gearshape") {
          appDelegate?.openSettings()
        }
        .buttonStyle(.plain)
        .font(.callout)
        
        Divider()
          .frame(height: 16)
        
        Button("Quit", systemImage: "xmark.circle") {
          NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .font(.callout)
      }
      .padding(12)
    }
    .frame(width: 360, height: 480)
    .onAppear {
      preloadCache()
      Task { await TimeSyncService.sync() }
    }
    .onChange(of: searchText) { _, newValue in
      if !newValue.isEmpty {
        expandedServices = Set(services.map(\.id))
      }
    }
    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
      now = Date()
    }
  }
  
  @ViewBuilder
  private var vaultContent: some View {
    if filteredSecrets.isEmpty {
      VStack(spacing: 8) {
        Image(systemName: "key.horizontal")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
        Text("No secrets found")
          .foregroundStyle(.secondary)
      }
      .frame(maxHeight: .infinity)
    } else {
      List(filteredSecrets) { item in
        HStack(spacing: 6) {
          TokenRowView(item: item, showTypeIcon: true, onCopy: { copySecret(item) })
          
          expiryBadge(item.expiresAt)
        }
        .padding(.horizontal, 4)
      }
      .listStyle(.plain)
    }
  }
  
  @ViewBuilder
  private var accountsContent: some View {
    if services.isEmpty {
      VStack(spacing: 8) {
        Image(systemName: "person.crop.circle")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
        Text("No accounts yet")
          .foregroundStyle(.secondary)
      }
      .frame(maxHeight: .infinity)
    } else {
      List {
        ForEach(filteredServices) { service in
          let accts = accounts(for: service)
          DisclosureGroup(isExpanded: expandedBinding(for: service.id)) {
            ForEach(accts) { account in
              accountRowView(for: account)
                .onAppear {
                  loadTOTP(for: account)
                }
            }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: service.icon)
                .foregroundStyle(.tint)
                .frame(width: 16)
              Text(service.name)
                .font(.callout)
              Spacer()
              Text("\(accts.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .listStyle(.plain)
    }
  }
  
  private func expandedBinding(for id: UUID) -> Binding<Bool> {
    Binding(
      get: { expandedServices.contains(id) },
      set: { expanded in
        if expanded { expandedServices.insert(id) }
        else { expandedServices.remove(id) }
      }
    )
  }
  
  private func copySecret(_ item: SecretItem) {
    guard let value = try? VaultService.read(for: item.id.uuidString) else { return }
    clipboardService.copy(value)
  }
  
  private func preloadCache() {
    for account in allAccounts {
      guard passwordCache[account.id] == nil else { continue }
      let pwd = try? VaultService.read(for: account.id.uuidString)
      passwordCache[account.id] = pwd
      
      if account.hasTOTP, totpConfigs[account.id] == nil {
        let raw = try? VaultService.read(for: "totp-\(account.id.uuidString)")
        if let raw {
          totpConfigs[account.id] = TOTPService.parseURL(raw)
        }
      }
    }
  }
  
  private func loadTOTP(for account: Account) {
    guard account.hasTOTP, totpConfigs[account.id] == nil else { return }
    let raw = try? VaultService.read(for: "totp-\(account.id.uuidString)")
    if let raw {
      totpConfigs[account.id] = TOTPService.parseURL(raw)
    }
  }
  
  private func cachedPassword(_ account: Account) -> String? {
    if let cached = passwordCache[account.id] { return cached }
    do {
      let value = try VaultService.read(for: account.id.uuidString)
      passwordCache[account.id] = value
      return value
    } catch {
      NSLog("Brankas: Failed to read password for account \(account.id): \(error.localizedDescription)")
      return nil
    }
  }
  
  private func copyUsername(_ account: Account) {
    clipboardService.copy(account.identifier)
  }
  
  private func copyAccount(_ account: Account) {
    guard let value = cachedPassword(account) else { return }
    clipboardService.copy(value)
  }
  
  private func openMainApp() {
    appDelegate?.openMainWindow()
  }
  
  @ViewBuilder
  private func expiryBadge(_ date: Date?) -> some View {
    if let date {
      let daysUntil = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
      if daysUntil <= 0 {
        Text("Expired")
          .font(.caption2)
          .foregroundStyle(.red)
      } else       if daysUntil <= 7 {
        Text("\(daysUntil)d")
          .font(.caption2)
          .foregroundStyle(.orange)
      }
    }
  }
  
  @ViewBuilder
  private func accountRowView(for account: Account) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Button {
          copyUsername(account)
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "person.circle")
              .foregroundStyle(.tint)
              .frame(width: 14)
            
            Text(account.identifier)
              .font(.callout)
              .lineLimit(1)
          }
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary.opacity(0.4))
          .clipShape(.rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("Copy Username")
        
        expiryBadge(account.expiresAt)
        
        if account.isFavorite {
          Image(systemName: "star.fill")
            .font(.caption2)
            .foregroundStyle(.yellow)
        }
      }
      
      HStack(spacing: 8) {
        Button {
          copyAccount(account)
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "lock")
              .font(.caption2)
            Text("••••••••••")
              .font(.caption)
              .monospaced()
          }
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary.opacity(0.4))
          .clipShape(.rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("Copy password")
        
        if account.hasTOTP, let config = totpConfigs[account.id] {
          let _ = now
          let progress = CGFloat(TOTPService.remainingSeconds(config: config)) / CGFloat(config.period)
          let code = TOTPService.generate(config: config) ?? "------"
          let isExpiring = TOTPService.remainingSeconds(config: config) <= 5
          
          HStack(spacing: 4) {
            Button {
              clipboardService.copy(code)
            } label: {
              HStack(spacing: 3) {
                Image(systemName: "lock.shield")
                  .font(.caption2)
                Text(code)
                  .font(.system(.caption, design: .monospaced))
                  .fontWeight(.bold)
              }
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.quaternary.opacity(0.4))
              .clipShape(.rect(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Copy TOTP code")
            
            ZStack {
              Circle()
                .stroke(.quaternary, lineWidth: 3)
                .frame(width: 24, height: 24)
              Circle()
                .trim(from: 0, to: progress)
                .stroke(isExpiring ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(-90))
              Text("\(TOTPService.remainingSeconds(config: config))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(isExpiring ? .red : .secondary)
            }
          }
        }
      }
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  MenuBarPopover()
    .modelContainer(for: [SecretItem.self, Service.self, Account.self, Tag.self], inMemory: true)
}
