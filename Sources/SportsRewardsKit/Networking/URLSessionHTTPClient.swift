import Foundation

/// `HTTPClienting` 的預設實作，基於 `URLSession`。
///
/// 安全設計重點：
/// - 只允許連到 `SiteConfig.host`（`500.gov.tw`）及其子網域，其餘一律
///   丟出 `AppError.blockedEgress`（見 `isAllowedHost`）。
/// - Cookie 儲存：預設採**持久化**（app sandbox 容器內、受 iOS 檔案保護），讓登入後的
///   session 能跨 App 重啟續用，不必每次冷啟動都重新登入；`resetSession()`（登出）呼叫
///   `URLSession.reset` 清空 cookie/cache/憑證。頁面內容一律不進 URL cache（可能含個資）。
///   傳 `persistCookies: false` 可退回純記憶體 ephemeral（測試/一次性情境）。
/// - **不自動跟隨 redirect**（每次請求都帶一個只回傳 `nil` 的 delegate），
///   由本類別自行讀取 3xx 狀態碼與 `Location` header、正規化後決定下一步。
///   這同時修正官方站「redirect 的 Location 是 http://」造成 Secure cookie 掉失的問題
///   （正規化後只保留 path，實際請求一律用 https 重新組 URL），也讓
///   LBSCookie 的 `?_cookie_check=1` 握手可以透過一般的 redirect 迴圈自然完成
///   （cookie jar 是同一個 `URLSession`，握手拿到的 cookie 會自動帶進下一跳）。
/// - **Response body 大小上限 2 MB**（`maxResponseBytes`）：超過就丟
///   `AppError.responseTooLarge`，body 不解碼、不交給任何 parser。這是所有
///   HTML parser 共用的止血點，見該常數的說明。
/// - 絕不記錄 cookie / body / 表單欄位；需要時只記錄 path（不含 query）與狀態碼。
public final class URLSessionHTTPClient: HTTPClienting {
    /// 保護用的 redirect 迴圈上限，避免正規化邏輯出錯造成無窮迴圈。
    private static let maxRedirects = 5

    /// response body 的大小上限（2 MB）。
    ///
    /// **這是所有 parser 共用的止血點。** 每個 parser 都是用正規表示式吃官方站回傳的
    /// HTML，而那是不受信任的輸入；只要有任何一條樣式在對抗輸入下退化成超線性，
    /// 一頁惡意 HTML 就能把 cooperative thread pool 卡住（`fetchTasks` 是 nonisolated
    /// async，卡的不是主執行緒，所以不會 watchdog crash——App 只是「所有抓取永遠不回來、
    /// CPU 滿載耗電」直到使用者自己殺掉）。逐條修 regex 是必要的，但擋不住之後新加的
    /// parser；把輸入長度先夾住，才是對「未來的自己」有效的防線。
    ///
    /// 2 MB 的依據：官方頁面實測都在數十 KB（本 repo 的 fixture 最大 4 KB），
    /// 留兩個數量級的餘裕。超過就代表對面不是我們認得的那個站。
    static let maxResponseBytes = 2 * 1024 * 1024

    /// body 超過 `maxResponseBytes` 就丟 `AppError.responseTooLarge`。
    /// 抽成純函式方便單元測試（不必真的下載 2 MB）。
    static func validateBodySize(_ byteCount: Int) throws {
        guard byteCount <= maxResponseBytes else {
            throw AppError.responseTooLarge(byteCount)
        }
    }

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private static let acceptHeader = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

    /// `SiteConfig.base` 的 URL path 部分（例如 `/registrant`），用來把 Location
    /// header 還原成的絕對 path 換算回 `getHTML`/`postForm` 使用的 base-relative path。
    private static let basePathPrefix: String = URL(string: SiteConfig.base)?.path ?? ""

    private let log = SecureLog(.network)
    private let session: URLSession

