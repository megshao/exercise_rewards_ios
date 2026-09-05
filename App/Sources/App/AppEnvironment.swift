import Foundation
import SportsRewardsKit

/// App 端依賴注入容器。ViewModel 只依賴 SportsRewardsKit 的 protocol（AuthServicing / TasksServicing /
/// ProfileStoring），不依賴具體實作，方便同事平行開發真正的網路層時互不阻塞。
public protocol AppEnvironment: Sendable {
    var auth: AuthServicing { get }
    var tasks: TasksServicing { get }
    var redeem: RedeemServicing { get }
    var voucher: VoucherServicing { get }
    var profileStore: ProfileStoring { get }
    var health: HealthReading { get }
    var upload: UploadServicing { get }
}

/// 預設環境：接真實的 SportsRewardsKit 實作。單一 `URLSessionHTTPClient`（記憶體 cookie，
/// 白名單只認 500.gov.tw）同時供 Auth 與 Tasks 共用，確保登入後的 session cookie 一路帶著。
/// profileStore 為真實 KeychainStore（WhenUnlockedThisDeviceOnly、不同步 iCloud）。
/// Preview／測試可透過帶參數的 init 傳入 Mock*Service。
public struct DefaultAppEnvironment: AppEnvironment {
    public let auth: AuthServicing
    public let tasks: TasksServicing
    public let redeem: RedeemServicing
    public let voucher: VoucherServicing
    public let profileStore: ProfileStoring
    public let health: HealthReading
    public let upload: UploadServicing

    /// 正式環境：共用一個 HTTP client 串起 Auth / Tasks / Redeem / Voucher，確保登入後的
    /// session cookie 一路帶著；健康資料唯讀接 HealthKit（never transmitted）；上傳接真實
    /// UploadService（multipart POST /member/upload，file 欄位 screenshot；R1 已實測）。
    public init() {
        let http = URLSessionHTTPClient()
        self.auth = AuthService(http: http)
        self.tasks = TasksService(http: http)
        self.redeem = RedeemService(http: http)
        self.voucher = VoucherService(http: http)
        self.profileStore = KeychainStore()
        self.health = HealthKitReader()
        self.upload = UploadService(http: http)
    }

    /// 可注入版本：Preview／測試傳入 Mock。
    public init(
        auth: AuthServicing,
        tasks: TasksServicing,
        redeem: RedeemServicing,
        voucher: VoucherServicing,
        profileStore: ProfileStoring = KeychainStore(),
        health: HealthReading = HealthKitReader(),
        upload: UploadServicing = UploadServiceStub()
    ) {
        self.auth = auth
        self.tasks = tasks
        self.redeem = redeem
        self.voucher = voucher
        self.profileStore = profileStore
        self.health = health
        self.upload = upload
    }
}

// MARK: - Environment key

import SwiftUI

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment = DefaultAppEnvironment()
}

public extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
