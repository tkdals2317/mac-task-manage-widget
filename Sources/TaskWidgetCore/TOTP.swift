import CryptoKit
import Foundation

/// RFC 6238 (HMAC-SHA1). 입력은 base32 키(공백·소문자 허용) 또는 `otpauth://totp/...?secret=` URL.
public struct TOTP {
    private let key: Data

    public init?(input: String) {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.lowercased().hasPrefix("otpauth://") {
            guard let c = URLComponents(string: raw), c.host?.lowercased() == "totp",
                  let s = c.queryItems?.first(where: { $0.name.lowercased() == "secret" })?.value else { return nil }
            raw = s
        }
        guard let k = Self.base32Decode(raw), !k.isEmpty else { return nil }
        key = k
    }

    public func code(at date: Date = Date(), digits: Int = 6, period: TimeInterval = 30) -> String {
        var counter = UInt64(max(0, date.timeIntervalSince1970) / period).bigEndian
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(bytes: &counter, count: 8), using: SymmetricKey(data: key))
        let h = Array(mac)
        let o = Int(h[h.count - 1] & 0x0f)
        let bin = (UInt32(h[o] & 0x7f) << 24) | (UInt32(h[o + 1]) << 16) | (UInt32(h[o + 2]) << 8) | UInt32(h[o + 3])
        var mod: UInt32 = 1
        for _ in 0..<digits { mod *= 10 }
        let s = String(bin % mod)
        return String(repeating: "0", count: max(0, digits - s.count)) + s
    }

    public static func secondsLeft(at date: Date = Date(), period: TimeInterval = 30) -> Int {
        Int(period - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period))
    }

    static func base32Decode(_ s: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0, acc = 0
        var out = Data()
        for ch in s.uppercased() where ch != " " && ch != "-" && ch != "=" {
            guard let v = alphabet.firstIndex(of: ch) else { return nil }
            acc = (acc << 5) | v
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((acc >> bits) & 0xff))
                acc &= (1 << bits) - 1
            }
        }
        return out
    }
}
