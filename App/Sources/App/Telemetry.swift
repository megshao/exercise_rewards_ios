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
// **哪些資料絕對不准進來**（新增事件前請逐條對照）：
//   1. 個資：身分證號、出生日期、手機號碼、姓名、email、健保卡號——這三欄是 App 唯一收集的
//      個資，只在登入當下直送 500.gov.tw，任何形式（原文、雜湊、截斷、拼接）都不得進入遙測。
//   2. HealthKit 衍生值：步數、距離、卡路里、達標與否的實際數字、任何從健康資料算出來的量。
//   3. 官方站識別碼：登入 session / cookie / CSRF token、活動期數對應的個人任務 id、
//      使用者在 500.gov.tw 上的任何帳號識別。
//   4. 券碼：兌換碼、券序號、條碼內容、以及任何可以拿去核銷的字串。
//   5. 自由文字：使用者輸入的任何內容、伺服器回傳的原始錯誤訊息（未經 `Redact.scrub`）。
//
// **為什麼 HealthKit 資料不可外傳**：這不是我們的偏好，是 Apple 的硬性規定。
// App Store Review Guideline 5.1.3 與 HealthKit 的使用條款明訂：從 HealthKit 讀到的資料
// 不得分享給第三方做廣告、資料探勘或類似用途，也不得在未經使用者明示同意下傳給任何第三方。
// Firebase Analytics 就是第三方。因此步數這類數值**連「匿名彙總」都不做**——
// 需要知道「使用者有沒有在用健康分頁」時，只送不含數值的畫面瀏覽事件。
// Info.plist 的 `NSHealthShareUsageDescription` 也已經對使用者承諾了「不會被上傳」。

// MARK: - 事件定義

/// 允許被送出的畫面名稱。**刻意做成封閉列舉**：畫面名不可以是自由字串，
/// 否則哪天有人寫 `screenViewed(name: voucher.code)` 就直接把券碼送出去了。
enum ScreenName: String, Sendable {
    case onboarding
    case home
    case tasks
    case health
    case wallet
    case profile
    case redeem
    case voucher
    case upload
}

/// 遙測參數的值。限制成三種純量，讓「參數裡塞了一個結構化的個資物件」在編譯期就不可能發生。
enum AnalyticsValue: Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)

    /// 轉成 Firebase 收得的型別。
    var firebaseValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .bool(let value): return value ? 1 : 0
        }
    }

    /// 只有字串需要過敏感樣式偵測；Int/Bool 不可能夾帶個資。
    var stringPayload: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// 全 App 允許送出的事件。之後要接真實事件，**只擴充這個 enum**，不要在別處直接呼叫 SDK。
///
/// 目前只放三個明顯安全的佔位事件；實際要埋哪些事件由 `docs/analytics-plan.md` 決定。
enum AnalyticsEvent: Sendable {
    /// App 冷啟動。無參數。
    case appLaunched
    /// 畫面瀏覽。只帶封閉列舉的畫面名，不帶任何畫面上的資料。
    case screenViewed(ScreenName)
    /// 使用者切換「傳送匿名使用統計」開關。
    /// 關閉那一次仍然會送（在關閉生效之前），才知道有多少人主動關掉。
    case telemetryPreferenceChanged(enabled: Bool)

    /// Firebase 事件名。用 snake_case（Firebase 慣例），長度 <= 40。
    var name: String {
        switch self {
        case .appLaunched: return "app_launched"
        case .screenViewed: return AnalyticsEventScreenView
        case .telemetryPreferenceChanged: return "telemetry_preference_changed"
        }
    }

    var parameters: [String: AnalyticsValue] {
        switch self {
        case .appLaunched:
            return [:]
        case .screenViewed(let screen):
            return [AnalyticsParameterScreenName: .string(screen.rawValue)]
        case .telemetryPreferenceChanged(let enabled):
            return ["enabled": .bool(enabled)]
        }
    }
}

