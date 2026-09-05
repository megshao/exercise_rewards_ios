import Foundation
import SportsRewardsKit
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

// MARK: - 這個檔案存在的理由
//
// **為什麼要有一層外殼**：Firebase 的 `Analytics.logEvent(_:parameters:)` 收的是
// `[String: Any]?`——任何字串都塞得進去，塞錯了也不會有人告訴你，而且送出去就收不回來。
// 本 App 的整個賣點是「不蒐集、不外傳個資」，所以遙測這條路必須是**唯一且受管制的出口**，
// 比照 `SecureLog` 的設計哲學：呼叫端不能直接碰 SDK，只能透過這裡的型別安全 API。
// 全 App 禁止 `import FirebaseAnalytics` / `import FirebaseCrashlytics`，只有這個檔案可以。
//
// 事件清單、參數、觸發時機與「刻意不埋」的判斷依據都在 `docs/analytics-plan.md`。
// 本檔案的列舉就是那份規格的可執行版本：規格說不能送的東西，這裡在型別上就構造不出來。
//
// **哪些資料絕對不准進來**（新增事件前請逐條對照）：
//   1. 個資：身分證號、出生日期、手機號碼、姓名、email、健保卡號——這三欄是 App 唯一收集的
//      個資，只在登入當下直送 500.gov.tw，任何形式（原文、雜湊、截斷、拼接）都不得進入遙測。
//   2. HealthKit 衍生值：步數、距離、卡路里、運動分鐘，以及**任何由它們算出來的東西**——
//      包含「達標了沒」這種布林值、達標百分比、達標時間、甚至「健康頁是不是 ready 狀態」。
//      衍生的布林值一樣是健康資料，這是本檔案最容易被說服放寬的一條，見下方「為什麼」。
//   3. 官方站識別碼：登入 session / cookie / CSRF token、期別 UUID（`TaskPeriod.id`）、
//      `vendorId` / `itemId`、S3 presigned URL 與其 host。
//   4. 券碼：兌換碼、券序號、條碼內容、OTP、以及任何可以拿去核銷的字串。
//   5. 自由文字：使用者輸入的任何內容、**官網回傳的任何原文**（`.notice--error`、OTP 錯誤
//      訊息、`Voucher.notices`、`remainingText`、商家名／品項名）。官網文字是不可信輸入，
//      可能回顯遮罩後的手機號或日期，一律先分類成本檔案自己定義的封閉列舉再送。
//
// **為什麼 HealthKit 資料（含衍生布林）不可外傳**：這不是我們的偏好，是 Apple 的硬性規定。
// App Store Review Guideline 5.1.3(i) 與 HealthKit 使用條款明訂：從 HealthKit 讀到的資料
// 不得分享給第三方。`goal_met: true` 是從步數算出來的，本質上就是健康資料的一個位元；
// 「匿名彙總」「只送布林」都不能豁免。需要知道「使用者有沒有在用健康分頁」時，
// 只送**流程動作**（按了連結按鈕、看了哪個畫面），不送授權結果、不送達標與否。
//
// **為什麼閘門擋不住這件事、需要你自己守**：`gate` 的敏感樣式掃描只掃字串
// （`Redact.sensitiveKinds`）。`.bool(true)` 與 `.int(8000)` 是掃不到的——所以「不埋」
// 必須發生在寫下 `case` 的那一刻，而不是指望送出前被攔下來。

// MARK: - 值域列舉（analytics-plan §3.1）
//
// 這一整區的存在理由只有一個：**遙測參數的值只能來自封閉集合**。
// 任何「從官網字串轉成分類」的動作都在這裡做完，之後的 API 就再也收不到自由字串。

/// 允許被送出的畫面名稱。**刻意做成封閉列舉**：畫面名不可以是自由字串，
/// 否則哪天有人寫 `screenViewed(name: voucher.code)` 就直接把券碼送出去了。
/// 不要為了方便加 `case custom(String)`——那等於把這道保護整個拆掉。
enum ScreenName: String, Sendable, CaseIterable {
    case onboardingWelcome = "onboarding_welcome"
    case onboardingForm = "onboarding_form"
    case home
    case tasks
    case health
    case wallet
    case profile
    case upload
    case screenshot
    case redeem
    case voucher

    /// GA4 的 `screen_class`。固定為對應的 Swift 型別名（**常數，不是變數**）：
    /// 手動送 `screen_view` 時 Firebase 不會自己填，留空會讓報表上全部併成一列。
    var screenClass: String {
        switch self {
        case .onboardingWelcome, .onboardingForm: return "OnboardingView"
        case .home: return "HomeView"
        case .tasks: return "TasksView"
        case .health: return "HealthView"
        case .wallet: return "WalletView"
        case .profile: return "ProfileView"
        case .upload: return "UploadView"
        case .screenshot: return "ScreenshotView"
        case .redeem: return "RedeemView"
        case .voucher: return "VoucherView"
        }
    }
}

/// 登入是從哪裡觸發的。
enum LoginTrigger: String, Sendable {
    /// Onboarding 表單的「送出並驗證」。
    case onboarding
    /// 冷啟動時的自動登入（`HomeViewModel.bootstrap` → `performLogin(silent: true)`）。
    case auto
    /// 首頁「重新登入」按鈕。
    case manual
}

/// 登入方式。只有一種，做成列舉是為了讓 `method` 參數也進不去自由字串。
enum LoginMethod: String, Sendable {
    case gov500Form = "gov_500_form"
}

/// 失敗原因分類。由 `Telemetry.classify(_:)` 從 `AppError` 映射，**只取 case，不取
/// associated value**——`AppError.blockedEgress` 的 host、`AppError.parsing` 的訊息、
/// `AppError.network` 的字串全部丟掉。
enum FailReason: String, Sendable {
    case invalidCredentials = "invalid_credentials"
    case notRegistered = "not_registered"
    case network
    case siteStatus = "site_status"
    case siteParse = "site_parse"
    case csrfMissing = "csrf_missing"
    case blockedEgress = "blocked_egress"
    case redirectLoop = "redirect_loop"
    /// 解析失敗但**很可能只是 session 過期**（官網 302 到登入頁，回的是登入頁 HTML，
    /// 解析器一樣丟 `parsing`）。冷啟動時的第一次抓取歸這一類，不視為官網改版。
    case sessionProbable = "session_probable"
    case unknown
}

/// 端點**樣板**。永遠是樣板，永遠不含 UUID——這就是它是列舉而不是 `String` 的原因。
enum Endpoint: String, Sendable {
    case access
    case login
    case logout
    case tasks
    case upload
    case screenshot
    case redeem
    case voucher
    case voucherResend = "voucher_resend"
    case voucherView = "voucher_view"
}

/// 官網任務狀態機的分類。對應 `TaskState`，屬 Usage Data，不是個人資料。
enum TaskStateClass: String, Sendable {
    case notStarted = "not_started"
    case open
    case pendingReview = "pending_review"
    case redeemable
    case redeemed
    case unknown

    init(_ state: TaskState) {
        switch state {
        case .notStarted: self = .notStarted
        case .open: self = .open
        case .pendingReview: self = .pendingReview
        case .redeemable: self = .redeemable
        case .redeemed: self = .redeemed
        case .unknown: self = .unknown
        }
    }
}

/// 合作商家分類。**由公開的商家名稱比對出來的分類**，不是官網的 `vendorId`。
/// 分類邏輯與 `RedeemView.VendorLogo` 的品牌色比對同源；認不出來一律 `other`，
/// 絕不 fallback 成原始名稱。
enum Vendor: String, Sendable {
    case familyMart = "family_mart"
    case sevenEleven = "seven_eleven"
    case hilife
    case pxmart
    case other

    /// - Parameter vendorName: 官網回傳的商家名稱。**只用來做分類，不會被送出。**
    init(vendorName: String) {
        if vendorName.contains("全家") { self = .familyMart; return }
        if vendorName.contains("7-11") || vendorName.localizedCaseInsensitiveContains("7-eleven") {
            self = .sevenEleven; return
        }
        if vendorName.contains("萊爾富") { self = .hilife; return }
        if vendorName.contains("全聯") { self = .pxmart; return }
        self = .other
    }
}

