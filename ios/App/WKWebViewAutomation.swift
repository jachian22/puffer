import Foundation
import SecureDataFetcherCore
import WebKit

enum WKWebViewAutomationDriverError: Error {
    case navigationInProgress
    case invalidJavaScriptResult
    case missingPDFURL
    case pdfTimeout
    case pdfHTTPStatus(Int)
}

struct WKWebViewDriverFactory: BankAutomationDriverFactory {
    let session: AutomationSessionController

    func makeDriver() throws -> BankAutomationDriver {
        let webView = session.prepareWebViewForExecution()
        return WKWebViewAutomationDriver(webView: webView, session: session)
    }
}

final class WKWebViewAutomationDriver: NSObject, BankAutomationDriver {
    private let webView: WKWebView
    private let session: AutomationSessionController
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var pdfContinuation: CheckedContinuation<Data, Error>?
    private var queuedPDFData: Data?
    private var timeoutTask: Task<Void, Never>?

    init(webView: WKWebView, session: AutomationSessionController) {
        self.webView = webView
        self.session = session
        super.init()

        DispatchQueue.main.async {
            webView.navigationDelegate = self
        }
    }

    deinit {
        timeoutTask?.cancel()
        session.finishExecution()
    }

    func navigate(to url: URL) async throws {
        session.markExecutionMessage("Opening bank login...")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                guard self.navigationContinuation == nil else {
                    continuation.resume(throwing: WKWebViewAutomationDriverError.navigationInProgress)
                    return
                }

                self.navigationContinuation = continuation
                self.webView.load(URLRequest(url: url))
            }
        }
    }

    func evaluateBoolean(script: String) async throws -> Bool {
        let value = try await evaluateJavaScript(script)

        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1":
                return true
            case "false", "0", "", "null", "undefined":
                return false
            default:
                throw WKWebViewAutomationDriverError.invalidJavaScriptResult
            }
        }

        throw WKWebViewAutomationDriverError.invalidJavaScriptResult
    }

    func evaluateString(script: String) async throws -> String {
        let value = try await evaluateJavaScript(script)

        if value == nil {
            return ""
        }

        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }

        return String(describing: value!)
    }

    func waitForPDFDownload(timeout: TimeInterval) async throws -> Data {
        session.markExecutionMessage("Waiting for statement PDF...")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DispatchQueue.main.async {
                if let data = self.queuedPDFData {
                    self.queuedPDFData = nil
                    continuation.resume(returning: data)
                    return
                }

                self.pdfContinuation = continuation

                self.timeoutTask?.cancel()
                self.timeoutTask = Task {
                    let seconds = max(timeout, 1)
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

                    DispatchQueue.main.async {
                        guard let pending = self.pdfContinuation else {
                            return
                        }
                        self.pdfContinuation = nil
                        pending.resume(throwing: WKWebViewAutomationDriverError.pdfTimeout)
                    }
                }
            }
        }
    }

    private func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(script) { value, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: value)
                }
            }
        }
    }

    private func completeNavigationIfNeeded(error: Error?) {
        guard let continuation = navigationContinuation else {
            return
        }
        navigationContinuation = nil

        if let error {
            session.markExecutionMessage("Navigation failed.")
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }

    private func startPDFFetch(from url: URL) {
        session.markExecutionMessage("Downloading statement PDF...")

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let sessionConfig = URLSessionConfiguration.ephemeral
            let cookieStorage = HTTPCookieStorage()
            sessionConfig.httpCookieStorage = cookieStorage
            cookies.forEach(cookieStorage.setCookie)

            let session = URLSession(configuration: sessionConfig)
            var request = URLRequest(url: url)
            request.httpShouldHandleCookies = true

            Task {
                do {
                    let (data, response) = try await session.data(for: request)
                    if let http = response as? HTTPURLResponse,
                       !(200...299).contains(http.statusCode) {
                        throw WKWebViewAutomationDriverError.pdfHTTPStatus(http.statusCode)
                    }
                    self.resolvePDF(data)
                } catch {
                    self.failPDF(error)
                }
            }
        }
    }

    private func resolvePDF(_ data: Data) {
        DispatchQueue.main.async {
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.session.markExecutionMessage("PDF captured. Finalizing...")

            if let continuation = self.pdfContinuation {
                self.pdfContinuation = nil
                continuation.resume(returning: data)
                return
            }

            self.queuedPDFData = data
        }
    }

    private func failPDF(_ error: Error) {
        DispatchQueue.main.async {
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.session.markExecutionMessage("PDF download failed.")

            guard let continuation = self.pdfContinuation else {
                return
            }
            self.pdfContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}

extension WKWebViewAutomationDriver: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completeNavigationIfNeeded(error: nil)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        completeNavigationIfNeeded(error: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        completeNavigationIfNeeded(error: error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let mime = navigationResponse.response.mimeType?.lowercased() ?? ""

        if mime.contains("pdf") {
            guard let url = navigationResponse.response.url else {
                decisionHandler(.cancel)
                failPDF(WKWebViewAutomationDriverError.missingPDFURL)
                return
            }

            decisionHandler(.cancel)
            startPDFFetch(from: url)
            return
        }

        decisionHandler(.allow)
    }
}
