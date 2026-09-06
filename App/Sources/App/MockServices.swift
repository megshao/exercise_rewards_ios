import Foundation
import SportsRewardsKit

/// 假的登入服務，供 UI 開發與 Preview 使用。
/// 正式環境由 `AppEnvironment` 換成真實的 `AuthService(http:)`。
public final class MockAuthService: AuthServicing, @unchecked Sendable {
    public enum Scenario: Sendable {
        case success
        case notRegistered
        case invalidCredentials
        case networkError
    }

    private let scenario: Scenario
    private let delayNanoseconds: UInt64

    public init(scenario: Scenario = .success, delaySeconds: Double = 0.9) {
        self.scenario = scenario
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
    }

    public func login(_ credentials: LoginCredentials) async throws -> LoginOutcome {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        switch scenario {
        case .success: return .success
        case .notRegistered: return .notRegistered
        case .invalidCredentials: return .invalidCredentials
        case .networkError: throw AppError.network("模擬網路逾時")
        }
    }

    public func logout() async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}

/// 假的任務服務，回傳範例的 14 期任務資料，供 UI 開發與 Preview 使用。
/// 正式環境由 `AppEnvironment` 換成真實的 `TasksService(http:)`。
public final class MockTasksService: TasksServicing, @unchecked Sendable {
    private let sample: [TaskPeriod]
    private let delayNanoseconds: UInt64

    public init(sample: [TaskPeriod] = MockTasksService.defaultSample, delaySeconds: Double = 0.6) {
        self.sample = sample
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
    }

