import Foundation
import SportsRewardsKit

/// 假的登入服務，供 UI 開發與 Preview 使用。
/// // TODO: wire real SportsRewardsKit implementations — 換成同事實作的 AuthService(http:)。
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
/// // TODO: wire real SportsRewardsKit implementations — 換成同事實作的 TasksService(http:)。
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

    public func screenshotImageURL(taskID: String) async throws -> URL {
        try await Task.sleep(nanoseconds: 300_000_000)
        // 假資料：模擬 302 導向後的 S3 presigned 圖片網址，供 Preview 直接用 AsyncImage 載入。
        guard let url = URL(string: "https://picsum.photos/seed/\(taskID)/600/800") else {
            throw AppError.unexpectedResponse(0)
        }
        return url
    }

    public static let defaultSample: [TaskPeriod] = [
        TaskPeriod(id: "period-1", index: 1, startDate: "09/01", endDate: "09/06",
                   state: .redeemable, remainingText: "剩 1 天 22 小時可兌換",
                   uploadedAt: "09/03 21:42", reviewedAt: "09/04 20:10 通過"),
        TaskPeriod(id: "period-2", index: 2, startDate: "09/07", endDate: "09/13",
                   state: .open, remainingText: nil),
        TaskPeriod(id: "period-3", index: 3, startDate: "09/14", endDate: "09/20",
                   state: .pendingReview, remainingText: "已上傳 · 5 個工作日內完成審核"),
        TaskPeriod(id: "period-4", index: 4, startDate: "09/21", endDate: "09/27",
                   state: .notStarted, remainingText: nil),
        TaskPeriod(id: "period-5", index: 5, startDate: "09/28", endDate: "10/04",
                   state: .notStarted, remainingText: nil),
    ]
}

/// 假的兌換服務，回傳範例商家品項清單，供 UI 開發與 Preview 使用。
/// // TODO: wire real SportsRewardsKit implementations — 換成同事實作的 RedeemService(http:)。
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

    public static let defaultSample: [RedeemOption] = [
        RedeemOption(vendorId: "1", vendorName: "全家便利商店", itemName: "50+3元加碼券", itemId: "item-demo-family"),
        RedeemOption(vendorId: "2", vendorName: "7-11", itemName: "50+5元加碼券", itemId: "item-demo-711"),
        RedeemOption(vendorId: "3", vendorName: "萊爾富", itemName: "50元加碼券", itemId: "item-demo-hilife"),
        RedeemOption(vendorId: "5", vendorName: "全聯", itemName: "50元加碼券", itemId: "item-demo-pxmart"),
    ]
}

/// 假的檢視加碼券服務，供 UI 開發與 Preview 使用。可設定 OTP 情境（一次驗證成功／錯誤幾次／
/// 傳送失敗），`fetchVoucher` 回傳範例券碼（比照 Fixtures/voucher_view.html 的萊爾富兩段式券）。
/// // TODO: wire real SportsRewardsKit implementations — 換成 VoucherService(http:)。
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
/// // TODO: wire real SportsRewardsKit implementations — 換成 HealthKitReader()。
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
/// // TODO: R1 upload file 欄位名待實測 — 換成真正的 UploadService（見 UploadService.swift）。
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
