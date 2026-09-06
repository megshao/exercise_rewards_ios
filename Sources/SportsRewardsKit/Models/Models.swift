import Foundation

/// 使用者個資，只會存在裝置本機 Keychain。切勿記錄到 log。
public struct Profile: Codable, Equatable, Sendable {
    public var name: String
    public var idNo: String            // 身分證號 e.g. A123456789
    public var birthDate: String       // ISO yyyy-MM-dd
    public var phone: String           // 09xxxxxxxx
    public var email: String
    public var nhiCardNo: String       // 健保卡卡號（首次註冊用）

    public init(name: String = "", idNo: String = "", birthDate: String = "",
                phone: String = "", email: String = "", nhiCardNo: String = "") {
        self.name = name; self.idNo = idNo; self.birthDate = birthDate
        self.phone = phone; self.email = email; self.nhiCardNo = nhiCardNo
    }
}

/// 登入所需三碼（登入無 OTP）。
public struct LoginCredentials: Equatable, Sendable {
    public let idNo: String
    public let birthDate: String   // ISO yyyy-MM-dd
    public let phone: String
    public init(idNo: String, birthDate: String, phone: String) {
        self.idNo = idNo; self.birthDate = birthDate; self.phone = phone
    }
}

public enum TaskState: String, Codable, Sendable {
    case notStarted      // 尚未開始
    case open            // 可上傳
    case pendingReview   // 待審核
    case redeemable      // 任務完成，可兌換
    case redeemed        // 已兌換
    case unknown

    /// 這個狀態下，官網的 `period-remaining` 還有意義嗎？
    ///
    /// **官網那個欄位講的是「上傳窗」倒數**，文字是「本期任務可上傳時間 剩 N 小時 N 分」，
    /// 而且**對已經走完審核的期別照樣回傳**——實測（2026-09-06）一張已兌換的券，
    /// 卡片上仍寫著「本期任務可上傳時間 剩 3 小時 20 分」。官網頁面自己的註解也寫明
    /// 「兌換窗是這一期自己的，與上傳窗無關」。
    ///
    /// 審核完成之後（可兌換／已兌換）上傳早就做完了，那個倒數指的是一個用不到的窗；
    /// 照著顯示只會讓使用者以為還有東西要上傳。因此這兩個狀態一律不顯示。
    ///
    /// 待審核（`pendingReview`）刻意**保留**：上傳窗還開著時，剩餘時間對「審核沒過還能不能
    /// 重新上傳」仍然是有用的資訊。
    public var showsUploadCountdown: Bool {
        switch self {
        case .redeemable, .redeemed: return false
        case .notStarted, .open, .pendingReview, .unknown: return true
        }
    }
}

/// 我的任務中的一期。
public struct TaskPeriod: Codable, Equatable, Identifiable, Sendable {
    public var id: String              // 後端 UUID
    public var index: Int              // 第 N 期
    public var startDate: String       // yyyy/MM/dd
    public var endDate: String
    public var state: TaskState
    public var remainingText: String?  // 剩 1 天 22 小時
    public var uploadedAt: String?
    public var reviewedAt: String?
    /// 已兌換的期別，官網會在卡片上寫「兌換內容：萊爾富／指定雞胸果昔兌換券」。
    /// 這裡存的是冒號後面那一段（通路／品項），只有 `state == .redeemed` 時才會有。
    ///
    /// **這是官網原文，屬不受信任輸入**：只能顯示在畫面上，
    /// 絕不可進遙測（見 `Telemetry.swift` 檔頭的禁止項）。
    public var voucherSummary: String?

    public init(id: String, index: Int, startDate: String, endDate: String,
                state: TaskState, remainingText: String? = nil,
                uploadedAt: String? = nil, reviewedAt: String? = nil,
                voucherSummary: String? = nil) {
        self.id = id; self.index = index; self.startDate = startDate; self.endDate = endDate
        self.state = state; self.remainingText = remainingText
        self.uploadedAt = uploadedAt; self.reviewedAt = reviewedAt
        self.voucherSummary = voucherSummary
    }
}