/// 允許設定的使用者屬性。同樣是封閉列舉，而且**只允許布林**——
/// 使用者屬性會附加在往後所有事件上，是最容易不小心變成「準識別碼」的地方。
enum UserProperty: Sendable {
    /// 是否已授權讀取步數。只有「有沒有授權」，不含任何健康數值。
    case healthAuthorizationGranted(Bool)
    /// 是否已完成初次設定。
    case onboardingCompleted(Bool)

    var name: String {
        switch self {
        case .healthAuthorizationGranted: return "health_auth_granted"
        case .onboardingCompleted: return "onboarding_completed"
        }
    }

    var value: String {
        switch self {
        case .healthAuthorizationGranted(let granted): return granted ? "true" : "false"
        case .onboardingCompleted(let completed): return completed ? "true" : "false"
        }
    }
}

/// 當機報告上的自訂鍵。同樣封閉，避免有人拿 crash key 當成「順手記一下使用者是誰」的地方。
enum CrashKey: Sendable {
    /// 目前是否處於示範模式（實際上示範模式不會送任何東西，這個鍵只在極端情況下有意義）。
    case isDemoMode(Bool)
    /// 當機前最後一個畫面。
    case lastScreen(ScreenName)

    var name: String {
        switch self {
        case .isDemoMode: return "is_demo_mode"
        case .lastScreen: return "last_screen"
        }
    }

    var value: String {
        switch self {
        case .isDemoMode(let demo): return demo ? "true" : "false"
        case .lastScreen(let screen): return screen.rawValue
        }
    }
}

// MARK: - 遙測出口

/// 全 App 唯一的遙測出口。
///
/// 所有方法都可以從任何執行緒呼叫；Firebase 的 `Analytics` 與 `Crashlytics` 對此是安全的，
/// 而本外殼自己的狀態只有一個 `UserDefaults` 旗標與一個 atomic 的 `configured` 布林。
enum Telemetry {
    /// 使用者偏好的 `UserDefaults` 鍵。ProfileView 的 Toggle 直接綁這個鍵。
    static let preferenceKey = "telemetryEnabled"

    /// **預設關閉（opt-in）**。
    ///
    /// 暫定值：這支 App 對外的承諾是「不蒐集、不外傳」，預設開啟遙測會直接抵觸那句話，
    /// 所以先站在最保守的一邊。若 `docs/analytics-plan.md` 的評估結論是 opt-out 比較合適，
    /// 再改這一個常數即可（Info.plist 的 `FIREBASE_ANALYTICS_COLLECTION_ENABLED` /
    /// `FirebaseCrashlyticsCollectionEnabled` 也要一起改）。
    static let defaultEnabled = false

    private static let log = SecureLog(.security)

    /// Firebase 是否真的初始化成功。沒有 GoogleService-Info.plist 時會是 false，
    /// 所有 API 都變成 no-op。用 `os_unfair_lock` 等級的東西太重，這裡用 NSLock 保護。
    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var isConfigured = false

    // MARK: 初始化