    public init(persistCookies: Bool = true) {
        // 持久：用 .default（cookie 落在 app 容器、受檔案保護，跨啟動續用）。
        // 非持久：ephemeral（純記憶體）。兩者都不快取頁面內容（可能含個資）。
        let configuration = persistCookies
            ? URLSessionConfiguration.default
            : URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - HTTPClienting

    public func getHTML(path: String) async throws -> String {
        var currentURL = try Self.buildURL(basePath: path)
        var hop = 0
        while true {
            hop += 1
            guard hop <= Self.maxRedirects else {
                throw AppError.unexpectedResponse(-1)
            }
            let request = try Self.buildRequest(url: currentURL, method: "GET")
            let raw = try await send(request)
            if (300..<400).contains(raw.statusCode) {
                guard let location = raw.location else {
                    throw AppError.unexpectedResponse(raw.statusCode)
                }
                let nextPath = try Self.normalizeLocation(location)
                currentURL = try Self.buildURL(basePath: nextPath)
                continue
            }
            guard raw.statusCode == 200 else {
                throw AppError.unexpectedResponse(raw.statusCode)
            }
            return raw.body
        }
    }

    public func postForm(path: String, fields: [(String, String)]) async throws -> HTTPFormResult {
        let url = try Self.buildURL(basePath: path)
        let bodyString = Self.encodeForm(fields)
        let request = try Self.buildRequest(
            url: url,
            method: "POST",
            body: Data(bodyString.utf8),
            contentType: "application/x-www-form-urlencoded; charset=utf-8"
        )
        let raw = try await send(request)
        let normalizedLocation = try raw.location.map { try Self.normalizeLocation($0) }
        return HTTPFormResult(statusCode: raw.statusCode, location: normalizedLocation, body: raw.body)
    }

    public func uploadMultipart(
        path: String,
        fields: [(String, String)],
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) async throws -> HTTPFormResult {
        let url = try Self.buildURL(basePath: path)
        let boundary = "----HuihanBoundary\(UUID().uuidString)"
        let body = Self.encodeMultipart(
            fields: fields, fileField: fileField, fileName: fileName,
            mimeType: mimeType, fileData: fileData, boundary: boundary
        )
        let request = try Self.buildRequest(
            url: url,
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        let raw = try await send(request)
        let normalizedLocation = try raw.location.map { try Self.normalizeLocation($0) }
        return HTTPFormResult(statusCode: raw.statusCode, location: normalizedLocation, body: raw.body)
    }

    public func redirectLocation(path: String) async throws -> String? {
        let url = try Self.buildURL(basePath: path)
        let request = try Self.buildRequest(url: url, method: "GET")
        let raw = try await send(request)
        guard (300..<400).contains(raw.statusCode) else {
            return nil
        }
        // 刻意不呼叫 normalizeLocation：目的地可能是白名單外的 S3 host，
        // 這裡只原樣回傳 Location header，交給呼叫端當純字串使用。
        return raw.location
    }

    public func resetSession() async {
        await withCheckedContinuation { continuation in
            session.reset { continuation.resume() }
        }
    }

    // MARK: - Sending

    private struct RawResponse {
        let statusCode: Int
        let location: String?
        let body: String
    }

    /// 送出單一請求，**不跟隨 redirect**（交給呼叫端讀 3xx + Location 自行處理）。
    /// 連線層錯誤（URLError：斷網、逾時、TLS…）一律包成 `AppError.network`，
    /// 避免原生錯誤逸出到 UI 顯示成「未知錯誤」；暫時性錯誤自動重試一次。
    private func send(_ request: URLRequest) async throws -> RawResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
        } catch let error as URLError {
            if Self.isRetryable(error) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                do {
                    (data, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
                } catch let retryError as URLError {
                    // 不記錄 URL/query，只記錄錯誤碼本身（非個資）。
                    log.error("network error (code \(retryError.code.rawValue)) after retry")
                    throw AppError.network("code \(retryError.code.rawValue)")
                }
            } else {
                log.error("network error (code \(error.code.rawValue))")
                throw AppError.network("code \(error.code.rawValue)")
            }
        }
        guard let http = response as? HTTPURLResponse else {
            throw AppError.unexpectedResponse(-1)
        }
        // 大小上限：先看站方宣告的 Content-Length，再看實收位元組數（有些回應不帶
        // Content-Length，或宣告的跟實際的不符，兩邊都要擋）。任一超標就直接丟錯，
        // **body 不會被解碼成字串、更不會交給任何 parser**。
        if http.expectedContentLength > Int64(Self.maxResponseBytes) {
            log.error("response body too large (declared \(http.expectedContentLength) bytes)")
            throw AppError.responseTooLarge(Int(clamping: http.expectedContentLength))
        }
        do {
            try Self.validateBodySize(data.count)
        } catch {
            log.error("response body too large (\(data.count) bytes)")
            throw error
        }
        log.debug("\(request.httpMethod ?? "GET") \(request.url?.path ?? "") -> \(http.statusCode)")
        return RawResponse(
            statusCode: http.statusCode,
            location: http.value(forHTTPHeaderField: "Location"),
            body: String(data: data, encoding: .utf8) ?? ""
        )
    }

