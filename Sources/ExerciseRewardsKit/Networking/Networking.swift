import Foundation

/// HTTP 抽象層介面。實作須：只允許 https 到 500.gov.tw、cookie 只存在 App 沙盒容器、
/// 修正官方站 http:// 降級 redirect、絕不 log 敏感內容。
public protocol HTTPClienting: Sendable {
    /// GET 一個頁面，回傳 HTML 字串（自動處理 LBSCookie 握手）。
    func getHTML(path: String) async throws -> String
    /// POST 表單，回傳最終 HTTP 狀態碼與（若有）Location 標頭與 body。
    func postForm(path: String, fields: [(String, String)]) async throws -> HTTPFormResult
    /// GET path，但**不跟隨** redirect，回傳原始、未正規化的絕對 `Location` 標頭字串
    /// （例如導向 S3 presigned URL 的截圖端點）；回應非 3xx 時回傳 `nil`。
    /// 與 `getHTML`/`postForm` 不同：這裡刻意不做 http→https 正規化、不轉成 base-relative
    /// path，因為目的地可能是白名單外的第三方 host（S3），呼叫端只是要把這個絕對網址
    /// 原樣交給 UI 顯示，本 client 並不會連線過去。
    func redirectLocation(path: String) async throws -> String?
    /// multipart/form-data POST（上傳檔案用）：帶若干純文字欄位與一個檔案欄位，
    /// **不跟隨** redirect，回傳狀態碼＋正規化後的 Location＋body。
    func uploadMultipart(
        path: String,
        fields: [(String, String)],
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) async throws -> HTTPFormResult
    /// 清除所有 cookie / session（登出用）。
    func resetSession() async
}

public struct HTTPFormResult: Sendable {
    public let statusCode: Int
    public let location: String?     // 302 的 Location（已正規化為 path）
    public let body: String
    public init(statusCode: Int, location: String?, body: String) {
        self.statusCode = statusCode; self.location = location; self.body = body
    }
}

public enum SiteConfig {
    public static let host = "500.gov.tw"
    public static let base = "https://500.gov.tw/registrant"
}
