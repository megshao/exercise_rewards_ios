import Foundation
import SwiftUI
import SportsRewardsKit

/// 送審用「示範模式」（Demo Mode）。
///
/// **為什麼需要**：本 App 的登入需要真實身分證號、出生日期、手機號碼，且帳號屬於官方網站
/// `500.gov.tw`（App 不做註冊）。App Store 審查員拿不到這樣一組真實憑證，沒有示範模式就完全
/// 無法走完主要流程。
///
/// **刻意不做成隱藏手勢**：示範模式的入口就是一般使用者也看得到的登入表單——只要輸入下列
/// 這組哨兵值即可進入。這組值與 App Store Connect 的示範帳號欄位同步，是**完整揭露的功能**。
///
/// **安全性**：`A000000000` 不是合法的中華民國身分證號（檢查碼不符），真實使用者不可能誤觸。
/// 進入示範模式後整個 App 改用 `Mock*Service`，**不會發出任何網路請求**，個資也只留在
/// 記憶體（`InMemoryProfileStore`），絕不寫入 Keychain。
enum DemoMode {
    /// 示範帳號三碼。修改這裡就要同步更新 App Store Connect 的示範帳號欄位。
    static let idNo = "A000000000"
    static let birthDate = "1990-01-01"
    static let phone = "0900000000"

    /// 是否處於示範模式（跨啟動保留，讓審查員關掉 App 再開仍在示範狀態）。
    static let storageKey = "demoModeEnabled"

    /// 示範模式下預先填好的個資（只存在記憶體）。
    static var profile: Profile {
        Profile(idNo: idNo, birthDate: birthDate, phone: phone)
    }

    static func matches(_ credentials: LoginCredentials) -> Bool {
        matches(idNo: credentials.idNo, birthDate: credentials.birthDate, phone: credentials.phone)
    }

    static func matches(_ profile: Profile) -> Bool {
        matches(idNo: profile.idNo, birthDate: profile.birthDate, phone: profile.phone)
    }

    /// 身分證號大小寫皆可、前後空白忽略——審查員手動輸入時容錯。
    static func matches(idNo: String, birthDate: String, phone: String) -> Bool {
        normalized(idNo).caseInsensitiveCompare(Self.idNo) == .orderedSame
            && normalized(birthDate) == Self.birthDate
            && normalized(phone) == Self.phone
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 示範環境：全部服務換成 Mock，個資改用記憶體儲存（不碰 Keychain）。
    static func makeEnvironment() -> AppEnvironment {
        DefaultAppEnvironment(
            auth: MockAuthService(delaySeconds: 0.4),
            tasks: MockTasksService(delaySeconds: 0.4),
            redeem: MockRedeemService(delaySeconds: 0.4),
            voucher: MockVoucherService(delaySeconds: 0.4),
            profileStore: InMemoryProfileStore(seed: profile),
            upload: MockUploadService()
        )
    }
}

/// 截圖模式：只用來在擷取上架素材時隱藏示範模式橫幅。
///
/// **只能由啟動參數開啟**：唯一的開關是**行程啟動參數**
/// （`ProcessInfo.processInfo.arguments`），而啟動參數只有 XCUITest／偵錯工具在啟動 App 時
/// 才給得出來。從 App Store 安裝的使用者不論怎麼操作（手勢、設定、輸入任何值）都無法讓
/// 這支 App 帶著這個參數啟動；這是 fastlane snapshot 那類截圖工具的標準做法。
///
/// **界線在哪（日後改動請守住）**：
/// - 只讀 `ProcessInfo.arguments`，**不可以**改讀 UserDefaults／Keychain／檔案等任何
///   使用者寫得進去的地方（`-uiTestScreenshotMode` 沒有配對的值，也不會進 NSArgumentDomain）。
/// - 只能影響「畫面上要不要畫示範橫幅」，**不可以**拿來改資料來源、跳過驗證或解鎖任何功能。
/// - 審查員實際輸入示範帳號操作時不會帶啟動參數，因此橫幅一定照常出現。
enum ScreenshotMode {
    /// 啟動參數名稱。XCUITest 端寫在 `App/UITests/ScreenshotTests.swift`。
    static let launchArgument = "-uiTestScreenshotMode"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

/// 示範模式專用的個資儲存：只在記憶體，App 一關就沒了，**絕不寫入 Keychain**。
/// 預先塞好示範個資，讓審查員一進入就有完整資料可看，不必再填一次表單。
final class InMemoryProfileStore: ProfileStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Profile?

    init(seed: Profile? = nil) {
        self.stored = seed
    }

    func save(_ profile: Profile) throws {
        lock.lock(); defer { lock.unlock() }
        stored = profile
    }

    func load() throws -> Profile? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}

/// 持有「當前生效的 AppEnvironment」，並負責在真實環境與示範環境之間切換。
/// 由 `HuihanApp` 建立單一實例，透過 `.environmentObject` 往下傳。
@MainActor
final class AppEnvironmentStore: ObservableObject {
    @Published private(set) var environment: AppEnvironment
    @Published private(set) var isDemo: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let demo = defaults.bool(forKey: DemoMode.storageKey)
        self.isDemo = demo
        self.environment = demo ? DemoMode.makeEnvironment() : DefaultAppEnvironment()
    }

    /// 憑證命中示範帳號就切進示範模式。回傳是否命中。
    @discardableResult
    func enterDemoIfSentinel(_ credentials: LoginCredentials) -> Bool {
        guard DemoMode.matches(credentials) else { return false }
        enterDemo()
        return true
    }

    func enterDemo() {
        guard !isDemo else { return }
        defaults.set(true, forKey: DemoMode.storageKey)
        // 真實任務快取不能留在示範畫面上（反之亦然），兩個方向都清。
        // 「已使用」標記也一樣：它是綁期別 UUID 的，示範資料與真實資料不可混用。
        TasksCache.clear()
        VoucherUsage.clear()
        // 這裡清的是持久層；畫面上那份由 `HuihanApp` 監看 `isDemo` 一起歸零
        // （`AppEnvironmentStore` 刻意不持有 View 層的 store）。
        environment = DemoMode.makeEnvironment()
        isDemo = true
        // 示範模式一律不送遙測與當機報告，SDK 層也一起關掉（不只靠 Telemetry 的閘門）。
        Telemetry.demoModeDidChange()
    }

    func exitDemo() {
        guard isDemo else { return }
        defaults.set(false, forKey: DemoMode.storageKey)
        TasksCache.clear()
        VoucherUsage.clear()
        environment = DefaultAppEnvironment()
        isDemo = false
        // 離開示範模式後，收集狀態回到使用者自己的偏好。
        Telemetry.demoModeDidChange()
    }
}

/// 示範模式常駐橫幅：讓審查員（與任何誤入的使用者）隨時知道畫面上是範例資料。
struct DemoModeBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.fill")
                .font(.system(size: 11, weight: .bold))
            Text("示範模式 · 畫面為範例資料，未連線官方網站")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        // 底色往上延伸蓋過狀態列，但版面高度仍只佔文字這條，不會壓到下面的內容。
        .background(Theme.Colors.text.ignoresSafeArea(edges: .top))
    }
}