    // MARK: - Pure helpers (unit-testable)

    /// 是否為白名單網域：`SiteConfig.host` 本身或其子網域。
    /// 暫時性連線錯誤（值得重試一次）：逾時、連線中斷、找不到主機、網路斷線等。
    static func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost,
             .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
             .resourceUnavailable, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    static func isAllowedHost(_ host: String) -> Bool {
        let candidate = host.lowercased()
        let root = SiteConfig.host.lowercased()
        return candidate == root || candidate.hasSuffix("." + root)
    }

    /// 把 redirect 的 `Location` header 正規化成 `getHTML`/`postForm` 慣用的
    /// base-relative path（例如 `/login`、`/access?_cookie_check=1`）。
    /// - 若帶有 host 且不在白名單內，丟出 `AppError.blockedEgress`。
    /// - 一律捨棄 scheme（不論站方回傳 http 或 https），實際請求永遠用 https 重組，
    ///   藉此修正官方站 redirect 降級為 http 造成 Secure cookie 掉失的問題。
    static func normalizeLocation(_ location: String) throws -> String {
        guard let components = URLComponents(string: location) else {
            throw AppError.parsing("invalid Location header")
        }
        if let host = components.host, !isAllowedHost(host) {
            throw AppError.blockedEgress(host)
        }

        var path = components.path
        if path.isEmpty {
            path = "/"
        }
        if let query = components.percentEncodedQuery, !query.isEmpty {
            path += "?" + query
        }

        if !basePathPrefix.isEmpty, path.hasPrefix(basePathPrefix) {
            let stripped = String(path.dropFirst(basePathPrefix.count))
            return stripped.isEmpty ? "/" : stripped
        }
        return path.hasPrefix("/") ? path : "/" + path
    }

    /// 用 base-relative path（以 `/` 開頭）組出完整 https URL，並驗證網域白名單。
    static func buildURL(basePath: String) throws -> URL {
        guard basePath.hasPrefix("/") else {
            throw AppError.parsing("path must start with /")
        }
        guard let url = URL(string: SiteConfig.base + basePath) else {
            throw AppError.parsing("invalid path")
        }
        guard url.scheme == "https", let host = url.host, isAllowedHost(host) else {
            throw AppError.blockedEgress(url.host ?? "unknown")
        }
        return url
    }

    private static func buildRequest(
        url: URL,
        method: String,
        body: Data? = nil,
        contentType: String? = nil
    ) throws -> URLRequest {
        guard url.scheme == "https", let host = url.host, isAllowedHost(host) else {
            throw AppError.blockedEgress(url.host ?? "unknown")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body
        return request
    }

    /// `application/x-www-form-urlencoded` 編碼（空白轉 `+`，其餘保留字元皆 percent-encode）。
    /// 組 multipart/form-data 內容：純文字欄位 + 一個檔案欄位。
    static func encodeMultipart(
        fields: [(String, String)],
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        boundary: String
    ) -> Data {
        var body = Data()
        let dashBoundary = "--\(boundary)\r\n"
        func append(_ s: String) { body.append(Data(s.utf8)) }
        for (name, value) in fields {
            append(dashBoundary)
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append(dashBoundary)
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        return body
    }

    static func encodeForm(_ fields: [(String, String)]) -> String {
        fields.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._* ")
        let percentEncoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return percentEncoded.replacingOccurrences(of: " ", with: "+")
    }
}

/// 永遠不跟隨 redirect 的 task delegate；讓呼叫端能自行讀取 3xx 狀態碼與 Location。
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