/// 被擋下的連線目的地分類。`AppError.blockedEgress(host)` 的 host 字串**不送**——
/// 它可能是 S3 presigned host，內含 bucket 名。
enum HostClass: String, Sendable {
    case govTw = "gov_tw"
    case amazonaws
    case other

    init(host: String) {
        let lower = host.lowercased()
        if lower == "gov.tw" || lower.hasSuffix(".gov.tw") { self = .govTw; return }
        if lower.contains("amazonaws.com") { self = .amazonaws; return }
        self = .other
    }
}

/// 券碼符號集分類。對應 `VoucherFigure.format` 的原始字串，只認已知兩種。
enum BarcodeFormat: String, Sendable {
    case code128
    case qr
    /// 一張券同時含兩種符號集（萊爾富兩段式）。
    case mixed
    case other

    init(format: String) {
        switch format.uppercased() {
        case "CODE_128": self = .code128
        case "QR_CODE": self = .qr
        default: self = .other
        }
    }

    /// 一整張券的符號集分類：兩段不同就是 `mixed`。
    init(figures: [VoucherFigure]) {
        let kinds = Set(figures.map { BarcodeFormat(format: $0.format) })
        if kinds.count == 1, let only = kinds.first {
            self = only
        } else if kinds.isEmpty {
            self = .other
        } else {
            self = .mixed
        }
    }
}

/// Onboarding 表單哪個欄位格式不對。**只說哪個欄位**——不送長度、不送第一碼、
/// 不送使用者輸入的任何字元。四種值都無法反推任何內容。
enum OnboardingField: String, Sendable {
    case empty
    case idNo = "id_no"
    case birthDate = "birth_date"
    case phone
}

/// `tasks_fetch` 是從哪個呼叫點發出的。
enum TasksFetchSource: String, Sendable {
    case homeBootstrap = "home_bootstrap"
    case homeRefresh = "home_refresh"
    case postLogin = "post_login"
    case tasksTab = "tasks_tab"
    case wallet
}

/// 通用二元結果。
enum TelemetryOutcome: String, Sendable {
    case ok
    case error
}

/// 相簿選圖結果。**只送二元結果**：不送檔案大小、尺寸、原格式、壓縮迭代次數、EXIF。
enum UploadPickOutcome: String, Sendable {
    case picked
    case unreadable
}

/// 上傳結果分類。官網 `.notice--error` 的原文一律不送，只歸類成 `site_rejected`。
enum UploadOutcome: String, Sendable {
    case submitted
    /// 頁面沒有 file 欄位＝當期不在可上傳狀態。這是常態，不是錯誤。
    case windowClosed = "window_closed"
    case csrfMissing = "csrf_missing"
    case siteRejected = "site_rejected"
    case httpError = "http_error"
    case network
    case unknown
}

/// 看截圖的最終結果。S3 presigned URL、host、查詢字串一律不送。
enum ScreenshotOutcome: String, Sendable {
    case ok
    case noId = "no_id"
    case urlFailed = "url_failed"
    case imageFailed = "image_failed"
}

/// 兌換清單載入結果。
enum RedeemOptionsOutcome: String, Sendable {
    case ok
    case empty
    case error
}

/// 送出兌換的結果。`RedeemResult.message` 是 App 自己的靜態文案，仍不送（維持無字串原則）。
enum RedeemOutcome: String, Sendable {
    case submitted
    case stayedOnPage = "stayed_on_page"
    case httpError = "http_error"
    case network
    case unknown
}

/// 券碼畫面是從哪裡打開的。
enum VoucherSource: String, Sendable {
    case wallet
    case tasks
    case redeemResult = "redeem_result"
}

/// OTP 驗證結果。**OTP 值絕不進 facade**（型別上也進不來）；官網回頁文字也不送——
/// 官網 OTP 頁的錯誤訊息可能含遮罩後的手機號（「已發送至 09xx***」）。
enum OtpVerifyOutcome: String, Sendable {
    case success
    case wrongCode = "wrong_code"
    case exhausted
    case failed
    case error
}

/// 券碼頁載入結果。券碼、期限、通路、注意事項一律不送。
enum VoucherRevealOutcome: String, Sendable {
    case ok
    case parseError = "parse_error"
    case error
}

/// `site_error` 的種類。
enum SiteErrorKind: String, Sendable {
    case parse
    case csrfMissing = "csrf_missing"
    case unexpectedStatus = "unexpected_status"
    case blockedEgress = "blocked_egress"
    case redirectLoop = "redirect_loop"
}

/// 同意是從哪個介面給的。
enum ConsentSource: String, Sendable {
    /// 首頁的同意卡（尚未實作，見 analytics-plan §6.2）。
    case prompt
    /// 「我的資料 › 安全與隱私」的開關。
    case settings
}

/// 建置管道。Crashlytics custom key 用。
enum BuildChannel: String, Sendable {
    case debug
    case testflight
    case appstore
}

/// Onboarding 目前在第幾步。Crashlytics custom key 用。
enum OnboardingStep: String, Sendable {
    case welcome
    case form
}

/// 登入狀態。**只說「有沒有登入」，不說是誰。**
enum SessionState: String, Sendable {
    case profileMissing = "profile_missing"
    case cachedOnly = "cached_only"
    case loggedIn = "logged_in"
    case loginFailed = "login_failed"
}

/// 任務快取狀態。
enum TasksCacheState: String, Sendable {
    case none
    case fresh
    case stale
}

/// 上傳畫面的 UI 狀態。**不含任何檔案資訊。**
enum UploadStage: String, Sendable {
    case idle
    case picked
    case uploading
    case done
}

/// 券碼畫面的 UI 狀態。**不含 OTP 與券碼。**
enum VoucherStage: String, Sendable {
    case needsOtp = "needs_otp"
    case enterCode = "enter_code"
    case showing
}

// MARK: - 參數值

/// 遙測參數的值。限制成三種純量，讓「參數裡塞了一個結構化的個資物件」在編譯期就不可能發生。
///
/// **沒有 `case string(String)`**——`enumCase` 雖然底層也是字串，但唯一的建構路徑是
/// `AnalyticsValue.code(_:)`，它只收 `RawRepresentable where RawValue == String`，
/// 也就是本檔案上面那一整區封閉列舉的 rawValue。想送自由字串就得先去定義一個列舉，
/// 而定義列舉的當下，就是「這個值域是不是封閉的」被 review 的時候。
enum AnalyticsValue: Sendable {
    /// 某個封閉列舉的 rawValue。請用 `AnalyticsValue.code(_:)` 建構。
    case enumCase(String)
    case int(Int)
    case bool(Bool)

    /// 唯一該用的建構子：從封閉列舉取 rawValue。
    static func code<E: RawRepresentable & Sendable>(_ value: E) -> AnalyticsValue
    where E.RawValue == String {
        .enumCase(value.rawValue)
    }

    /// 轉成 Firebase 收得的型別。
    var firebaseValue: Any {
        switch self {
        case .enumCase(let value): return value
        case .int(let value): return value
        case .bool(let value): return value ? 1 : 0
        }
    }

    /// 只有字串需要過敏感樣式偵測。
    var stringPayload: String? {
        if case .enumCase(let value) = self { return value }
        return nil
    }

    /// Int 的值域檢查用。
    var intPayload: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    /// breadcrumb 用的簡短表示。
    var breadcrumbText: String {
        switch self {
        case .enumCase(let value): return value
        case .int(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        }
    }
}

// MARK: - 事件

/// 全 App 允許送出的事件。要接新事件，**只擴充這個 enum**，不要在別處直接呼叫 SDK。
///
/// 編號對應 `docs/analytics-plan.md` §3.2 的事件表。表上有、這裡沒有的事件都是
/// **刻意不實作**的，理由寫在對應位置的註解裡——不要因為「規格上有」就補回來。
enum AnalyticsEvent: Sendable {
    // E1
    /// 畫面瀏覽。只帶封閉列舉的畫面名，不帶任何畫面上的資料。
    /// **健康頁不帶任何狀態參數**（不區分未授權／已連結）：`ready` 等於「`summary()` 查得到
    /// 資料」，是 HealthKit 授權結果的間接訊號。
    /// **upload / redeem / voucher / screenshot 不帶 taskID。**
    case screenViewed(ScreenName)

