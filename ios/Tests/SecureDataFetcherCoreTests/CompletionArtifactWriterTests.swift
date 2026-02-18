import CryptoKit
import Foundation
import XCTest
@testable import SecureDataFetcherCore

final class CompletionArtifactWriterTests: XCTestCase {
    func testWriteStatementPDFWritesPDFAndSignedManifest() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("puffer-writer-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fixedDate = ISO8601DateFormatter().date(from: "2026-02-17T21:00:00Z")!
        let writer = CompletionArtifactWriter(
            inboxDirectory: tempDir,
            sharedSecret: "secret_123",
            nowProvider: { fixedDate },
            nonceProvider: { "nonce-fixed" }
        )

        let pdfData = Data("fake-pdf-data".utf8)
        let result = try writer.writeStatementPDF(
            requestId: "req-123",
            month: 1,
            year: 2026,
            pdfData: pdfData
        )

        XCTAssertEqual(result.pdfURL.lastPathComponent, "req-123-jan-2026.pdf")
        XCTAssertEqual(result.manifestURL.lastPathComponent, "req-123-jan-2026.pdf.manifest.json")

        let writtenPDF = try Data(contentsOf: result.pdfURL)
        XCTAssertEqual(writtenPDF, pdfData)

        let manifestData = try Data(contentsOf: result.manifestURL)
        let decoded = try JSONDecoder().decode(CompletionManifest.self, from: manifestData)
        XCTAssertEqual(decoded.requestId, "req-123")
        XCTAssertEqual(decoded.filename, "req-123-jan-2026.pdf")
        XCTAssertEqual(decoded.bytes, pdfData.count)
        XCTAssertEqual(decoded.nonce, "nonce-fixed")

        let expectedDigest = SHA256.hash(data: pdfData)
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(decoded.sha256, expectedDigest)

        let verifier = ManifestVerifier(sharedSecret: "secret_123")
        XCTAssertTrue(try verifier.verify(decoded))
    }

    func testWriteStatementPDFRejectsInvalidMonth() {
        let writer = CompletionArtifactWriter(
            inboxDirectory: FileManager.default.temporaryDirectory,
            sharedSecret: "secret_123"
        )

        XCTAssertThrowsError(
            try writer.writeStatementPDF(
                requestId: "req-123",
                month: 13,
                year: 2026,
                pdfData: Data("x".utf8)
            )
        ) { error in
            XCTAssertEqual(error as? CompletionArtifactWriterError, .invalidMonth)
        }
    }

    func testWriteStatementPDFRejectsDuplicateFileNames() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("puffer-writer-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let writer = CompletionArtifactWriter(
            inboxDirectory: tempDir,
            sharedSecret: "secret_123",
            nonceProvider: { "nonce-fixed" }
        )

        _ = try writer.writeStatementPDF(
            requestId: "req-123",
            month: 1,
            year: 2026,
            pdfData: Data("payload".utf8)
        )

        XCTAssertThrowsError(
            try writer.writeStatementPDF(
                requestId: "req-123",
                month: 1,
                year: 2026,
                pdfData: Data("payload".utf8)
            )
        ) { error in
            XCTAssertEqual(error as? CompletionArtifactWriterError, .fileAlreadyExists)
        }
    }
}
