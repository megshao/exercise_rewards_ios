import Foundation
import SportsRewardsKit

/// 上傳沒成功的原因分類。
///
/// **存在的理由是遙測**：`message` 有可能是官網 `.notice--error` 的**原文**
/// （可能回顯日期、檔名等），絕對不可以被送到第三方。這個列舉是同一件事的封閉分類版本，
/// 讓 `upload_result` 有東西可送，而 `message` 只留給畫面顯示。
public enum UploadFailure: Equatable, Sendable {
    /// 頁面沒有 file 欄位＝當期不在可上傳狀態或本期已上傳過。**這是常態，不是錯誤。**
    case windowClosed
    /// 上傳頁抓不到 `_csrf`。
    case csrfMissing
    /// 官網收下了但退回（停在 200 上傳頁，可能附 `.notice--error`）。
    case siteRejected
    /// 非 200／302 的回應。
    case httpError(status: Int)
}

/// 上傳運動紀錄截圖的結果。
public struct UploadResult: Equatable, Sendable {
    public let submitted: Bool
    public let message: String
    /// 失敗原因分類（成功時為 nil）。只給遙測用，不影響畫面。
    public let failure: UploadFailure?

    public init(submitted: Bool, message: String, failure: UploadFailure? = nil) {
        self.submitted = submitted
        self.message = message
        self.failure = failure
    }
}

/// 上傳運動紀錄服務介面：把使用者從相簿自選的截圖送給官網
/// `multipart POST /member/upload`。
///
/// 隱私注意：`imageData` 只會是使用者主動從相簿選取的截圖（`PhotosPicker`），
/// **絕不是** HealthKit 讀出的數值——HealthKit 步數/距離/運動分鐘只在 HealthView/HomeView
/// 本機顯示用來判斷達標，never leaves the device。
public protocol UploadServicing: Sendable {
    /// - Parameters:
    ///   - taskID: 目前所在期別的 id（僅供 UI 顯示用；後端 `/member/upload` 會自動綁「當前可
    ///     上傳期」，不需帶 UUID）。
    ///   - imageData: 使用者從相簿選取的截圖二進位內容。
    ///   - fileName: 送出時使用的檔名。
    func upload(taskID: String?, imageData: Data, fileName: String) async throws -> UploadResult
}

/// 真正的上傳實作（對應官網的上傳流程）：
/// 1. `GET /member/upload` 取 `_csrf` 並確認頁面確有 file 欄位（`name="screenshot"`）。
///    若當期不在可上傳狀態（非 NOT_UPLOADED、或已上傳過）則頁面沒有表單，回 submitted:false。
/// 2. `multipart POST /member/upload`，file 欄位名 **`screenshot`**，帶 `_csrf`。
/// 3. 成功後端回 302 → /member/tasks；停在 200 頁視為失敗（讀 .notice--error 或給通用訊息）。
/// 與 App 共用同一個已登入的 `HTTPClienting`（session cookie 一路帶著）。
public final class UploadService: UploadServicing, @unchecked Sendable {
    private let http: HTTPClienting

    public init(http: HTTPClienting) {
        self.http = http
    }

    public func upload(taskID: String?, imageData: Data, fileName: String) async throws -> UploadResult {
        // 1. 取上傳頁 → _csrf + 確認有 file 欄位
        let html = try await http.getHTML(path: "/member/upload")
        guard html.contains("name=\"screenshot\"") || html.contains("type=\"file\"") else {
            return UploadResult(submitted: false,
                                message: "目前不在可上傳期間，或本期已上傳過（每期限一次）。",
                                failure: .windowClosed)
        }
        let csrf: String
        do {
            csrf = try CsrfParser.extract(from: html)
        } catch {
            return UploadResult(submitted: false, message: "無法取得上傳授權，請重新登入後再試。",
                                failure: .csrfMissing)
        }

        let mime = fileName.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"

        // 2. multipart POST
        let result = try await http.uploadMultipart(
            path: "/member/upload",
            fields: [("_csrf", csrf)],
            fileField: "screenshot",
            fileName: fileName,
            mimeType: mime,
            fileData: imageData
        )

        // 3. 判讀結果
        if result.statusCode == 302, let loc = result.location, loc.contains("/member/tasks") {
            return UploadResult(submitted: true, message: "已送出，審查約需 5 個工作日。")
        }
        if result.statusCode == 200 {
            // 停在上傳頁：可能是格式/大小/日期不符，官方頁會有錯誤訊息。
            // ⚠️ `msg` 可能是官網原文，只准顯示在畫面上，**不可以進遙測**。
            let msg = Self.errorNotice(in: result.body) ?? "上傳未通過檢查，請確認截圖為原始畫面、含當週日期與運動數據後再試。"
            return UploadResult(submitted: false, message: msg, failure: .siteRejected)
        }
        return UploadResult(submitted: false, message: "上傳失敗（回應碼 \(result.statusCode)），請稍後再試。",
                            failure: .httpError(status: result.statusCode))
    }

    /// 從回應頁抓 `.notice--error` 文字（若有）。
    static func errorNotice(in html: String) -> String? {
        guard let range = html.range(of: #"notice--error[^>]*>\s*([^<]+)"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(html[range])
        // 取 > 之後的可見文字
        if let gt = matched.lastIndex(of: ">") {
            let text = matched[matched.index(after: gt)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return nil
    }
}

/// 佔位實作（保留給 Preview／尚未注入真實 client 的情境）：不發任何網路請求。
public final class UploadServiceStub: UploadServicing, @unchecked Sendable {
    public init() {}

    public func upload(taskID: String?, imageData: Data, fileName: String) async throws -> UploadResult {
        try await Task.sleep(nanoseconds: 300_000_000)
        return UploadResult(submitted: false, message: "（示範模式）未連線，未實際送出。",
                            failure: .windowClosed)
    }
}