    // E2
    /// Onboarding 的「開始使用」。無參數。
    case tutorialBegin

    // E3
    /// Onboarding 表單本機驗證失敗。只送哪個欄位，不送內容。
    case onboardingValidationFailed(field: OnboardingField)

    // E4
    /// 登入成功。憑證完全不經過 facade；不帶 cookie／JSESSIONID／CSRF。
    case login(trigger: LoginTrigger, durationMs: Int)

    // E5
    /// 登入失敗。`netCode` 只有在 `reason == .network` 時才帶，值是 `URLError.Code.rawValue`。
    case loginFailed(trigger: LoginTrigger, reason: FailReason, netCode: Int?, durationMs: Int)

    // E6
    /// 「前往官網註冊」按下（開啟固定 URL）。無參數。
    case registerRedirect

    // E7
    /// Onboarding 完成（真實登入成功路徑）。示範帳號進入的 `finish()` 會被 `isDemo` 閘門擋掉。
    case tutorialComplete

    // E8
    /// 抓任務清單的結果。
    /// `currentPeriod` 是活動週次（全體使用者同一週）不是個人識別；
    /// **不帶 `TaskPeriod.id`（UUID）、不帶 `remainingText` / `uploadedAt`（官網文字）。**
    case tasksFetch(
        source: TasksFetchSource,
        outcome: TelemetryOutcome,
        reason: FailReason?,
        periodCount: Int,
        currentPeriod: Int?,
        currentState: TaskStateClass?,
        hadCache: Bool,
        durationMs: Int
    )

    // E9
    /// 按下「連結 Apple 健康」。**這是 UI 動作，不是 HealthKit 資料**——
    /// 按鈕按下的當下 HealthKit 還沒被呼叫。無參數。
    case healthLinkTap

    // ⛔️ E10 `health_link_result`（授權流程的結果）**刻意不實作**。
    // 規格把它列為「邊界案例，需明知而為」，但本 App 的判準更嚴：健康相關只埋
    // **流程動作**，不埋授權結果。理由：
    //   1. `completed` / `unavailable` / `error` 三選一就是在描述 HealthKit 授權流程的
    //      結果，即使 Apple 設計上不揭露「使用者按了允許還是不允許」，這仍然是
    //      「從 HealthKit API 取得的資訊」，屬 5.1.3(i) 要保護的範圍。
    //   2. `unavailable`（`isHealthDataAvailable() == false`）雖然只是裝置能力，
    //      但混在同一個事件裡就無法在資料端切乾淨。
    //   3. G4（有多少人願意連結健康）用 E9 的次數就估得出來，不值得為它踩灰色地帶。

    // E11
    /// 從相簿選圖的結果。只送二元結果。
    case uploadPick(outcome: UploadPickOutcome)

    // E12
    /// 按下「確認上傳」。`periodIndex` 是活動週次（1–14），不是 taskID。
    case uploadSubmit(periodIndex: Int?)

    // E13
    /// 上傳結果。官網 `.notice--error` 原文不送，只分類。
    case uploadResult(outcome: UploadOutcome, periodIndex: Int?, durationMs: Int)

    // E14
    /// 看截圖的最終結果。
    case screenshotView(outcome: ScreenshotOutcome)

    // E15
    /// 兌換清單載入結果。`optionCount` 是官網目錄大小，非個人資料。
    case redeemOptions(outcome: RedeemOptionsOutcome, reason: FailReason?, optionCount: Int)

    // E16
    /// 點了某商家的「兌換」（確認 alert 出現）。
    case redeemSelect(vendor: Vendor)

    // E17
    /// 確認 alert 按「取消」。
    case redeemCancel(vendor: Vendor)

    // E18
    /// 確認兌換送出。
    case redeemSubmit(vendor: Vendor, periodIndex: Int?)

    // E19
    /// 兌換結果。
    case redeemResult(outcome: RedeemOutcome, vendor: Vendor, durationMs: Int)

    // E20
    /// 券碼畫面出現。不帶 taskID。
    case voucherOpen(source: VoucherSource)

    // E21
    /// 發送簡訊 OTP 的結果。發送對象手機號在官網 session 裡，App 沒碰。
    case voucherOtpSend(outcome: TelemetryOutcome, reason: FailReason?, isResend: Bool)

    // E22
    /// OTP 驗證結果。`remaining`（0–3）只在 `wrongCode` 時帶。
    case voucherOtpVerify(outcome: OtpVerifyOutcome, remaining: Int?)

    // E23
    /// 券碼載入結果。`figureCount` 與 `format` 是**券種結構**（萊爾富兩段式），不是券碼。
    case voucherReveal(outcome: VoucherRevealOutcome, figureCount: Int, format: BarcodeFormat)

    // E24
    /// 條碼畫不出來。新的未知 format 出現＝官網改版訊號。
    case barcodeRenderFailed(format: BarcodeFormat)

    // E25
    /// 儲存個資到 Keychain 的結果。`draft` 不進 facade。
    case profileSave(outcome: TelemetryOutcome)

    // E26
    /// 「立即清除本機資料」。在真的清除之前送，送完立刻重置 app instance ID。
    case localDataClear

    // E27
    /// 官網改版訊號。與各 `*_result` 事件並存。
    case siteError(endpoint: Endpoint, kind: SiteErrorKind, status: Int, hostClass: HostClass?)

    // E28
    /// 使用者開啟匿名統計。**唯一一個「同意後的第一個事件」。**
    ///
    /// 沒有對應的 `consent_revoked`：使用者剛說「不要」，再送一筆等於沒聽到。
    /// 舊版外殼曾經用 `bypassingUserPreference` 在關閉時補送一筆，那條路已經整個拆掉。
    case consentGranted(source: ConsentSource)

    /// Firebase 事件名。snake_case、字母開頭、≤ 40 字元、不用 `firebase_`／`google_`／`ga_` 前綴。
    var name: String {
        switch self {
        case .screenViewed: return AnalyticsEventScreenView
        case .tutorialBegin: return AnalyticsEventTutorialBegin
        case .onboardingValidationFailed: return "onboarding_validation_failed"
        case .login: return AnalyticsEventLogin
        case .loginFailed: return "login_failed"
        case .registerRedirect: return "register_redirect"
        case .tutorialComplete: return AnalyticsEventTutorialComplete
        case .tasksFetch: return "tasks_fetch"
        case .healthLinkTap: return "health_link_tap"
        case .uploadPick: return "upload_pick"
        case .uploadSubmit: return "upload_submit"
        case .uploadResult: return "upload_result"
        case .screenshotView: return "screenshot_view"
        case .redeemOptions: return "redeem_options"
        case .redeemSelect: return "redeem_select"
        case .redeemCancel: return "redeem_cancel"
        case .redeemSubmit: return "redeem_submit"
        case .redeemResult: return "redeem_result"
        case .voucherOpen: return "voucher_open"
        case .voucherOtpSend: return "voucher_otp_send"
        case .voucherOtpVerify: return "voucher_otp_verify"
        case .voucherReveal: return "voucher_reveal"
        case .barcodeRenderFailed: return "barcode_render_failed"
        case .profileSave: return "profile_save"
        case .localDataClear: return "local_data_clear"
        case .siteError: return "site_error"
        case .consentGranted: return "consent_granted"
        }
    }