/// 登入結果分流。
public enum LoginOutcome: Equatable, Sendable {
    case success                 // 302 -> /member/tasks
    case notRegistered           // access 導向 /register（此身分證未註冊）
    case invalidCredentials      // 三碼不符，回登入頁
}

public enum AppError: Error, Equatable, Sendable {
    case network(String)
    case csrfNotFound
    case unexpectedResponse(Int)
    case parsing(String)
    case notLoggedIn
    case blockedEgress(String)   // 嘗試連非白名單網域
    /// response body 超過 `URLSessionHTTPClient.maxResponseBytes`（2 MB）。
    /// 官方頁面實測都在數十 KB；超過這個量級代表對面不是我們認得的那個站
    /// （官網被入侵、或裝置信任了 MITM 憑證），此時**不該把 body 交給任何 parser**。
    /// associated value 是實際位元組數，只給 log 用，不進遙測。
    case responseTooLarge(Int)
}

/// 兌換頁（`/member/redeem/{uuid}`）解析出的一個可兌換品項（商家 + 品項）。
public struct RedeemOption: Identifiable, Equatable, Sendable {
    public let vendorId: String
    public let vendorName: String
    public let itemName: String
    public let itemId: String
    /// 該列「兌換品項」連結指向的廠商商品頁，已正規化成 base-relative path
    /// （例如 `/intro/vendor-1.html`）。
    ///
    /// **nil 是正常狀況**：官網的規則是「靜態頁 `intro/vendor-{id}.html` 存在才長出這個
    /// 連結」，沒有另一份設定可以跟它不同步。因此這裡不自己用 `vendorId` 拼網址——
    /// 拼出來的網址在官網沒有那一頁時會是 404，而解析不到就代表官網也沒給。
    public let introPath: String?

    public var id: String { "\(vendorId)-\(itemId)" }

    public init(vendorId: String, vendorName: String, itemName: String, itemId: String,
                introPath: String? = nil) {
        self.vendorId = vendorId
        self.vendorName = vendorName
        self.itemName = itemName
        self.itemId = itemId
        self.introPath = introPath
    }
}

/// 廠商可兌換商品頁（`/intro/vendor-{id}.html`）解析出的內容。
///
/// 官網這幾頁有**兩種版型**，兩種都要吃：
/// - 逐項列出（全家／7-11／萊爾富）：`<details data-category>` 分類卡，卡內 `<li data-name>`
///   一項一列，`summary` 上有「N 項」。
/// - 只給類別與舉例（全聯／萬家福／樂家康）：一張 `類別名稱 / 商品名稱（列舉）` 的表格。
///
/// 兩者共用 `VendorIntroCategory`：前者填 `items`，後者填 `examples`。
/// **刻意不把 `examples` 拆成 `items`**——官網那欄本來就是「舉例」不是完整清單，
/// 拆開會讓使用者以為那就是全部。
public struct VendorIntro: Equatable, Sendable {
    /// 頁面主標，例如「全家便利商店可兌換商品」。
    public let title: String
    /// 主標下方的說明，例如「點選商品分類，即可展開查看相關兌換品項。」。可能沒有。
    public let subtitle: String?
    public let categories: [VendorIntroCategory]
    /// 頁尾「兌換注意事項」的每一段。
    public let notices: [String]
    /// 這一頁是用哪一種版型解析出來的。`.unrecognised` 代表兩種已知版型都對不上、
    /// 靠純文字兜出來的——呼叫端**必須**為它發警報（見 `VendorIntroLayout`）。
    public let layout: VendorIntroLayout

    public init(title: String, subtitle: String?, categories: [VendorIntroCategory],
                notices: [String], layout: VendorIntroLayout = .itemList) {
        self.title = title
        self.subtitle = subtitle
        self.categories = categories
        self.notices = notices
        self.layout = layout
    }
}

