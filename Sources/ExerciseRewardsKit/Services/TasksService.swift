import Foundation

/// 「我的任務」服務：取任務清單、組截圖圖片 URL。
public final class TasksService: TasksServicing {
    private let http: HTTPClienting
    private let log = SecureLog(.tasks)

    public init(http: HTTPClienting) {
        self.http = http
    }

    public func fetchTasks() async throws -> [TaskPeriod] {
        let html = try await http.getHTML(path: "/member/tasks")
        let tasks = try TaskParser.parse(html: html)
        log.debug("fetched \(tasks.count) task periods")
        return tasks
    }

    public func screenshotURL(taskID: String) async throws -> URL {
        guard !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.parsing("empty taskID")
        }
        guard let url = URL(string: SiteConfig.base + "/member/screenshot/" + taskID) else {
            throw AppError.parsing("invalid screenshot URL")
        }
        return url
    }

    /// 官方站存放截圖的圖片網域（實測為 S3，網域由**官方站**決定，不是本 App 決定）。
    /// 這是 500.gov.tw 白名單之外唯一被允許的目的地。
    private static let imageHostSuffix = "amazonaws.com"

    /// 截圖圖片網址的准入條件。
    ///
    /// 這個 URL 完全來自官方站回傳的 302 `Location`，屬**不受信任輸入**：官網被入侵、
    /// 或使用者裝置信任了 MITM 憑證（本專案刻意不做 certificate pinning）時，`Location`
    /// 可以是任何東西。原樣交給圖片載入器的話至少有兩種後果：
    /// - `https://attacker.example/1x1.png`：把使用者的 IP、UA、開啟時間送給第三方。
    /// - `https://500.gov.tw/registrant/<任一 GET 端點>`：以同源身分觸發一次 GET。
    ///
    /// 因此這裡把目的地夾成「https + （官方站白名單 或 官方圖片儲存網域）」。
    /// 這是**縱深防禦的第一層**；第二層是 `ScreenshotView` 用一個 cookie-less、
    /// 不落盤的專用 `URLSession` 下載圖片（見該檔）。
    static func isAllowedScreenshotImageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        if URLSessionHTTPClient.isAllowedHost(host) { return true }
        return host == Self.imageHostSuffix || host.hasSuffix("." + Self.imageHostSuffix)
    }

    public func screenshotImageURL(taskID: String) async throws -> URL {
        guard !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.parsing("empty taskID")
        }
        guard let location = try await http.redirectLocation(path: "/member/screenshot/" + taskID) else {
            log.error("screenshot endpoint did not redirect")
            throw AppError.unexpectedResponse(0)
        }
        guard let url = URL(string: location) else {
            throw AppError.parsing("invalid screenshot redirect location")
        }
        guard Self.isAllowedScreenshotImageURL(url) else {
            // host 只進 AppError（遙測端只取 HostClass 分類，不送 host 字串本身）。
            log.error("screenshot redirect pointed at a host outside the image allowlist")
            throw AppError.blockedEgress(url.host ?? "unknown")
        }
        log.debug("resolved screenshot redirect location")
        return url
    }
}