    public func fetchTasks() async throws -> [TaskPeriod] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return sample
    }

    public func screenshotURL(taskID: String) async throws -> URL {
        try await Task.sleep(nanoseconds: 200_000_000)
        guard let url = URL(string: "https://500.gov.tw/registrant/member/screenshot/\(taskID)") else {
            throw AppError.unexpectedResponse(0)
        }
        return url
    }

    /// 示範模式**絕不能連外**（DemoMode 檔頭與畫面上的橫幅都是這樣宣告的），所以這裡回傳
    /// App bundle 內附的示範運動紀錄截圖 file URL，而不是任何第三方圖床網址。
    /// `ScreenshotView.ScreenshotImageLoader` 對 `isFileURL` 有專門分支，不會走網路。
    public func screenshotImageURL(taskID: String) async throws -> URL {
        try await Task.sleep(nanoseconds: 300_000_000)
        guard let url = Bundle.main.url(forResource: "DemoScreenshot", withExtension: "png") else {
            throw AppError.unexpectedResponse(0)
        }
        return url
    }

    /// 示範模式（App Store 審查）與 Preview 用的完整 14 期範例資料。
    ///
    /// 陣列順序刻意把「本週那一期」放在第一個：`HomeViewModel.highlightedPeriod` 取的是
    /// 第一個非 `.notStarted` 的期別，首頁「本週任務」與任務頁置頂高亮都依它決定。
    /// 其餘期別依 1→14 排在後面（`TasksViewModel.sorted` 會再排一次）。
    ///
    /// 狀態分佈刻意涵蓋全部 5 種狀態，讓審查員與截圖素材都看得到完整流程：
    /// 已兌換 3 期（券夾有券可看）／可兌換 1 期／審核中 1 期／可上傳 1 期／尚未開始 8 期。
    /// `id` 比照真實後端：只有當期與已結束的期別有 UUID，尚未開始的期別為空字串
    /// （空字串會讓卡片不顯示需要 UUID 的按鈕，與正式站行為一致）。
    public static let defaultSample: [TaskPeriod] = [
        // 本週：可上傳，倒數中。
        TaskPeriod(id: "demo-period-06", index: 6, startDate: "10/06", endDate: "10/12",
                   state: .open, remainingText: "剩 2 天 7 小時可上傳"),

        // 已完成並兌換：券夾裡看得到 3 張加碼券。
        // `voucherSummary` 比照官網任務卡上的「兌換內容：通路／品項」那一行。
        TaskPeriod(id: "demo-period-01", index: 1, startDate: "09/01", endDate: "09/07",
                   state: .redeemed, uploadedAt: "09/03 21:42", reviewedAt: "09/05 10:18 通過",
                   voucherSummary: "示範超商 A／50+3元加碼券"),
        TaskPeriod(id: "demo-period-02", index: 2, startDate: "09/08", endDate: "09/14",
                   state: .redeemed, uploadedAt: "09/10 07:55", reviewedAt: "09/12 14:03 通過",
                   voucherSummary: "示範超商 C／指定雞胸果昔兌換券"),
        TaskPeriod(id: "demo-period-03", index: 3, startDate: "09/15", endDate: "09/21",
                   state: .redeemed, uploadedAt: "09/18 20:11", reviewedAt: "09/19 09:26 通過",
                   voucherSummary: "示範超市 D／50元加碼券"),

        // 審核通過、尚未兌換：券夾「可兌換」區與任務頁的「立即兌換」按鈕都由這期驅動。
        TaskPeriod(id: "demo-period-04", index: 4, startDate: "09/22", endDate: "09/28",
                   state: .redeemable, remainingText: "剩 3 天 5 小時可兌換",
                   uploadedAt: "09/24 19:30", reviewedAt: "09/26 11:47 通過"),

        // 已上傳、等待審核。
        TaskPeriod(id: "demo-period-05", index: 5, startDate: "09/29", endDate: "10/05",
                   state: .pendingReview, remainingText: "已上傳 · 5 個工作日內完成審核",
                   uploadedAt: "10/01 22:08"),

        // 尚未開始的 8 期（後端此時不給 UUID，維持空字串）。
        TaskPeriod(id: "", index: 7, startDate: "10/13", endDate: "10/19", state: .notStarted),
        TaskPeriod(id: "", index: 8, startDate: "10/20", endDate: "10/26", state: .notStarted),
        TaskPeriod(id: "", index: 9, startDate: "10/27", endDate: "11/02", state: .notStarted),
        TaskPeriod(id: "", index: 10, startDate: "11/03", endDate: "11/09", state: .notStarted),
        TaskPeriod(id: "", index: 11, startDate: "11/10", endDate: "11/16", state: .notStarted),
        TaskPeriod(id: "", index: 12, startDate: "11/17", endDate: "11/23", state: .notStarted),
        TaskPeriod(id: "", index: 13, startDate: "11/24", endDate: "11/30", state: .notStarted),
        TaskPeriod(id: "", index: 14, startDate: "12/01", endDate: "12/07", state: .notStarted),
    ]
}

/// 假的兌換服務，回傳範例商家品項清單，供 UI 開發與 Preview 使用。
/// 正式環境由 `AppEnvironment` 換成真實的 `RedeemService(http:)`。
public final class MockRedeemService: RedeemServicing, @unchecked Sendable {
    private let sample: [RedeemOption]
    private let delayNanoseconds: UInt64

    public init(sample: [RedeemOption] = MockRedeemService.defaultSample, delaySeconds: Double = 0.5) {
        self.sample = sample
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
    }