/// 廠商商品頁的版型。
///
/// **為什麼要把它變成資料的一部分**：`.unrecognised` 是「官網換版型了」這件事唯一的訊號。
/// 舊做法是兩種版型都對不上就丟 `AppError.parsing`——警報有了，但使用者只看到一個錯誤畫面。
/// 現在改成退到純文字仍然給出內容，代價是**失敗不再自動變成例外**，
/// 所以這個欄位就是要求呼叫端自己回報的那份契約。
public enum VendorIntroLayout: String, Sendable {
    /// `<details data-category>` 分類卡 + `<li data-name>` 逐項清單（全家／7-11／萊爾富）。
    case itemList = "item_list"
    /// `類別名稱 / 商品名稱（列舉）` 表格（全聯／萬家福・樂家康）。
    case categoryTable = "category_table"
    /// 兩種都對不上，靠 `<li>`／`<p>` 純文字兜出來的最小可用結果。
    case unrecognised
}

/// 商品頁上的一個分類。
public struct VendorIntroCategory: Identifiable, Equatable, Sendable {
    /// 分類名稱，例如「Let's Café」「冷藏鮮乳」。
    public let name: String
    /// 逐項列出的品項（只有逐項版的頁面有）。
    public let items: [String]
    /// 官網原文的舉例字串（只有列舉版的頁面有），例如「光泉低脂鮮乳、林鳳營高品質鮮乳等」。
    public let examples: String?
    /// 官網自己標的品項數（「54 項」）。**以官網為準，不用 `items.count` 取代**——
    /// 兩者不一致時代表解析漏了東西，是個看得見的訊號。
    public let statedCount: Int?
    /// 是不是「全部品項」那張彙總卡（官網用 `class="... all-items"` 標記）。
    public let isAllItems: Bool

    public var id: String { name }

    public init(name: String, items: [String] = [], examples: String? = nil,
                statedCount: Int? = nil, isAllItems: Bool = false) {
        self.name = name
        self.items = items
        self.examples = examples
        self.statedCount = statedCount
        self.isAllItems = isAllItems
    }
}

/// 送出兌換申請的結果。best-effort：官網送出兌換表單後還要走一次簡訊 OTP 才會出示券碼，
/// 該流程由 `VoucherServicing` 另行處理，因此這裡只能回報表單是否成功送出、附上友善訊息。
public struct RedeemResult: Equatable, Sendable {
    public let submitted: Bool
    public let message: String

    public init(submitted: Bool, message: String) {
        self.submitted = submitted
        self.message = message
    }
}

/// 券碼頁（`/member/voucher/{uuid}/view`）中一段 `.voucher-figure`。
/// `format` 保留原始字串（"CODE_128" / "QR_CODE"），由 App 端分流成不同的條碼產生器。
/// 萊爾富超值商品券為兩段式（商品條碼＋券號條碼），兩段缺一不可，因此 `Voucher.figures`
/// 是陣列而非單一值。
public struct VoucherFigure: Equatable, Sendable {
    public let format: String
    public let value: String
    public let caption: String

    public init(format: String, value: String, caption: String) {
        self.format = format
        self.value = value
        self.caption = caption
    }
}

/// 通過 OTP 驗證後看到的加碼券內容。依合規要求，這個型別**絕不可被快取**——
/// 每次進入 VoucherView 都要重新走一次 OTP 驗證才能取得。
public struct Voucher: Equatable, Sendable {
    public let vendorName: String
    public let itemName: String
    public let expiry: String
    public let figures: [VoucherFigure]
    public let notices: [String]

    public init(vendorName: String, itemName: String, expiry: String,
                figures: [VoucherFigure], notices: [String]) {
        self.vendorName = vendorName
        self.itemName = itemName
        self.expiry = expiry
        self.figures = figures
        self.notices = notices
    }
}

/// 驗證簡訊 OTP 的結果分流。
public enum VoucherOtpResult: Equatable, Sendable {
    /// 驗證通過（302 -> `.../view`）。
    case success
    /// 驗證碼錯誤，回同一頁附錯誤訊息；`remaining` 是解析到的剩餘可再試次數（共 3 次）。
    case wrongCode(remaining: Int?)
    /// 其他非預期狀況（例如已用罄仍未收到重發提示、頁面格式不符預期）。
    case failed(message: String)
}
