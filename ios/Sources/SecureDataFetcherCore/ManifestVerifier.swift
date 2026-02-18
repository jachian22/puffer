import Foundation

public struct ManifestVerifier {
    private let sharedSecret: String

    public init(sharedSecret: String) {
        self.sharedSecret = sharedSecret
    }

    public func verify(_ manifest: CompletionManifest) throws -> Bool {
        guard manifest.version == "1" else {
            return false
        }
        return try Signer.verify(
            payload: UnsignedCompletionManifest(from: manifest),
            signature: manifest.signature,
            secret: sharedSecret
        )
    }
}