    var parameters: [String: AnalyticsValue] {
        switch self {
        case .screenViewed(let screen):
            return [
                AnalyticsParameterScreenName: .code(screen),
                AnalyticsParameterScreenClass: .enumCase(screen.screenClass),
            ]

        case .tutorialBegin, .registerRedirect, .tutorialComplete, .healthLinkTap, .localDataClear:
            return [:]

        case .onboardingValidationFailed(let field):
            return ["field": .code(field)]

        case .login(let trigger, let durationMs):
            return [
                AnalyticsParameterMethod: .code(LoginMethod.gov500Form),
                "trigger": .code(trigger),
                "duration_ms": .int(Telemetry.clampDuration(durationMs)),
            ]

        case .loginFailed(let trigger, let reason, let netCode, let durationMs):
            var params: [String: AnalyticsValue] = [
                "trigger": .code(trigger),
                "reason": .code(reason),
                "duration_ms": .int(Telemetry.clampDuration(durationMs)),
            ]
            // net_code 只在 network 失敗時有意義，且只可能是 URLError 的整數碼。
            if reason == .network, let netCode { params["net_code"] = .int(netCode) }
            return params

        case .tasksFetch(let source, let outcome, let reason, let periodCount,
                         let currentPeriod, let currentState, let hadCache, let durationMs):
            var params: [String: AnalyticsValue] = [
                "source": .code(source),
                "outcome": .code(outcome),
                "period_count": .int(periodCount),
                "had_cache": .bool(hadCache),
                "duration_ms": .int(Telemetry.clampDuration(durationMs)),
            ]
            if let reason { params["reason"] = .code(reason) }
            if let currentPeriod { params["current_period"] = .int(currentPeriod) }
            if let currentState { params["current_state"] = .code(currentState) }
            return params

        case .uploadPick(let outcome):
            return ["outcome": .code(outcome)]

        case .uploadSubmit(let periodIndex):
            guard let periodIndex else { return [:] }
            return ["period_index": .int(periodIndex)]

        case .uploadResult(let outcome, let periodIndex, let durationMs):
            var params: [String: AnalyticsValue] = [
                "outcome": .code(outcome),
                "duration_ms": .int(Telemetry.clampDuration(durationMs)),
            ]
            if let periodIndex { params["period_index"] = .int(periodIndex) }
            return params

        case .screenshotView(let outcome):
            return ["outcome": .code(outcome)]

        case .redeemOptions(let outcome, let reason, let optionCount):
            var params: [String: AnalyticsValue] = [
                "outcome": .code(outcome),
                "option_count": .int(optionCount),
            ]
            if let reason { params["reason"] = .code(reason) }
            return params

        case .redeemSelect(let vendor), .redeemCancel(let vendor):
            return ["vendor": .code(vendor)]

        case .redeemSubmit(let vendor, let periodIndex):
            var params: [String: AnalyticsValue] = ["vendor": .code(vendor)]
            if let periodIndex { params["period_index"] = .int(periodIndex) }
            return params

        case .redeemResult(let outcome, let vendor, let durationMs):
            return [
                "outcome": .code(outcome),
                "vendor": .code(vendor),
                "duration_ms": .int(Telemetry.clampDuration(durationMs)),
            ]

        case .voucherOpen(let source):
            return ["source": .code(source)]

        case .voucherOtpSend(let outcome, let reason, let isResend):
            var params: [String: AnalyticsValue] = [
                "outcome": .code(outcome),
                "is_resend": .bool(isResend),
            ]
            if let reason { params["reason"] = .code(reason) }
            return params

        case .voucherOtpVerify(let outcome, let remaining):
            var params: [String: AnalyticsValue] = ["outcome": .code(outcome)]
            // remaining 是官網給的「還可以再試幾次」，值域 0–3；只在 wrongCode 時帶。
            if outcome == .wrongCode, let remaining, (0...3).contains(remaining) {
                params["remaining"] = .int(remaining)
            }
            return params

        case .voucherReveal(let outcome, let figureCount, let format):
            return [
                "outcome": .code(outcome),
                "figure_count": .int(figureCount),
                "format": .code(format),
            ]

        case .barcodeRenderFailed(let format):
            return ["format": .code(format)]

        case .profileSave(let outcome):
            return ["outcome": .code(outcome)]

        case .siteError(let endpoint, let kind, let status, let hostClass):
            var params: [String: AnalyticsValue] = [
                "endpoint": .code(endpoint),
                "kind": .code(kind),
                "status": .int(status),
            ]
            if let hostClass { params["host_class"] = .code(hostClass) }
            return params

        case .consentGranted(let source):
            return ["source": .code(source)]
        }
    }
}

// MARK: - 使用者屬性

/// **本 App 不設定任何 user property，也不呼叫 `setUserID`。**
///
/// 這個列舉刻意留成空的（無法被建構），用來擋掉「順手加一個」的念頭並解釋原因：
///
/// - user property 會**附加在往後所有事件上**，是最容易不小心變成準識別碼的地方：
///   幾個布林的組合就足以把裝置切成很小的群，跟「匿名」的承諾方向相反。
/// - 舊版外殼有 `healthAuthorizationGranted(Bool)`。那是**HealthKit 授權結果**，
///   還會被黏在每一個事件上，等於把健康資料的一個位元散佈到整個資料集，
///   直接踩 Guideline 5.1.3(i)。已移除，不要以任何形式加回來。
/// - 舊版另有 `onboardingCompleted(Bool)`。它本身無害，但 analytics-plan §2.3 是
///   「不設定任何 user property」，而漏斗用 `tutorial_begin` / `tutorial_complete`
///   兩個事件就算得出來，不需要常駐屬性。
enum UserProperty: Sendable {}

// MARK: - 當機報告

/// 當機報告上的自訂鍵（analytics-plan §5.2）。同樣封閉，避免有人拿 crash key
/// 當成「順手記一下使用者是誰」的地方。
///
/// **禁止成為 custom key 的東西**（列出來讓後人不用再想一次）：`Profile` 任何欄位、
/// taskID／UUID、`vendorId`／`itemId`、OTP、券碼、S3 URL、cookie／CSRF、
/// `HealthSummary` 任何數值、**健康連結狀態**、圖片資訊、官網任何文字、
/// Analytics 的 app instance ID。
enum CrashKey: Sendable {
    case buildChannel(BuildChannel)
    /// 理論上回報時恆為 false（示範模式已關閉收集）；保留作為不變量檢查——
    /// 若在後台看到 true，代表閘門失效了。
    case isDemoMode(Bool)
    case screen(ScreenName)
    case onboardingStep(OnboardingStep)
    case sessionState(SessionState)
    case tasksCache(TasksCacheState)
    /// 活動週次 1–14。
    case currentPeriod(Int)
    case currentState(TaskStateClass)
    case lastEndpoint(Endpoint)
    case lastStatus(Int)
    case uploadStage(UploadStage)
    case voucherStage(VoucherStage)
    case consentSource(ConsentSource)

    var name: String {
        switch self {
        case .buildChannel: return "build_channel"
        case .isDemoMode: return "demo_mode"
        case .screen: return "screen"
        case .onboardingStep: return "onboarding_step"
        case .sessionState: return "session_state"
        case .tasksCache: return "tasks_cache"
        case .currentPeriod: return "current_period"
        case .currentState: return "current_state"
        case .lastEndpoint: return "last_endpoint"
        case .lastStatus: return "last_status"
        case .uploadStage: return "upload_stage"
        case .voucherStage: return "voucher_stage"
        case .consentSource: return "consent_source"
        }
    }

    var value: AnalyticsValue {
        switch self {
        case .buildChannel(let channel): return .code(channel)
        case .isDemoMode(let demo): return .bool(demo)
        case .screen(let screen): return .code(screen)
        case .onboardingStep(let step): return .code(step)
        case .sessionState(let state): return .code(state)
        case .tasksCache(let state): return .code(state)
        case .currentPeriod(let index): return .int(index)
        case .currentState(let state): return .code(state)
        case .lastEndpoint(let endpoint): return .code(endpoint)
        case .lastStatus(let status): return .int(status)
        case .uploadStage(let stage): return .code(stage)
        case .voucherStage(let stage): return .code(stage)
        case .consentSource(let source): return .code(source)
        }
    }
}

/// 非致命錯誤的網域（analytics-plan §5.4）。
enum TelemetryDomain: String, Sendable {
    /// 官網改版訊號。
    case siteDrift = "SiteDrift"
    /// 本機儲存問題。
    case storage = "Storage"
    /// 本機繪製問題。
    case render = "Render"
}

/// 非致命錯誤的具體項目。`code` 就是這裡的 `intCode`，Crashlytics 用 (domain, code) 分群。
///
/// **N2 `SiteDrift.tasks_partial` 的 `raw_state` 沒有實作**：規格把它列為
/// 「唯一放行的非 enum 字串」（由 regex `[A-Z_]+` 約束），但那需要讓 `TelemetryError`
/// 的 userInfo 接受 `String`，等於在唯一的出口上開一個字串洞。本 App 的判準是
/// 「官網回傳的原文一律不送」，沒有例外；改用 `unknown_states` 計數與 `missing_id`
/// 布林達到同樣的警報效果（知道「官網出現了我們不認得的狀態」就夠觸發人工去看一眼）。
enum TelemetryIssue: String, Sendable {
    // SiteDrift
    case tasksNoCards = "tasks_no_cards"
    case tasksPartial = "tasks_partial"
    case tasksParse = "tasks_parse"
    case redeem = "redeem"
    case csrfMissing = "csrf_missing"
    case voucherView = "voucher_view"
    case voucherNotice = "voucher_notice"
    case auth = "auth"
    case http = "http"
    case egress = "egress"
    case upload = "upload"
    case screenshotRedirect = "screenshot_redirect"
    // Storage
    case keychain = "keychain"
    case profileDecode = "profile_decode"
    case cacheDecode = "cache_decode"
    // Render
    case barcode = "barcode"

