import XCTest
@testable import SecureDataFetcherCore

final class ManifestSigningTests: XCTestCase {
    func testManifestSignatureVerification() throws {
        let payload = UnsignedCompletionManifest(
            version: "1",
            requestId: "req-4",
            filename: "req-4-jan-2026.pdf",
            sha256: "abc",
            bytes: 123,
            completedAt: "2026-02-17T00:00:00Z",
            nonce: "nonce-4"
        )
        let signature = try Signer.sign(payload: payload, secret: "test_secret")
        let manifest = CompletionManifest(
            version: "1",
            requestId: "req-4",
            filename: "req-4-jan-2026.pdf",
            sha256: "abc",
            bytes: 123,
            completedAt: "2026-02-17T00:00:00Z",
            nonce: "nonce-4",
            signature: signature
        )

        let verifier = ManifestVerifier(sharedSecret: "test_secret")
        XCTAssertTrue(try verifier.verify(manifest))
    }
}