    public func options(taskID: String) async throws -> [RedeemOption] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return sample
    }

    public func redeem(taskID: String, vendorId: String, item: String) async throws -> RedeemResult {
        try await Task.sleep(nanoseconds: 400_000_000)
        return RedeemResult(submitted: true, message: "已送出兌換，請完成簡訊驗證後檢視加碼券")
    }

    /// 示範用的可兌換商品頁。逐項版與列舉版各給一個範例，讓審查員兩種畫面都看得到。
    public func vendorIntro(path: String) async throws -> VendorIntro {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return Self.intros[path] ?? Self.defaultIntro
    }

    public static let defaultSample: [RedeemOption] = [
        RedeemOption(vendorId: "1", vendorName: "全家便利商店", itemName: "50+3元加碼券",
                     itemId: "item-demo-family", introPath: "/intro/vendor-1.html"),
        RedeemOption(vendorId: "2", vendorName: "7-11", itemName: "50+5元加碼券",
                     itemId: "item-demo-711", introPath: "/intro/vendor-2.html"),
        RedeemOption(vendorId: "3", vendorName: "萊爾富", itemName: "50元加碼券",
                     itemId: "item-demo-hilife", introPath: "/intro/vendor-3.html"),
        RedeemOption(vendorId: "5", vendorName: "全聯", itemName: "50元加碼券",
                     itemId: "item-demo-pxmart", introPath: "/intro/vendor-5.html"),
    ]

    /// 逐項版（示範超商）：分類卡 + 品項清單。
    private static let listStyleIntro = VendorIntro(
        title: "示範超商可兌換商品",
        subtitle: "點選商品分類，即可展開查看相關兌換品項。",
        categories: [
            VendorIntroCategory(name: "全部品項",
                                items: ["示範無糖綠茶", "示範礦泉水", "示範大冰拿鐵",
                                        "示範綜合堅果", "示範茶葉蛋", "示範鮮豆漿"],
                                statedCount: 6, isAllItems: true),
            VendorIntroCategory(name: "現煮咖啡", items: ["示範大冰拿鐵"], statedCount: 1),
            VendorIntroCategory(name: "無糖茶", items: ["示範無糖綠茶"], statedCount: 1),
            VendorIntroCategory(name: "瓶裝水類", items: ["示範礦泉水"], statedCount: 1),
            VendorIntroCategory(name: "堅果、蛋類",
                                items: ["示範綜合堅果", "示範茶葉蛋"], statedCount: 2),
            VendorIntroCategory(name: "豆米漿／鮮乳", items: ["示範鮮豆漿"], statedCount: 1),
        ],
        notices: ["實際可兌換品項、供應狀況及門市庫存，依各門市現場公告為準。"]
    )

    /// 列舉版（示範超市）：只有類別與舉例，沒有完整品項清單。
    private static let tableStyleIntro = VendorIntro(
        title: "示範超市可兌換商品",
        subtitle: "以下為運動幣加碼活動可兌換商品類別",
        categories: [
            VendorIntroCategory(name: "冷藏鮮乳", examples: "示範低脂鮮乳、示範高品質鮮乳等"),
            VendorIntroCategory(name: "豆漿／米漿／燕麥", examples: "示範無加糖鮮豆漿、示範陽光糙米漿等"),
            VendorIntroCategory(name: "常溫鮮蛋", examples: "示範洗選蛋（白）等"),
            VendorIntroCategory(name: "堅果／核仁類", examples: "示範綜合堅果、示範無調味腰果罐等"),
        ],
        notices: ["實際可兌換品項、供應狀況及門市庫存，依各門市現場公告為準。"]
    )

    private static let intros: [String: VendorIntro] = [
        "/intro/vendor-1.html": listStyleIntro,
        "/intro/vendor-2.html": listStyleIntro,
        "/intro/vendor-3.html": listStyleIntro,
        "/intro/vendor-5.html": tableStyleIntro,
    ]

    private static let defaultIntro = listStyleIntro
}

/// 假的檢視加碼券服務，供 UI 開發與 Preview 使用。可設定 OTP 情境（一次驗證成功／錯誤幾次／
/// 傳送失敗），`fetchVoucher` 回傳範例券碼（比照 Fixtures/voucher_view.html 的萊爾富兩段式券）。
public final class MockVoucherService: VoucherServicing, @unchecked Sendable {
    public enum OtpScenario: Sendable {
        /// 任何 6 碼都驗證成功。
        case alwaysSucceeds
        /// 先回錯誤 N 次（`remaining` 遞減至 0），之後才成功。
        case wrongThenSucceeds(times: Int)
        /// 每次都驗證錯誤，直到用罄（remaining 用完後回 .failed）。
        case alwaysWrong
        /// 發送 OTP 本身就失敗。
        case sendFails
    }