    var domain: TelemetryDomain {
        switch self {
        case .keychain, .profileDecode, .cacheDecode: return .storage
        case .barcode: return .render
        default: return .siteDrift
        }
    }

    /// Crashlytics 的 `code`。**不要重排**——重排會讓歷史議題對不上。
    var intCode: Int {
        switch self {
        case .tasksNoCards: return 1
        case .tasksPartial: return 2
        case .tasksParse: return 3
        case .redeem: return 4
        case .csrfMissing: return 5
        case .voucherView: return 6
        case .voucherNotice: return 7
        case .auth: return 8
        case .http: return 9
        case .egress: return 10
        case .upload: return 11
        case .screenshotRedirect: return 12
        case .keychain: return 20
        case .profileDecode: return 21
        case .cacheDecode: return 22
        case .barcode: return 30
        }
    }

    /// 後台看得懂的標題。**這是本檔案自己寫死的常數**，不是任何外部字串。
    var label: String { "\(domain.rawValue).\(rawValue)" }
}

// MARK: - 遙測出口

/// 全 App 唯一的遙測出口。
///
/// 所有方法都可以從任何執行緒呼叫；Firebase 的 `Analytics` 與 `Crashlytics` 對此是安全的，
/// 而本外殼自己的狀態只有 `UserDefaults` 旗標與幾個由 `NSLock` 保護的變數。
enum Telemetry {
    /// 使用者偏好的 `UserDefaults` 鍵。ProfileView 的 Toggle 直接綁這個鍵。
    static let preferenceKey = "telemetryEnabled"

    /// **預設關閉（opt-in）**。
    ///
    /// 這支 App 的承諾是「個資不蒐集、不外傳」，且統計要送出去之前使用者必須先看到並同意；
    /// 預設開啟會讓「第一次啟動、還沒看到任何開關」的當下就已經送出 `first_open`。
    /// Info.plist 的 `FIREBASE_ANALYTICS_COLLECTION_ENABLED` /
    /// `FirebaseCrashlyticsCollectionEnabled` 也是 false，兩邊要一起改才有意義。
    static let defaultEnabled = false

    /// **每一個整數參數的合法值域白名單。**
    ///
    /// **為什麼需要**：`gate` 的敏感樣式掃描只掃字串（`Redact.sensitiveKinds`），
    /// `.int` 完全不掃。券碼、期別 UUID 的數字部分、Unix 時間戳（毫秒約 1.7×10¹²）、
    /// 6 碼 OTP、任何識別碼只要被寫成 `.int(...)` 就會直接穿過所有防線送出去。
    ///
    /// **為什麼是白名單而不是一個全域範圍**：全域範圍擋得掉時間戳，擋不掉 6 碼 OTP
    /// （它跟「600000 毫秒」長得一樣）。本 App 用到的整數其實每一個都有很窄的自然值域
    /// （期數 1–14、剩餘次數 0–3、HTTP 狀態碼、`OSStatus`…），把它們一條一條寫下來，
    /// 「新增一個整數參數」就必須順手回答「它的值域是什麼」——那正是該被 review 的問題。
    ///
    /// 表上沒有的鍵一律擋下並在 DEBUG assert。
    static let allowedIntRanges: [String: ClosedRange<Int>] = [
        // 事件參數
        "duration_ms": 0...maxDurationMs,
        "net_code": -99_999...0,          // URLError.Code.rawValue 皆為負
        "status": -1...599,               // HTTP 狀態碼；-1 = 不明
        "period_count": 0...14,           // 活動共 14 期
        "current_period": 1...14,
        "period_index": 1...14,
        "option_count": 0...200,          // 官網兌換目錄大小
        "remaining": 0...3,               // OTP 還可以再試幾次（官網給 3 次）
        "figure_count": 0...5,            // 一張券最多幾段條碼（萊爾富是 2）
        "unknown_states": 0...14,
        // 非致命錯誤的 userInfo
        "os_status": -99_999...99_999,    // Keychain OSStatus，例如 -25308
        // Crashlytics custom key（鍵名即參數名，見 setCrashKey）
        "last_status": -1...599,
    ]

    /// `duration_ms` 的上限（10 分鐘）。同時避免有人誤把時間戳當耗時傳進來。
    static let maxDurationMs = 600_000

    private static let log = SecureLog(.security)

    /// Firebase 是否真的初始化成功。沒有 GoogleService-Info.plist 時會是 false，
    /// 所有 API 都變成 no-op。
    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var isConfigured = false
    /// 本次 App session 已回報過的非致命錯誤（`issue|endpoint`），用來去重。
    nonisolated(unsafe) private static var reportedIssues: Set<String> = []

    // MARK: 初始化

    /// 在 App 啟動時呼叫一次（`HuihanApp.init()`）。
    ///
    /// **這裡刻意什麼都不做，除非使用者已經同意。**
    ///
    /// 為什麼是 lazy（這不是效能考量，是承諾的結構性基礎）：
    ///
    /// 1. `site/privacy.html` §5 寫的是「App 安裝好之後，這項功能是關閉的，**一個位元組都
    ///    不會送出去**」。要讓這句話為真，不能只靠「有 configure，但兩個 collection 旗標
    ///    都關著」——`FirebaseApp.configure()` 一旦執行，Firebase Installations 就會去要
    ///    一組 installation ID，**即使 Analytics 與 Crashlytics 的收集旗標都是 false**
    ///    （firebase-ios-sdk issue #15513，SDK 12.6.0 實測；我們用 12.18.0，
    ///    沒有理由假設它已經改掉）。那是一次往 `firebaseinstallations.googleapis.com`
    ///    的連線，也就是一個位元組以上。
    /// 2. **使用者驗得到。** iOS 內建「設定 › 隱私權與安全性 › App 隱私權報告」會列出這支
    ///    App 連過的網域。只要有 Google 網域出現，上面那句承諾就當場被使用者本人推翻——
    ///    而且是最糟的那種被推翻方式。
    /// 3. 因此把界線放在**執行與否**，而不是**旗標開關**：開關關著的時候，Firebase 的程式碼
    ///    一行都不會跑。這讓「零連線」從「我們相信 SDK 會尊重旗標」變成一件結構性的事實。
    ///
    /// 要接受的代價：Crashlytics 只抓得到 opt-in 之後的當機，同意之前的當機永遠看不到。
    /// 這本來就是 opt-in 的語意，不為了多幾筆當機報告去妥協。
    static func configure() {
        // 示範模式（App Store 審查員走的路）也一併擋掉：審查員從未同意，
        // 而且「送審版本在示範模式下對 Google 零連線」是 Review Notes 寫得出來的一句話。
        guard isUserEnabled, !isDemoModeActive else {
            log.debug("遙測未同意或處於示範模式，完全不初始化 Firebase（一行 SDK 程式碼都不執行）")
            return
        }
        startFirebase()
    }

    /// 真正接觸 Firebase 的唯一入口。呼叫端必須自己先確認使用者已同意。
    ///
    /// **絕不 crash**：`FirebaseApp.configure()` 在找不到 `GoogleService-Info.plist` 時會
    /// `fatalError`，所以這裡**先自己檢查檔案存在**，不存在就完全跳過初始化。
    /// 這讓 repo 在不含真實設定檔的情況下仍然可以 clone、build、跑起來。
    @discardableResult
    private static func startFirebase() -> Bool {
        stateLock.lock()
        let already = isConfigured
        stateLock.unlock()
        if already { return true }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            log.debug("找不到 GoogleService-Info.plist，跳過 Firebase 初始化（遙測全程 no-op）")
            return false
        }

