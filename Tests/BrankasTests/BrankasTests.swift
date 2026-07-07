import Testing
import Foundation
@testable import Brankas

@Test("SecretType display names match expected values")
func secretTypeDisplayNames() {
    #expect(SecretType.token.displayName == "API Token")
    #expect(SecretType.password.displayName == "Password")
    #expect(SecretType.sshKey.displayName == "SSH Key")
    #expect(SecretType.certificate.displayName == "Certificate")
    #expect(SecretType.note.displayName == "Secure Note")
}

@Test("SecretType icon names match expected values")
func secretTypeIconNames() {
    #expect(SecretType.token.iconName == "key.horizontal")
    #expect(SecretType.password.iconName == "lock")
    #expect(SecretType.sshKey.iconName == "terminal")
    #expect(SecretType.certificate.iconName == "shield")
    #expect(SecretType.note.iconName == "doc.text")
}

@Test("SecretType allCases includes all types")
func secretTypeAllCases() {
    #expect(SecretType.allCases.count == 5)
    #expect(SecretType.allCases == [.token, .password, .sshKey, .certificate, .note])
}

@Test("VaultData.empty returns empty vault with version 2")
func vaultDataEmpty() {
    let empty = VaultData.empty()
    #expect(empty.version == 2)
    #expect(empty.secrets.isEmpty)
    #expect(empty.items.isEmpty)
    #expect(empty.accounts.isEmpty)
    #expect(empty.services.isEmpty)
    #expect(empty.categories.isEmpty)
    #expect(empty.tags.isEmpty)
}

@Test("Category init sets default values")
func categoryDefaults() {
    let cat = Category(name: "Test")
    #expect(cat.name == "Test")
    #expect(cat.icon == "folder")
    #expect(cat.colorHex == "#007AFF")
    #expect(cat.sortOrder == 0)
}

@Test("Category init with custom values")
func categoryCustom() {
    let cat = Category(name: "Work", icon: "briefcase", colorHex: "#FF0000", sortOrder: 1)
    #expect(cat.name == "Work")
    #expect(cat.icon == "briefcase")
    #expect(cat.colorHex == "#FF0000")
    #expect(cat.sortOrder == 1)
}

@Test("TOTP base32Decode decodes known RFC 4648 test vectors")
func base32DecodeTestVectors() {
    let vec: [(String, String)] = [
        ("", ""),
        ("MY======", "f"),
        ("MZXQ====", "fo"),
        ("MZXW6===", "foo"),
        ("MZXW6YQ=", "foob"),
        ("MZXW6YTB", "fooba"),
        ("MZXW6YTBOI======", "foobar"),
    ]
    for (encoded, expected) in vec {
        let decoded = TOTPService.base32Decode(encoded)
        let result = decoded.map { String(data: $0, encoding: .utf8) } ?? nil
        #expect(result == expected, "base32Decode(\(encoded)) should be \(expected) got \(result ?? "nil")")
    }
}

@Test("TOTP base32Decode returns nil for invalid input")
func base32DecodeInvalid() {
    #expect(TOTPService.base32Decode("1") == nil)
    #expect(TOTPService.base32Decode("!@#$") == nil)
}

@Test("TOTP parseURL handles raw secret")
func parseURLRawSecret() {
    let config = TOTPService.parseURL("JBSWY3DPEHPK3PXP")
    #expect(config.secret == "JBSWY3DPEHPK3PXP")
    #expect(config.issuer == nil)
    #expect(config.account == nil)
    #expect(config.digits == 6)
    #expect(config.period == 30)
}

@Test("TOTP parseURL handles otpauth URL")
func parseURLOTPAuth() {
    let url = "otpauth://totp/ACME:john@example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME"
    let config = TOTPService.parseURL(url)
    #expect(config.secret == "JBSWY3DPEHPK3PXP")
    #expect(config.issuer == "ACME")
    #expect(config.account == "john@example.com")
    #expect(config.digits == 6)
    #expect(config.period == 30)
}

@Test("TOTP parseURL handles otpauth URL with custom digits/period")
func parseURLOTPAuthCustom() {
    let url = "otpauth://totp/GitHub:user?secret=JBSWY3DPEHPK3PXP&digits=8&period=60"
    let config = TOTPService.parseURL(url)
    #expect(config.secret == "JBSWY3DPEHPK3PXP")
    #expect(config.digits == 8)
    #expect(config.period == 60)
}

@Test("TOTP parseURL handles invalid URL gracefully")
func parseURLInvalid() {
    let config = TOTPService.parseURL("not-a-url")
    #expect(config.secret == "not-a-url")
}
