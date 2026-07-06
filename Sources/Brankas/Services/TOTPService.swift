import Foundation
import CryptoKit

struct TOTPConfiguration {
    let secret: String
    let issuer: String?
    let account: String?
    let digits: Int
    let period: Int

    init(secret: String, issuer: String? = nil, account: String? = nil, digits: Int = 6, period: Int = 30) {
        self.secret = secret
        self.issuer = issuer
        self.account = account
        self.digits = digits
        self.period = period
    }
}

struct TOTPService {
    /// Time offset from network sync (seconds). Applied to all TOTP generation.
    /// Set by TimeSyncService. Zero = use system clock as-is.
    static var timeOffset: TimeInterval = 0

    static func generate(config: TOTPConfiguration) -> String? {
        let adjustedTime = Date().timeIntervalSince1970 + timeOffset
        let counter = UInt64(adjustedTime / Double(config.period)).bigEndian
        let counterData = withUnsafeBytes(of: counter) { Data($0) }
        guard let keyData = base32Decode(config.secret), keyData.count > 0 else { return nil }

        let symmetricKey = SymmetricKey(data: keyData)
        let code = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: symmetricKey)
        let codeData = Data(code)

        guard let last = codeData.last else { return nil }
        let offset = Int(last) & 0x0f
        // RFC 4226 Section 5.4: big-endian, clear MSB
        let truncated = (UInt32(codeData[offset] & 0x7f) << 24)
            | (UInt32(codeData[offset + 1]) << 16)
            | (UInt32(codeData[offset + 2]) << 8)
            | UInt32(codeData[offset + 3])

        let otp = truncated % UInt32(pow(10, Double(config.digits)))
        return String(format: "%0\(config.digits)d", otp)
    }

    static func remainingSeconds(config: TOTPConfiguration) -> Int {
        let adjustedTime = Date().timeIntervalSince1970 + timeOffset
        return config.period - (Int(adjustedTime) % config.period)
    }

    static func parseURL(_ urlString: String) -> TOTPConfiguration {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().hasPrefix("otpauth://") {
            return parseOTPAuth(trimmed)
        }

        return TOTPConfiguration(secret: trimmed)
    }

    private static func parseOTPAuth(_ urlString: String) -> TOTPConfiguration {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return TOTPConfiguration(secret: urlString)
        }

        let params = components.queryItems ?? []
        let secret = params.first(where: { $0.name == "secret" })?.value ?? urlString
        let issuer = params.first(where: { $0.name == "issuer" })?.value
        let digits = Int(params.first(where: { $0.name == "digits" })?.value ?? "") ?? 6
        let period = Int(params.first(where: { $0.name == "period" })?.value ?? "") ?? 30

        let path = components.path.removingPercentEncoding ?? ""
        let pathParts = path.split(separator: ":").map(String.init)
        let account: String?
        if pathParts.count >= 2 {
            account = pathParts.dropFirst().joined(separator: ":")
        } else if pathParts.count == 1 {
            account = pathParts[0]
        } else {
            account = nil
        }

        return TOTPConfiguration(
            secret: secret,
            issuer: issuer ?? pathParts.first,
            account: account,
            digits: digits,
            period: period
        )
    }

    static func base32Decode(_ string: String) -> Data? {
        let cleaned = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0 != "=" }

        var bits = 0
        var bitCount = 0
        var result = Data()

        for char in cleaned {
            guard let value = char.asciiValue else { return nil }
            let index: UInt8
            if value >= 65 && value <= 90 {
                index = value - 65
            } else if value >= 50 && value <= 55 {
                index = value - 24
            } else {
                return nil
            }

            bits = (bits << 5) | Int(index)
            bitCount += 5

            if bitCount >= 8 {
                bitCount -= 8
                result.append(UInt8((bits >> bitCount) & 0xFF))
            }
        }

        return result
    }
}