        FirebaseApp.configure()
        stateLock.lock()
        isConfigured = true
        stateLock.unlock()

        // Info.plist 已經把兩邊的預設收集都關掉了；這裡依使用者當前偏好把狀態同步一次，
        // 讓「使用者上次選的」在每次冷啟動都確實生效，而不是依賴 SDK 自己的持久化。
        applyCollectionFlags(enabled: isUserEnabled)
        setCrashKey(.buildChannel(currentBuildChannel))
        setCrashKey(.isDemoMode(isDemoModeActive))
        log.debug("Firebase 已初始化（使用者已同意），遙測偏好=\(isUserEnabled)")
        return true
    }

    private static var configured: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return isConfigured
    }

    /// 建置管道。TestFlight 的 receipt 檔名固定是 `sandboxReceipt`。
    private static var currentBuildChannel: BuildChannel {
        #if DEBUG
        return .debug
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return .testflight
        }
        return .appstore
        #endif
    }

    // MARK: 使用者偏好

    /// 使用者是否同意傳送匿名使用統計。
    static var isUserEnabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? defaultEnabled
    }

    /// 使用者在「我的資料 › 安全與隱私」切換開關時呼叫。
    ///
    /// **關閉時不送任何事件。** 舊版外殼會在關閉那一刻用 `bypassingUserPreference`
    /// 補送一筆 `telemetry_preference_changed(false)`，理由是「否則拿不到 opt-out 率」。
    /// 那條路已經整個移除：使用者剛按下「不要」，還硬送一筆出去，等於沒聽到。
    /// 對一支把隱私當賣點的 App 來說，這個數字不值得用「違背同意」去換。
    ///
    /// **「打開」是這支 App 第一次接觸 Firebase 的時刻**（見 `configure()` 的說明）：
    /// 在此之前 `FirebaseApp.configure()` 從來沒有被執行過，所以裝置對 Google 的網域
    /// 一次連線都沒發生過——這正是「開關關著時零連線」這句承諾成立的方式。
    ///
    /// **「關掉」關不掉已經初始化的 process**：Firebase 沒有 `deconfigure()`，本次執行期間
    /// SDK 仍然活著（只是收集旗標關了、instance ID 重置了、未送出的報告刪了）。
    /// 真正回到「一行都不跑」要等**下一次冷啟動**——那時 `configure()` 會看到偏好是關的，
    /// 直接跳過。這一點必須誠實寫出來，不要讓 UI 文案暗示關掉就等於從沒裝過。
    static func setUserEnabled(_ enabled: Bool, source: ConsentSource = .settings) {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)

        if enabled {
            // 示範模式下**不初始化**，即使使用者（或審查員）把開關打開。
            //
            // 為什麼這道守衛非有不可：`configure()` 的 demo 守衛只在冷啟動生效，
            // 這裡是另一條進入 Firebase 的路。而審查員正是唯一一群一定會走示範模式、
            // 又可能順手撥開關的人——少了這行，光是 `FirebaseApp.configure()` 引發的
            // Installations 連線就足以推翻 README 與隱私權政策寫下的
            // 「示範模式下對 Google 零連線」。偏好本身照樣記下來，離開示範模式時
            // `demoModeDidChange()` 會補做初始化。
            guard !isDemoModeActive else {
                log.debug("示範模式：記下遙測偏好但不初始化 Firebase")
                return
            }
            // 這一行是整支 App 第一次執行 Firebase 的程式碼。
            startFirebase()
            applyCollectionFlags(enabled: true)
            setCrashKey(.consentSource(source))
            // E28：同意後的第一個事件，必須在 setAnalyticsCollectionEnabled(true) 之後。
            logEvent(.consentGranted(source: source))
        } else {
            applyCollectionFlags(enabled: false)
            // 關閉：重置 app instance ID、丟掉還沒送出的當機報告。
            resetCollectedData()
        }
        log.debug("遙測偏好改為 \(enabled)")
    }

    /// 「立即清除本機資料」時呼叫：把偏好重設回預設值（opt-in ⇒ 關閉）並立刻停止收集。
    ///
    /// 呼叫端必須**先送 E26 `local_data_clear`**（在偏好還開著的時候）再呼叫這裡，
    /// 順序見 analytics-plan §6.4。
    static func resetPreference() {
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        applyCollectionFlags(enabled: defaultEnabled)
        resetCollectedData()
        log.debug("遙測偏好已重設為預設值（\(defaultEnabled)）")
    }

    /// 重置 app instance ID 並丟掉未送出的當機報告。
    private static func resetCollectedData() {
        guard configured else { return }
        Analytics.resetAnalyticsData()
        Crashlytics.crashlytics().deleteUnsentReports()
    }

    /// 同步 SDK 兩邊的收集開關。示範模式下一律關閉，不管使用者偏好是什麼。
    private static func applyCollectionFlags(enabled: Bool) {
        guard configured else { return }
        let allowed = enabled && !isDemoModeActive
        Analytics.setAnalyticsCollectionEnabled(allowed)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(allowed)
    }

    /// 進出示範模式時呼叫，讓 SDK 的收集狀態跟著切換。
    ///
    /// 離開示範模式且使用者本來就同意時，這裡會補做一次 `startFirebase()`——
    /// 因為冷啟動時若正處於示範模式，`configure()` 是刻意跳過的。
    static func demoModeDidChange() {
        if isUserEnabled, !isDemoModeActive { startFirebase() }
        applyCollectionFlags(enabled: isUserEnabled)
        setCrashKey(.isDemoMode(isDemoModeActive))
    }

    // MARK: 隱私閘門

    /// 示範模式旗標。直接讀 `UserDefaults`（`AppEnvironmentStore` 也是寫這個鍵），
    /// 避免為了讀一個布林把這裡綁到 `@MainActor`。
    ///
    /// **必須每次呼叫時動態讀**，不能在 init 時快取：ViewModel 的 `configure()` 有
    /// `guard self.auth == nil` 守衛，切進示範模式後 ViewModel 仍握著舊環境。
    private static var isDemoModeActive: Bool {
        UserDefaults.standard.bool(forKey: DemoMode.storageKey)
    }

    /// 被擋下來的原因。回傳 nil 代表通過。
    private enum Block {
        case notConfigured
        case demoMode
        case screenshotMode
        case userDisabled
        case sensitive(field: String, kinds: Set<Redact.SensitiveKind>)
        case outOfRange(field: String, value: Int)

        var reason: String {
            switch self {
            case .notConfigured: return "Firebase 未初始化"
            case .demoMode: return "示範模式"
            case .screenshotMode: return "截圖模式"
            case .userDisabled: return "使用者已關閉遙測"
            case .sensitive(let field, let kinds):
                let list = kinds.map(\.rawValue).sorted().joined(separator: ",")
                return "欄位 \(field) 命中敏感樣式 [\(list)]"
            case .outOfRange(let field, let value):
                if let range = allowedIntRanges[field] {
                    return "欄位 \(field) 的整數 \(value) 超出允許值域 \(range)"
                }
                return "欄位 \(field) 是未登記的整數參數（值 \(value)）"
            }
        }

        /// 是不是「程式寫錯了」而不是「預期中的正常狀態」。
        var isProgrammerError: Bool {
            switch self {
            case .sensitive, .outOfRange: return true
            case .notConfigured, .demoMode, .screenshotMode, .userDisabled: return false
            }
        }
    }

    /// 送出前的四道閘門：初始化 → 開關（示範模式／截圖模式／使用者偏好）→ 內容掃描 → 值域檢查。
    /// 這是**機制**而不是自律：呼叫端沒有繞過它的路。
    private static func gate(
        eventName: String,
        parameters: [String: AnalyticsValue]
    ) -> Block? {
        // 順序有意義：**先問「該不該送」，再問「送得出去嗎」**。
        // 四道都必須通過，所以順序不影響安全性，但影響 debug log 的資訊量——
        // 把 `configured` 放最前面的話，沒有 GoogleService-Info.plist 的開發／CI 環境會讓
        // 每一筆都回報「Firebase 未初始化」，於是「同意閘門到底有沒有在擋」就永遠驗不到。
        // 現在的順序讓 `SecureLog` 直接說出是哪一道擋下來的。
        //
        // 示範模式排在使用者偏好前面：審查員可能自己把開關打開，仍然一個字都不能送。
        guard !isDemoModeActive else { return .demoMode }
        // 截圖模式：fastlane／XCUITest 跑出來的事件不該進正式資料。
        guard !ScreenshotMode.isEnabled else { return .screenshotMode }
        guard isUserEnabled else { return .userDisabled }
        guard configured else { return .notConfigured }

        // 事件名本身也掃一次。名稱來自封閉列舉，理論上不可能中；中了代表有人改壞了 enum。
        let nameKinds = Redact.sensitiveKinds(in: eventName)
        if !nameKinds.isEmpty { return .sensitive(field: "event_name", kinds: nameKinds) }

        for (key, value) in parameters {
            if let text = value.stringPayload {
                let kinds = Redact.sensitiveKinds(in: text)
                if !kinds.isEmpty { return .sensitive(field: key, kinds: kinds) }
            }
            // 樣式掃描掃不到整數，所以整數改用「每個鍵各自的值域白名單」把關
            // （見 allowedIntRanges 的說明）。表上沒有的鍵一律擋。
            if let number = value.intPayload {
                guard let range = allowedIntRanges[key], range.contains(number) else {
                    return .outOfRange(field: key, value: number)
                }
            }
            let keyKinds = Redact.sensitiveKinds(in: key)
            if !keyKinds.isEmpty { return .sensitive(field: "key:\(key)", kinds: keyKinds) }
        }
        return nil
    }

    /// 處理被擋下來的事件。
    ///
    /// **敏感樣式／值域違規時在 DEBUG build 直接 `assertionFailure`**：這種情況一定是程式
    /// 寫錯了（某個個資或識別碼被接到遙測參數上），要在開發期就爆出來，而不是在正式版
    /// 靜靜地被丟掉——靜靜丟掉會讓下一個人以為「反正閘門會擋」而放心亂接。
    /// 其他原因（未初始化／示範模式／截圖模式／使用者關閉）是**預期中的正常狀態**，只記 debug log。
    private static func handle(_ block: Block, eventName: String) {
        if block.isProgrammerError {
            #if DEBUG
            assertionFailure(
                "遙測事件 \(eventName) 夾帶疑似個資或識別碼（\(block.reason)）。"
                + "請改成封閉列舉，或到 allowedIntRanges 為這個鍵登記一個明確的窄值域；"
                + "不要為了讓事件送得出去而放寬 Redact 的樣式。"
            )
            #endif
            log.error("遙測事件遭攔截：\(eventName) — \(block.reason)")
        } else {
            log.debug("遙測事件未送出：\(eventName) — \(block.reason)")
        }
    }

    // MARK: 送出

    /// 送出一個事件。被閘門擋下時什麼事都不會發生（DEBUG 下敏感樣式會 assert）。
    static func logEvent(_ event: AnalyticsEvent) {
        let parameters = event.parameters
        if let block = gate(eventName: event.name, parameters: parameters) {
            handle(block, eventName: event.name)
            return
        }
        Analytics.logEvent(event.name, parameters: parameters.mapValues(\.firebaseValue))

        // Breadcrumb：內容與 Analytics 參數完全相同（同一套型別限制）。
        // **不橋接 `SecureLog`**——它的 debug 行印過 `request.url?.path`（含期別 UUID）。
        let crumb = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.breadcrumbText)" }
            .joined(separator: " ")
        Crashlytics.crashlytics().log(crumb.isEmpty ? event.name : "\(event.name) \(crumb)")
    }

    /// 送畫面瀏覽，並同步更新 Crashlytics 的 `screen` 鍵。畫面的 `.onAppear` 呼叫這一支就好。
    static func screenAppeared(_ screen: ScreenName) {
        setCrashKey(.screen(screen))
        logEvent(.screenViewed(screen))
    }

    /// 設定當機報告的自訂鍵。
    static func setCrashKey(_ key: CrashKey) {
        let value = key.value
        // 參數名用 crash key 自己的名字（而不是通用的 "value"），
        // 整數的值域白名單才對得上（`current_period` 1–14、`last_status` -1–599）。
        if let block = gate(eventName: key.name, parameters: [key.name: value]) {
            handle(block, eventName: "crash_key:\(key.name)")
            return
        }
        Crashlytics.crashlytics().setCustomValue(value.firebaseValue, forKey: key.name)
    }

    // MARK: 非致命錯誤

    /// 記錄一個非致命錯誤。
    ///
    /// **刻意不接受 `Error`**：`NSError.userInfo` 與 `localizedDescription` 常常夾帶伺服器
    /// 回傳的原文或完整 URL（`URLError.userInfo[NSURLErrorFailingURLStringErrorKey]`
    /// 就是含期別 UUID 的完整網址），而 Crashlytics 的 `record(error:)` 會把整包 userInfo
    /// 一起送走。這裡只收**已經分類完成**的 `TelemetryIssue` 與封閉列舉／整數，
    /// 呼叫端沒有「把原始 error 丟進來」這條路。
    ///
    /// 每個 (issue, endpoint) 組合**每個 App session 只回報一次**，避免下拉刷新把同一個
    /// 改版訊號洗成幾千筆。
    static func recordNonFatal(
        _ issue: TelemetryIssue,
        endpoint: Endpoint? = nil,
        status: Int? = nil,
        extras: [String: AnalyticsValue] = [:]
    ) {
        var parameters: [String: AnalyticsValue] = extras
        if let endpoint { parameters["endpoint"] = .code(endpoint) }
        if let status { parameters["status"] = .int(status) }

        if let block = gate(eventName: issue.rawValue, parameters: parameters) {
            handle(block, eventName: "non_fatal:\(issue.label)")
            return
        }

        let dedupeKey = "\(issue.rawValue)|\(endpoint?.rawValue ?? "-")"
        stateLock.lock()
        let alreadyReported = reportedIssues.contains(dedupeKey)
        if !alreadyReported { reportedIssues.insert(dedupeKey) }
        stateLock.unlock()
        guard !alreadyReported else {
            log.debug("非致命錯誤本次 session 已回報過，略過：\(issue.label)")
            return
        }

        var userInfo: [String: Any] = parameters.mapValues(\.firebaseValue)
        // 這串是本檔案寫死的常數（domain.case），不是任何外部字串。
        userInfo[NSLocalizedDescriptionKey] = issue.label

        let error = NSError(domain: issue.domain.rawValue, code: issue.intCode, userInfo: userInfo)
        Crashlytics.crashlytics().record(error: error)
    }

    // MARK: 錯誤分類

    /// 把 `AppError` 分類成封閉列舉。**只取 case，不取 associated value。**
    static func classify(_ error: Error) -> FailReason {
        guard let appError = error as? AppError else { return .unknown }
        switch appError {
        case .network: return .network
        case .csrfNotFound: return .csrfMissing
        // `URLSessionHTTPClient` 用 -1 代表 redirect 超過 5 跳。
        case .unexpectedResponse(let status): return status == -1 ? .redirectLoop : .siteStatus
        case .parsing: return .siteParse
        case .notLoggedIn: return .sessionProbable
        case .blockedEgress: return .blockedEgress
        }
    }

    /// 取 HTTP 狀態碼。取不到（非 `unexpectedResponse`）回 -1。
    static func statusCode(from error: Error) -> Int {
        guard let appError = error as? AppError,
              case .unexpectedResponse(let status) = appError else { return -1 }
        return (0...599).contains(status) ? status : -1
    }

    /// 取 `URLError` 的整數碼。
    ///
    /// `AppError.network` 的 associated value 是 `URLSessionHTTPClient` 自己組的
    /// `"code -1009"`——**格式是我們寫的，不是官網給的**。這裡用嚴格的錨定樣式只取整數，
    /// 對不上就回 nil；字串本身永遠不會被送出。
    static func networkCode(from error: Error) -> Int? {
        guard let appError = error as? AppError, case .network(let text) = appError else { return nil }
        guard text.range(of: #"^code -?\d{1,6}$"#, options: .regularExpression) != nil else { return nil }
        return Int(text.dropFirst("code ".count)).flatMap { (-99_999...0).contains($0) ? $0 : nil }
    }

    /// 把 `AppError.blockedEgress(host)` 的 host 分類。**host 字串本身不送。**
    static func hostClass(from error: Error) -> HostClass? {
        guard let appError = error as? AppError, case .blockedEgress(let host) = appError else { return nil }
        return HostClass(host: host)
    }

    /// `duration_ms` 收斂到合法範圍。負數（時鐘往回跳）歸 0。
    static func clampDuration(_ milliseconds: Int) -> Int {
        min(max(milliseconds, 0), maxDurationMs)
    }

    /// 量測一段耗時的毫秒數。
    static func elapsedMs(since start: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000)
    }

    // MARK: 官網改版訊號（analytics-plan §2.4 / §5.4）

    /// 把一個失敗分類，並在該送的時候送出 E27 `site_error` ＋ 對應的 Crashlytics 非致命錯誤。
    ///
    /// - Parameter sessionProbable: 呼叫點是不是「冷啟動後的第一次抓取」。
    ///   `URLSessionHTTPClient.getHTML` 會跟隨 redirect，session 過期時
    ///   `GET /member/tasks` → 302 `/login` → 200 登入頁 HTML → 解析器丟 `parsing`。
    ///   **錯誤型別與官網改版一模一樣**，但冷啟動時多半只是 session 過期，
    ///   這時歸類為 `session_probable`，**不送** Crashlytics，也不送 `site_error`。
    ///   只有在剛登入成功之後（`source = post_login`）發生的解析失敗才算改版訊號。
    /// - Returns: 分類後的原因，供呼叫端附在自己的 `*_result` 事件上。
    @discardableResult
    static func reportFailure(
        _ error: Error,
        endpoint: Endpoint,
        sessionProbable: Bool = false
    ) -> FailReason {
        var reason = classify(error)
        if sessionProbable, reason == .siteParse {
            reason = .sessionProbable
        }

        let status = statusCode(from: error)
        setCrashKey(.lastEndpoint(endpoint))
        if status != -1 { setCrashKey(.lastStatus(status)) }

        switch reason {
        // 網路錯誤太吵，不進 Crashlytics、也不算官網改版；只留在各 *_result 的 reason 上。
        case .network, .invalidCredentials, .notRegistered, .unknown, .sessionProbable:
            return reason

        case .siteParse:
            logEvent(.siteError(endpoint: endpoint, kind: .parse, status: status, hostClass: nil))
            recordNonFatal(parseIssue(for: endpoint), endpoint: endpoint,
                           status: status == -1 ? 200 : status)

        case .csrfMissing:
            logEvent(.siteError(endpoint: endpoint, kind: .csrfMissing, status: status, hostClass: nil))
            recordNonFatal(.csrfMissing, endpoint: endpoint, status: status)

        case .siteStatus:
            logEvent(.siteError(endpoint: endpoint, kind: .unexpectedStatus, status: status, hostClass: nil))
            recordNonFatal(statusIssue(for: endpoint), endpoint: endpoint, status: status)

        case .redirectLoop:
            logEvent(.siteError(endpoint: endpoint, kind: .redirectLoop, status: status, hostClass: nil))
            recordNonFatal(.http, endpoint: endpoint, status: status,
                           extras: ["kind": .code(SiteErrorKind.redirectLoop)])

        case .blockedEgress:
            let host = hostClass(from: error)
            logEvent(.siteError(endpoint: endpoint, kind: .blockedEgress, status: status, hostClass: host))
            recordNonFatal(.egress, endpoint: endpoint,
                           extras: host.map { ["host_class": .code($0)] } ?? [:])
        }
        return reason
    }

    /// 解析失敗要記在哪個 issue 下。
    private static func parseIssue(for endpoint: Endpoint) -> TelemetryIssue {
        switch endpoint {
        case .tasks: return .tasksNoCards
        case .redeem: return .redeem
        case .voucher, .voucherResend: return .voucherNotice
        case .voucherView: return .voucherView
        case .screenshot: return .screenshotRedirect
        case .upload: return .upload
        case .access, .login, .logout: return .auth
        }
    }

    /// 非預期狀態碼要記在哪個 issue 下。
    private static func statusIssue(for endpoint: Endpoint) -> TelemetryIssue {
        switch endpoint {
        case .access, .login, .logout: return .auth
        case .upload: return .upload
        case .screenshot: return .screenshotRedirect
        default: return .http
        }
    }
}

