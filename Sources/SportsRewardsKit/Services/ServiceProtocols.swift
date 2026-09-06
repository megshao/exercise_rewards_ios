import Foundation

/// 登入服務介面（登入流程無 OTP）。
public protocol AuthServicing: Sendable {
    /// 執行 access -> login 序列。回傳分流結果。
    func login(_ credentials: LoginCredentials) async throws -> LoginOutcome
    /// 登出並清 session。
    func logout() async throws
}

/// 我的任務服務介面。
public protocol TasksServicing: Sendable {
    /// 取得 14 期任務清單（需已登入）。
    func fetchTasks() async throws -> [TaskPeriod]
    /// 取得某期已上傳截圖的圖片 URL（/member/screenshot/{id} 會 302 到 S3）。
    func screenshotURL(taskID: String) async throws -> URL
    /// 用已登入的 session 打 `/member/screenshot/{id}`，回傳 302 導向的 S3 presigned 圖片
    /// 絕對網址（該網址自帶簽章、無需登入）。
    ///
    /// 實作**必須驗證這個網址**：`Location` 完全由官方站決定，屬不受信任輸入。
    /// 見 `TasksService.isAllowedScreenshotImageURL`（https + 白名單 host），
    /// 以及 `ScreenshotView` 用來下載它的 cookie-less 專用 `URLSession`。
    func screenshotImageURL(taskID: String) async throws -> URL
}

/// 兌換服務介面：列出某期可兌換的商家品項、送出兌換申請。
///
/// ⚠️ `redeem` 會消耗使用者真實的兌換次數且送出後不可更換；官網送出後該期即進入
/// state=REDEEMED，要看券碼還需再走一次簡訊 OTP 驗證（見 `VoucherServicing`），因此
/// `RedeemResult` 只能 best-effort 回報表單是否送出成功。呼叫端（UI）必須先讓使用者
/// 二次確認才可呼叫 `redeem`。
public protocol RedeemServicing: Sendable {
    /// GET 兌換頁並解析出各商家品項清單。
    func options(taskID: String) async throws -> [RedeemOption]
    /// 先 GET 兌換頁取得 `_csrf`，再 POST 送出兌換表單。
    func redeem(taskID: String, vendorId: String, item: String) async throws -> RedeemResult
    /// GET 廠商可兌換商品頁並解析出分類與品項。
    ///
    /// `path` 只接受 `RedeemOption.introPath`——那是 `RedeemParser` 已經驗證過、
    /// 限定在 `/intro/*.html` 的 base-relative path。**不要讓呼叫端自己拼網址**：
    /// 官網的規則是「靜態頁存在才長出連結」，自己拼會拼出 404。
    func vendorIntro(path: String) async throws -> VendorIntro
}

/// 檢視加碼券服務：兌換完成（state=REDEEMED）後，每次要看券碼都要重新走一次簡訊 OTP。
///
/// ⚠️ 合規要求「須本人帳號即時畫面抵用、不得截圖」，因此呼叫端（VoucherView）絕對不可以
/// 快取 `fetchVoucher` 的結果──每次進入畫面都要從 `sendOtp`/`verifyOtp` 重新驗證一次。
public protocol VoucherServicing: Sendable {
    /// 先 GET 券碼頁取得 `_csrf`，再 POST `/member/voucher/{uuid}/resend` 觸發簡訊發送。
    func sendOtp(taskID: String) async throws
    /// 先 GET 券碼頁取得 `_csrf`，再 POST `/member/voucher/{uuid}`（`_csrf`,`otp`）驗證。
    func verifyOtp(taskID: String, otp: String) async throws -> VoucherOtpResult
    /// GET `/member/voucher/{uuid}/view` 並解析出券碼內容。僅在 `verifyOtp` 回傳 `.success` 後呼叫。
    func fetchVoucher(taskID: String) async throws -> Voucher
}
