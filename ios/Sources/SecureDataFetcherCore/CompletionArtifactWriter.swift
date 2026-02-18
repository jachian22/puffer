import CryptoKit
import Foundation

public enum CompletionArtifactWriterError: Error, Equatable, Sendable {
    case invalidMonth
    case emptyPayload
    case fileAlreadyExists
}

public struct CompletionWriteResult: Equatable, Sendable {
    public let pdfURL: URL
    public let manifestURL: URL
    public let manifest: CompletionManifest

    public init(pdfURL: URL, manifestURL: URL, manifest: CompletionManifest) {
        self.pdfURL = pdfURL
        self.manifestURL = manifestURL
        self.manifest = manifest
    }
}

public struct CompletionArtifactWriter {
    public let inboxDirectory: URL
    public let sharedSecret: String
    public let fileManager: FileManager
    public let nowProvider: () -> Date
    public let nonceProvider: () -> String

    public init(
        inboxDirectory: URL,
        sharedSecret: String,
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init,
        nonceProvider: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.inboxDirectory = inboxDirectory
        self.sharedSecret = sharedSecret
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.nonceProvider = nonceProvider
    }

    public func writeStatementPDF(
        requestId: String,
        month: Int,
        year: Int,
        pdfData: Data
    ) throws -> CompletionWriteResult {
        guard (1...12).contains(month) else {
            throw CompletionArtifactWriterError.invalidMonth
        }
        guard !pdfData.isEmpty else {
            throw CompletionArtifactWriterError.emptyPayload
        }

        let filename = "\(requestId)-\(monthAbbreviation(for: month))-\(year).pdf"
        let pdfURL = inboxDirectory.appendingPathComponent(filename)
        let manifestURL = inboxDirectory.appendingPathComponent("\(filename).manifest.json")

        if fileManager.fileExists(atPath: pdfURL.path) || fileManager.fileExists(atPath: manifestURL.path) {
            throw CompletionArtifactWriterError.fileAlreadyExists
        }

        let digest = sha256Hex(data: pdfData)
        let completedAt = iso8601(nowProvider())
        let nonce = nonceProvider()

        let unsigned = UnsignedCompletionManifest(
            version: "1",
            requestId: requestId,
            filename: filename,
            sha256: digest,
            bytes: pdfData.count,
            completedAt: completedAt,
            nonce: nonce
        )
        let signature = try Signer.sign(payload: unsigned, secret: sharedSecret)
        let manifest = CompletionManifest(
            version: unsigned.version,
            requestId: unsigned.requestId,
            filename: unsigned.filename,
            sha256: unsigned.sha256,
            bytes: unsigned.bytes,
            completedAt: unsigned.completedAt,
            nonce: unsigned.nonce,
            signature: signature
        )

        try fileManager.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)

        let tempToken = UUID().uuidString.lowercased()
        let tempPDF = inboxDirectory.appendingPathComponent(".\(tempToken).pdf.tmp")
        let tempManifest = inboxDirectory.appendingPathComponent(".\(tempToken).manifest.json.tmp")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)

        try pdfData.write(to: tempPDF, options: .atomic)
        try manifestData.write(to: tempManifest, options: .atomic)

        try fileManager.moveItem(at: tempPDF, to: pdfURL)
        try fileManager.moveItem(at: tempManifest, to: manifestURL)

        return CompletionWriteResult(pdfURL: pdfURL, manifestURL: manifestURL, manifest: manifest)
    }

    private func monthAbbreviation(for month: Int) -> String {
        let months = [
            "jan", "feb", "mar", "apr", "may", "jun",
            "jul", "aug", "sep", "oct", "nov", "dec",
        ]
        return months[month - 1]
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func sha256Hex(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