// MARK: - tasks_fetch 的共用組裝（E8 / N1 / N2）

/// `TasksServicing.fetchTasks()` 有五個呼叫點（首頁啟動／首頁刷新／登入後／任務分頁／券夾），
/// 每一個都要送同一組參數。集中在這裡，避免五份各自漂移的複製貼上。
///
/// **不會被送出的東西**（每次改這裡都請重看一次）：
/// `TaskPeriod.id`（期別 UUID）、`remainingText`／`uploadedAt`／`reviewedAt`（官網文字，
/// 可能含日期）、`startDate`／`endDate`。送出去的只有：期數（活動週次，全體使用者同一週）、
/// 清單長度、狀態機分類、有無快取、耗時。
enum TasksTelemetry {
    static func reportSuccess(
        source: TasksFetchSource,
        periods: [TaskPeriod],
        highlighted: TaskPeriod?,
        hadCache: Bool,
        startedAt: DispatchTime
    ) {
        let currentPeriod = highlighted.map { min(max($0.index, 1), 14) }
        let currentState = highlighted.map { TaskStateClass($0.state) }

        if let currentPeriod { Telemetry.setCrashKey(.currentPeriod(currentPeriod)) }
        if let currentState { Telemetry.setCrashKey(.currentState(currentState)) }

        Telemetry.logEvent(.tasksFetch(
            source: source,
            outcome: .ok,
            reason: nil,
            periodCount: periods.count,
            currentPeriod: currentPeriod,
            currentState: currentState,
            hadCache: hadCache,
            durationMs: Telemetry.elapsedMs(since: startedAt)
        ))

        reportPartialDrift(periods)
    }

