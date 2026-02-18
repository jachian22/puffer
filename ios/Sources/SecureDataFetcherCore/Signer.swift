import CryptoKit
import Foundation

public enum Signer {
    private static func canonicalData<T: Encodable>(from value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func key(from secret: String) -> SymmetricKey {
        SymmetricKey(data: Data(secret.utf8))
    }

    public static func sign<T: Encodable>(payload: T, secret: String) throws -> String {
        let data = try canonicalData(from: payload)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: key(from: secret))
        return Data(mac).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func verify<T: Encodable>(payload: T, signature: String, secret: String) throws -> Bool {
        let expected = try sign(payload: payload, secret: secret)
        return expected == signature
    }
}