    /// 在 App 啟動時呼叫一次（`HuihanApp.init()`）。
    ///
    /// **絕不 crash**：`FirebaseApp.configure()` 在找不到 `GoogleService-Info.plist` 時會
    /// `fatalError`，所以這裡**先自己檢查檔案存在**，不存在就完全跳過初始化。
    /// 這讓 repo 在不含真實設定檔的情況下仍然可以 clone、build、跑起來。
    static func configure() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            log.debug("找不到 GoogleService-Info.plist，跳過 Firebase 初始化（遙測全程 no-op）")
            return
        }

        FirebaseApp.configure()
        stateLock.lock()
        isConfigured = true
        stateLock.unlock()

        // Info.plist 已經把兩邊的預設收集都關掉了；這裡依使用者當前偏好把狀態同步一次，
        // 讓「使用者上次選的」在每次冷啟動都確實生效，而不是依賴 SDK 自己的持久化。
        applyCollectionFlags(enabled: isUserEnabled)
        log.debug("Firebase 初始化完成，遙測偏好=\(isUserEnabled)")
    }

    private static var configured: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return isConfigured
    }

    // MARK: 使用者偏好

    /// 使用者是否同意傳送匿名使用統計。
    static var isUserEnabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? defaultEnabled
    }

    /// 使用者在「我的資料 › 安全與隱私」切換開關時呼叫。
    ///
    /// 呼叫端可能是 SwiftUI 的 `@AppStorage` binding，偏好值在進到這裡之前就已經寫好了，
    /// 所以「使用者關掉遙測」這個事件必須用 `bypassingUserPreference` 送——
    /// 它是使用者剛剛按下的動作本身，不是後續的追蹤，而且是最後一個事件。
    static func setUserEnabled(_ enabled: Bool) {
        if !enabled {
            // 先送出「使用者關掉了」，再真的關掉——否則永遠拿不到這個數字。
            logEvent(.telemetryPreferenceChanged(enabled: false), bypassingUserPreference: true)
        }

        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        applyCollectionFlags(enabled: enabled)

        if enabled { logEvent(.telemetryPreferenceChanged(enabled: true)) }
        log.debug("遙測偏好改為 \(enabled)")
    }

    /// 「立即清除本機資料」時呼叫：把偏好重設回預設值（opt-in ⇒ 關閉）並立刻停止收集。
    static func resetPreference() {
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        applyCollectionFlags(enabled: defaultEnabled)
        log.debug("遙測偏好已重設為預設值（\(defaultEnabled)）")
    }

    /// 同步 SDK 兩邊的收集開關。示範模式下一律關閉，不管使用者偏好是什麼。
    private static func applyCollectionFlags(enabled: Bool) {
        guard configured else { return }
        let allowed = enabled && !isDemoModeActive
        Analytics.setAnalyticsCollectionEnabled(allowed)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(allowed)
    }

    /// 進出示範模式時呼叫，讓 SDK 的收集狀態跟著切換。
    static func demoModeDidChange() {
        applyCollectionFlags(enabled: isUserEnabled)
    }

    // MARK: 隱私閘門

    /// 示範模式旗標。直接讀 `UserDefaults`（`AppEnvironmentStore` 也是寫這個鍵），
    /// 避免為了讀一個布林把這裡綁到 `@MainActor`。
    private static var isDemoModeActive: Bool {
        UserDefaults.standard.bool(forKey: DemoMode.storageKey)
    }

    /// 被擋下來的原因。回傳 nil 代表通過。
    private enum Block {
        case notConfigured
        case demoMode
        case userDisabled
        case sensitive(field: String, kinds: Set<Redact.SensitiveKind>)

        var reason: String {
            switch self {
            case .notConfigured: return "Firebase 未初始化"
            case .demoMode: return "示範模式"
            case .userDisabled: return "使用者已關閉遙測"
            case .sensitive(let field, let kinds):
                let list = kinds.map(\.rawValue).sorted().joined(separator: ",")
                return "欄位 \(field) 命中敏感樣式 [\(list)]"
            }
        }
    }

    /// 送出前的三道閘門：初始化 → 開關（示範模式 / 使用者偏好）→ 內容掃描。
    /// 這是**機制**而不是自律：呼叫端沒有繞過它的路。
    private static func gate(
        eventName: String,
        parameters: [String: AnalyticsValue],
        requireUserOptIn: Bool = true
    ) -> Block? {
        guard configured else { return .notConfigured }
        // 示範模式排在使用者偏好前面：審查員可能把開關打開，仍然一個字都不能送。
        // 這一關**沒有任何 bypass**。
        guard !isDemoModeActive else { return .demoMode }
        if requireUserOptIn { guard isUserEnabled else { return .userDisabled } }

        // 事件名本身也掃一次。名稱來自封閉列舉，理論上不可能中；中了代表有人改壞了 enum。
        let nameKinds = Redact.sensitiveKinds(in: eventName)
        if !nameKinds.isEmpty { return .sensitive(field: "event_name", kinds: nameKinds) }

        for (key, value) in parameters {
            if let text = value.stringPayload {
                let kinds = Redact.sensitiveKinds(in: text)
                if !kinds.isEmpty { return .sensitive(field: key, kinds: kinds) }
            }
            let keyKinds = Redact.sensitiveKinds(in: key)
            if !keyKinds.isEmpty { return .sensitive(field: "key:\(key)", kinds: keyKinds) }
        }
        return nil
    }

    /// 處理被擋下來的事件。
    ///
    /// **敏感樣式命中時在 DEBUG build 直接 `assertionFailure`**：這種情況一定是程式寫錯了
    /// （某個個資被接到遙測參數上），要在開發期就爆出來，而不是在正式版靜靜地被丟掉——
    /// 靜靜丟掉會讓下一個人以為「反正閘門會擋」而放心亂接。
    /// 其他原因（未初始化 / 示範模式 / 使用者關閉）是**預期中的正常狀態**，只記 debug log。
    private static func handle(_ block: Block, eventName: String) {
        if case .sensitive = block {
            #if DEBUG
            assertionFailure(
                "遙測事件 \(eventName) 夾帶疑似個資（\(block.reason)）。"
                + "請改成不含個資的參數，不要放寬 Redact 的樣式。"
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
        logEvent(event, bypassingUserPreference: false)
    }

    /// `bypassingUserPreference` 只給 `setUserEnabled(false)` 用——參數是 private，
    /// 一般呼叫端拿不到這條路。示範模式與敏感樣式兩道閘門仍然照常生效。
    private static func logEvent(_ event: AnalyticsEvent, bypassingUserPreference bypass: Bool) {
        let parameters = event.parameters
        if let block = gate(
            eventName: event.name,
            parameters: parameters,
            requireUserOptIn: !bypass
        ) {
            handle(block, eventName: event.name)
            return
        }
        Analytics.logEvent(event.name, parameters: parameters.mapValues(\.firebaseValue))
    }

    /// 設定使用者屬性。值只可能是 "true"/"false"，一樣走完整閘門。
    static func setUserProperty(_ property: UserProperty) {
        if let block = gate(eventName: property.name, parameters: ["value": .string(property.value)]) {
            handle(block, eventName: "user_property:\(property.name)")
            return
        }
        Analytics.setUserProperty(property.value, forName: property.name)
    }

    /// 設定當機報告的自訂鍵。
    static func setCrashKey(_ key: CrashKey) {
        if let block = gate(eventName: key.name, parameters: ["value": .string(key.value)]) {
            handle(block, eventName: "crash_key:\(key.name)")
            return
        }
        Crashlytics.crashlytics().setCustomValue(key.value, forKey: key.name)
    }

    /// 記錄一個非致命錯誤。
    ///
    /// **刻意不直接把 `Error` 交給 Crashlytics**：`NSError` 的 `userInfo` 與
    /// `localizedDescription` 常常夾帶伺服器回傳的原文（可能含個資），而 Crashlytics 的
    /// `record(error:)` 會把整包 userInfo 一起送走。這裡只取 domain / code，
    /// 訊息一律先過 `Redact.scrub`，再組一個乾淨的 `NSError` 送出。
    static func recordError(_ error: Error, context: String = "") {
        let nsError = error as NSError
        let scrubbedContext = Redact.scrub(context)
        let scrubbedMessage = Redact.scrub(nsError.localizedDescription)

        // scrub 後再掃一次：樣式沒認出來的東西不該進 Crashlytics。
        let payload = "\(scrubbedContext) \(scrubbedMessage)"
        if let block = gate(eventName: "non_fatal_error", parameters: ["payload": .string(payload)]) {
            handle(block, eventName: "non_fatal_error(\(nsError.domain)#\(nsError.code))")
            return
        }

        let sanitized = NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: [
                NSLocalizedDescriptionKey: scrubbedMessage,
                "context": scrubbedContext,
            ]
        )
        Crashlytics.crashlytics().record(error: sanitized)
    }
}