    static func reportFailure(
        _ error: Error,
        source: TasksFetchSource,
        hadCache: Bool,
        startedAt: DispatchTime,
        sessionProbable: Bool
    ) {
        let reason = Telemetry.reportFailure(error, endpoint: .tasks, sessionProbable: sessionProbable)
        Telemetry.logEvent(.tasksFetch(
            source: source,
            outcome: .error,
            reason: reason,
            periodCount: 0,
            currentPeriod: nil,
            currentState: nil,
            hadCache: hadCache,
            durationMs: Telemetry.elapsedMs(since: startedAt)
        ))
    }

    /// N2：頁面解析得出來，但**內容跟我們認得的不一樣**——官網新增狀態常數，或本該有
    /// UUID 的卡片抓不到。這是官網改版最早的警報，比「整頁解析失敗」早好幾週出現。
    ///
    /// 規格允許在這裡附上官網的原始狀態字串（`raw_state`，由 regex `[A-Z_]+` 約束）作為
    /// 「唯一放行的非 enum 字串」。**本 App 不用那個例外**：官網回傳的原文一律不送，
    /// 沒有特例。知道「出現了不認得的狀態、有幾張」就足以觸發人工去看一眼官網，
    /// 不需要把字串本身送到第三方。
    private static func reportPartialDrift(_ periods: [TaskPeriod]) {
        let unknownStates = periods.filter { $0.state == .unknown }.count
        // 非 `notStarted` 的卡片理應都帶得到期別 UUID；抓不到代表兌換／截圖連結的結構變了。
        let missingID = periods.contains { $0.state != .notStarted && $0.state != .unknown && $0.id.isEmpty }
        guard unknownStates > 0 || missingID else { return }
        Telemetry.recordNonFatal(
            .tasksPartial,
            endpoint: .tasks,
            status: 200,
            extras: [
                "unknown_states": .int(unknownStates),
                "missing_id": .bool(missingID),
            ]
        )
    }
}
