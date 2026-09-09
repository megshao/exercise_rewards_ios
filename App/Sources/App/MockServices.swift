import Foundation
import ExerciseRewardsKit

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
    /// **日期是依「今天」動態算出來的**：第 6 期永遠涵蓋當下所在那一週（週一～週日，
    /// 台北時間），其餘 13 期以它為基準前後各推一週。示範模式因此永遠有一個真正的當期，
    /// 不會像寫死日期那樣過幾天就整份過期。
    ///
    /// **為什麼順序改回 1→14**：舊版刻意把當期塞到陣列第 0 位，好讓當時
    /// 「取第一個非 `.notStarted`」的 `HomeViewModel.highlightedPeriod` 剛好選中它。
    /// 那等於用示範資料把正式站的 bug 蓋住——正式站回的是 1→14，第 1 期一旦不是
    /// `.notStarted` 就永遠被選中，當期再也不前進，而截圖測試跑的是這份被排好的資料，
    /// 完全驗不到。現在當期由日期決定，示範資料跟正式資料走同一條路徑。
    ///
    /// 狀態分佈刻意涵蓋全部 5 種狀態，讓審查員與截圖素材都看得到完整流程：
    /// 已兌換 3 期（券夾有券可看）／可兌換 1 期／審核中 1 期／可上傳 1 期／尚未開始 8 期。
    ///
    /// 「已使用」不在這份資料裡——它不是官網的狀態，而是使用者在 App 內自己標記的
    /// 本機旗標（見 `VoucherUsage`），因此示範模式一開始三張券都是未使用。
    /// `id` 比照真實後端：只有當期與已結束的期別有 UUID，尚未開始的期別為空字串
    /// （空字串會讓卡片不顯示需要 UUID 的按鈕，與正式站行為一致）。
    public static var defaultSample: [TaskPeriod] { sample() }

    /// - Parameter now: 「今天」的基準時間。第 6 期會涵蓋它。測試可注入固定時間。
    static func sample(now: Date = Date()) -> [TaskPeriod] {
        let weeks = weekRanges(currentIndex: 6, now: now)
        func start(_ index: Int) -> String { siteDate(weeks[index - 1].start) }
        func end(_ index: Int) -> String { siteDate(weeks[index - 1].end) }

        /// 該期第 `day` 天的 `MM/dd HH:mm`——官網「上傳時間／審核時間」就是這個格式。
        /// 跟著期別日期一起算，才不會出現「第 1 期是 8 月、上傳時間卻寫 9 月」。
        func stamp(_ index: Int, day: Int, _ hour: Int, _ minute: Int) -> String {
            let base = weeks[index - 1].start
            let date = demoCalendar.date(byAdding: .day, value: day, to: base) ?? base
            let parts = demoCalendar.dateComponents([.month, .day], from: date)
            return String(format: "%02d/%02d %02d:%02d", parts.month ?? 0, parts.day ?? 0, hour, minute)
        }

        return [
            // 已完成並兌換：券夾裡看得到 3 張加碼券。
            // `voucherSummary` 比照官網任務卡上的「兌換內容：通路／品項」那一行。
            TaskPeriod(id: "demo-period-01", index: 1, startDate: start(1), endDate: end(1),
                       state: .redeemed, uploadedAt: stamp(1, day: 2, 21, 42),
                       reviewedAt: stamp(1, day: 4, 10, 18) + " 通過",
                       voucherSummary: "示範超商 A／50+3元加碼券"),
            TaskPeriod(id: "demo-period-02", index: 2, startDate: start(2), endDate: end(2),
                       state: .redeemed, uploadedAt: stamp(2, day: 2, 7, 55),
                       reviewedAt: stamp(2, day: 4, 14, 3) + " 通過",
                       voucherSummary: "示範超商 C／指定雞胸果昔兌換券"),
            TaskPeriod(id: "demo-period-03", index: 3, startDate: start(3), endDate: end(3),
                       state: .redeemed, uploadedAt: stamp(3, day: 3, 20, 11),
                       reviewedAt: stamp(3, day: 4, 9, 26) + " 通過",
                       voucherSummary: "示範超市 D／50元加碼券"),

            // 審核通過、尚未兌換：券夾「可兌換」區與任務頁的「立即兌換」按鈕都由這期驅動。
            TaskPeriod(id: "demo-period-04", index: 4, startDate: start(4), endDate: end(4),
                       state: .redeemable, remainingText: "剩 3 天 5 小時可兌換",
                       uploadedAt: stamp(4, day: 2, 19, 30),
                       reviewedAt: stamp(4, day: 4, 11, 47) + " 通過"),

            // 已上傳、等待審核。
            TaskPeriod(id: "demo-period-05", index: 5, startDate: start(5), endDate: end(5),
                       state: .pendingReview, remainingText: "已上傳 · 5 個工作日內完成審核",
                       uploadedAt: stamp(5, day: 2, 22, 8)),

            // 本週：可上傳，倒數中。倒數字串同樣依這一期的結束時間算，避免與日期矛盾。
            TaskPeriod(id: "demo-period-06", index: 6, startDate: start(6), endDate: end(6),
                       state: .open,
                       remainingText: uploadRemainingText(periodEnd: weeks[5].end, now: now)),

            // 尚未開始的 8 期（後端此時不給 UUID，維持空字串）。
            TaskPeriod(id: "", index: 7, startDate: start(7), endDate: end(7), state: .notStarted),
            TaskPeriod(id: "", index: 8, startDate: start(8), endDate: end(8), state: .notStarted),
            TaskPeriod(id: "", index: 9, startDate: start(9), endDate: end(9), state: .notStarted),
            TaskPeriod(id: "", index: 10, startDate: start(10), endDate: end(10), state: .notStarted),
            TaskPeriod(id: "", index: 11, startDate: start(11), endDate: end(11), state: .notStarted),
            TaskPeriod(id: "", index: 12, startDate: start(12), endDate: end(12), state: .notStarted),
            TaskPeriod(id: "", index: 13, startDate: start(13), endDate: end(13), state: .notStarted),
            TaskPeriod(id: "", index: 14, startDate: start(14), endDate: end(14), state: .notStarted),
        ]
    }

    /// 示範資料共用的行事曆：跟正式資料同一個時區（`TaskPeriod.activityCalendar`），
    /// 並把一週之始設為週一——官網的期別就是週一到週日。
    private static var demoCalendar: Calendar {
        var calendar = TaskPeriod.activityCalendar
        calendar.firstWeekday = 2
        return calendar
    }

    /// 14 期的起訖日，第 `currentIndex` 期涵蓋 `now` 所在的那一週。
    private static func weekRanges(currentIndex: Int, now: Date) -> [(start: Date, end: Date)] {
        let calendar = demoCalendar
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        return (1...14).map { index in
            let start = calendar.date(byAdding: .day, value: (index - currentIndex) * 7, to: thisWeek) ?? thisWeek
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return (start, end)
        }
    }

    /// 官網格式 `yyyy/MM/dd`——`TaskPeriod.dateSpan` 就是照這個格式解析的。
    private static func siteDate(_ date: Date) -> String {
        let parts = demoCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 「剩 N 天 M 小時可上傳」。上傳窗到期別最後一天結束為止，與 `TaskPeriod.hasEnded(now:)` 同界。
    private static func uploadRemainingText(periodEnd: Date, now: Date) -> String? {
        let calendar = demoCalendar
        guard let closesAt = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: periodEnd)),
              closesAt > now
        else { return nil }
        let seconds = Int(closesAt.timeIntervalSince(now))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        return days > 0 ? "剩 \(days) 天 \(hours) 小時可上傳" : "剩 \(hours) 小時可上傳"
    }
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

/// 不打網路的備份目錄。**示範模式與 Preview 一律用這一支**——`DemoMode` 明訂
/// 示範環境「不會發出任何網路請求」，那條界線不能為了一顆瀏覽按鈕破例。
/// 回空清單的效果是：券夾對已兌換的券找不到品項頁，那顆按鈕就不出現（與官網沒給連結時相同）。
public struct EmptyVendorCatalogService: VendorCatalogFetching {
    public init() {}

    public func fetch() async throws -> VendorCatalogBackup {
        VendorCatalogBackup(capturedAt: "", vendors: [])
    }
}