    private let scenario: OtpScenario
    private let sample: Voucher
    private let delayNanoseconds: UInt64
    private var attemptCount = 0

    public init(
        scenario: OtpScenario = .alwaysSucceeds,
        sample: Voucher = MockVoucherService.defaultSample,
        delaySeconds: Double = 0.5
    ) {
        self.scenario = scenario
        self.sample = sample
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
    }

    public func sendOtp(taskID: String) async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        if case .sendFails = scenario {
            throw AppError.network("模擬簡訊發送失敗")
        }
    }

    public func verifyOtp(taskID: String, otp: String) async throws -> VoucherOtpResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        attemptCount += 1
        switch scenario {
        case .alwaysSucceeds:
            return .success
        case .wrongThenSucceeds(let times):
            if attemptCount <= times {
                return .wrongCode(remaining: max(0, 3 - attemptCount))
            }
            return .success
        case .alwaysWrong:
            let remaining = max(0, 3 - attemptCount)
            if remaining == 0 {
                return .failed(message: "驗證碼錯誤次數已達上限，請重新發送")
            }
            return .wrongCode(remaining: remaining)
        case .sendFails:
            return .failed(message: "尚未發送驗證碼")
        }
    }

    public func fetchVoucher(taskID: String) async throws -> Voucher {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return sample
    }

    public static let defaultSample = Voucher(
        vendorName: "萊爾富",
        itemName: "超值商品券",
        expiry: "115年12月31日",
        figures: [
            VoucherFigure(format: "CODE_128", value: "00000000", caption: "① 商品條碼"),
            VoucherFigure(format: "CODE_128", value: "AAAA0000BBBB1111", caption: "② 券號條碼")
        ],
        notices: [
            "加碼券使用期限自取得後起至115年12月31日24時止，逾期視同放棄，恕不補發、展延、折換現金或更換其他等值商品。",
            "抵用時應開啟本人帳號之有效加碼券頁面，並依合作店家現場流程完成抵用，不得以紙本列印、手機截圖、翻拍或其他非活動網站即時畫面方式抵用。"
        ]
    )
}

/// 假的健康資料讀取器，回傳範例的今日健康摘要，供 UI 開發與 Preview 使用。
public final class MockHealthReader: HealthReading, @unchecked Sendable {
    public enum Scenario: Sendable, Equatable {
        case authorized
        case notAuthorized
    }

    private var scenario: Scenario
    private let sample: HealthSummary
    private let delayNanoseconds: UInt64

    public init(
        scenario: Scenario = .authorized,
        sample: HealthSummary = MockHealthReader.defaultSample,
        delaySeconds: Double = 0.4
    ) {
        self.scenario = scenario
        self.sample = sample
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
    }

    public func isAuthorized() async -> Bool {
        scenario == .authorized
    }

    public func requestAuthorization() async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        scenario = .authorized
    }

    public func summary(for date: Date) async throws -> HealthSummary {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return HealthSummary(
            date: date,
            steps: sample.steps,
            distanceMeters: sample.distanceMeters,
            exerciseMinutes: sample.exerciseMinutes
        )
    }

    public static let defaultSample = HealthSummary(
        date: Date(),
        steps: 9_688,
        distanceMeters: 6_400,
        exerciseMinutes: 42
    )
}

/// 假的上傳服務，供 UI 開發與 Preview 使用。
public final class MockUploadService: UploadServicing, @unchecked Sendable {
    public enum Scenario: Sendable {
        case success
        case failure
    }

    private let scenario: Scenario
    private let delayNanoseconds: UInt64

    public init(scenario: Scenario = .success, delaySeconds: Double = 0.5) {
        self.scenario = scenario
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
    }

    public func upload(taskID: String?, imageData: Data, fileName: String) async throws -> UploadResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        switch scenario {
        case .success:
            return UploadResult(submitted: true, message: "已送出，等待審核")
        case .failure:
            return UploadResult(submitted: false, message: "上傳失敗，請稍後再試")
        }
    }
}
