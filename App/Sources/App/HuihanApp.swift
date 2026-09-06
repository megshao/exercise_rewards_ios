import SwiftUI
import SportsRewardsKit

@main
struct HuihanApp: App {
    /// 目前生效的環境。正式為 `DefaultAppEnvironment()`（真實 AuthService/TasksService/
    /// KeychainStore）；審查員輸入示範帳號後切成 `DemoMode.makeEnvironment()`。
    @StateObject private var envStore = AppEnvironmentStore()

    /// 「已使用」標記的單一真相來源。首頁／任務／券夾是同時活著的三個分頁，
    /// 必須共用同一份才會一起更新（見 `VoucherUsageStore` 的說明）。
    @StateObject private var voucherUsage = VoucherUsageStore()

    /// 唯一一次 Firebase 初始化。沒有 GoogleService-Info.plist 時會安全跳過（不會 crash），
    /// 使用者同意免責聲明之前不會初始化 Firebase，也不會送出任何東西。細節見 Telemetry.swift 檔頭。
    ///
    /// **這裡刻意不送任何「App 啟動了」事件**：Firebase 自己就有 `first_open` 與
    /// `session_start`（同意前不會產生），再自己補一個 `app_launched` 只是把同一件事
    /// 數兩次。
    init() {
        Telemetry.configure()
    }

    var body: some Scene {
        WindowGroup {
            // 用 VStack 讓橫幅真的佔版面（safeAreaInset 會蓋在 TabView 內容上，把首頁問候語壓掉）。
            VStack(spacing: 0) {
                // 截圖模式（只有 XCUITest 的啟動參數能開，見 ScreenshotMode）會把橫幅收起來，
                // 讓上架素材的畫面上緣乾淨。真機使用者與 App Store 審查員都不可能帶啟動參數，
                // 他們進示範模式時橫幅一定照常出現。
                if envStore.isDemo && !ScreenshotMode.isEnabled { DemoModeBanner() }
                RootView()
            }
            .environment(\.appEnvironment, envStore.environment)
            .environmentObject(envStore)
            .environmentObject(voucherUsage)
            // 進出示範模式時 `AppEnvironmentStore` 會清掉持久化的「已使用」標記
            // （示範資料與真實資料的期別 UUID 不可混用）。這裡把畫面上那份一起歸零，
            // 否則標記會留在畫面上直到下次冷啟動。
            .onChange(of: envStore.isDemo) { _ in
                voucherUsage.clear()
            }
            .preferredColorScheme(.light) // 設計為白底單一主題，鎖淺色避免深色模式白底白字
            // 全 App 鎖繁體中文（台灣）：系統提供的元件與數字/日期格式不會跟著裝置語系跑掉。
            .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
        }
    }
}

/// App 根導覽。首次啟動的順序：**歡迎 → 免責聲明 → 個資填寫 → 主畫面**。
///
/// **為什麼歡迎頁排在免責聲明之前**：免責聲明是一整頁條款，第一次開 App 就直接撞上它，
/// 使用者連「這是什麼 App」都還不知道就要決定同不同意。先給一頁「這是什麼、誰做的」，
/// 按下「開始使用」表示願意繼續，再請他讀條款——同意才是有前提的。
///
/// **這個順序對遙測的影響**：`Telemetry.configure()` 仍然只在同意的那一刻被呼叫，
/// 所以歡迎頁完全在「Firebase 一行都還沒執行」的階段（那句話仍然為真）。
/// 代價是歡迎頁不能埋任何事件——漏斗第一步 `tutorial_begin` 因此移到表單出現時才送。
struct RootView: View {
    /// 是否看過歡迎頁。與免責聲明的同意分開存：同意紀錄有版本號（改條款要重新同意），
    /// 而歡迎頁看過就算看過，不該因為條款改版又跳一次。
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// 已同意的免責聲明版本；0 代表從未同意。用版本號而非布林，是為了日後修改
    /// 聲明內容時能讓舊使用者重新同意（把 `DisclaimerView.currentVersion` 加一即可）。
    @AppStorage(DisclaimerConsent.versionKey) private var agreedVersion = 0

    var body: some View {
        Group {
            if !hasSeenWelcome {
                WelcomeView(onStart: { hasSeenWelcome = true })
            } else if agreedVersion < DisclaimerView.currentVersion {
                // 擋在個資填寫之前：使用者填第一個欄位之前就該知道這是非官方工具、
                // 以及活動問題該找誰。
                DisclaimerView(onAgree: { DisclaimerConsent.record() })
            } else if hasCompletedOnboarding {
                RootTabView()
            } else {
                OnboardingView(onFinish: { hasCompletedOnboarding = true })
            }
        }
        .tint(Theme.Colors.primary)
    }
}

/// 主要 3 個分頁：首頁、任務、券夾。
///
struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("首頁", systemImage: "house.fill")
            }

            NavigationStack {
                TasksView()
            }
            .tabItem {
                Label("任務", systemImage: "checkmark.seal.fill")
            }

            NavigationStack {
                WalletView()
            }
            .tabItem {
                Label("券夾", systemImage: "ticket.fill")
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.appEnvironment, DefaultAppEnvironment())
        .environmentObject(AppEnvironmentStore())
        .environmentObject(VoucherUsageStore())
}
