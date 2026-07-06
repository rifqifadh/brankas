enum SecretType: String, Codable, CaseIterable, Identifiable {
    case token
    case password
    case sshKey
    case certificate
    case note

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .token: "API Token"
        case .password: "Password"
        case .sshKey: "SSH Key"
        case .certificate: "Certificate"
        case .note: "Secure Note"
        }
    }

    var iconName: String {
        switch self {
        case .token: "key.horizontal"
        case .password: "lock"
        case .sshKey: "terminal"
        case .certificate: "shield"
        case .note: "doc.text"
        }
    }
}
