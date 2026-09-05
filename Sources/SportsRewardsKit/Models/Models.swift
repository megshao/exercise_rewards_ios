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

    public init(id: String, index: Int, startDate: String, endDate: String,
                state: TaskState, remainingText: String? = nil,
                uploadedAt: String? = nil, reviewedAt: String? = nil) {
        self.id = id; self.index = index; self.startDate = startDate; self.endDate = endDate
        self.state = state; self.remainingText = remainingText
        self.uploadedAt = uploadedAt; self.reviewedAt = reviewedAt
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
}

/// 兌換頁（`/member/redeem/{uuid}`）解析出的一個可兌換品項（商家 + 品項）。
public struct RedeemOption: Identifiable, Equatable, Sendable {
    public let vendorId: String
    public let vendorName: String
    public let itemName: String
    public let itemId: String

    public var id: String { "\(vendorId)-\(itemId)" }

    public init(vendorId: String, vendorName: String, itemName: String, itemId: String) {
        self.vendorId = vendorId
        self.vendorName = vendorName
        self.itemName = itemName
        self.itemId = itemId
    }
}

/// 送出兌換申請的結果。best-effort：官網送出兌換表單後還要走一次簡訊 OTP 才會出示券碼，
/// 該流程目前未知/未實測（PRD R2），因此這裡只能回報表單是否成功送出、附上友善訊息。
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
