import SwiftUI
import SportsRewardsKit

@main
struct HuihanApp: App {
    /// 目前生效的環境。正式為 `DefaultAppEnvironment()`（真實 AuthService/TasksService/
    /// KeychainStore/HealthKitReader）；審查員輸入示範帳號後切成 `DemoMode.makeEnvironment()`。
    @StateObject private var envStore = AppEnvironmentStore()

    /// 唯一一次 Firebase 初始化。沒有 GoogleService-Info.plist 時會安全跳過（不會 crash），
    /// 使用者沒開「傳送匿名使用統計」之前也不會送出任何東西。細節見 Telemetry.swift 檔頭。
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
            .preferredColorScheme(.light) // 設計為白底單一主題，鎖淺色避免深色模式白底白字
            // 全 App 鎖繁體中文（台灣）：系統提供的元件與數字/日期格式不會跟著裝置語系跑掉。
            .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
        }
    }
}

/// App 根導覽：先跑一次 Onboarding（首次啟動），之後進到主要的 TabView。
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// 已同意的免責聲明版本；0 代表從未同意。用版本號而非布林，是為了日後修改
    /// 聲明內容時能讓舊使用者重新同意（把 `DisclaimerView.currentVersion` 加一即可）。
    @AppStorage(DisclaimerConsent.versionKey) private var agreedVersion = 0

    var body: some View {
        Group {
            if agreedVersion < DisclaimerView.currentVersion {
                // 擋在 Onboarding 之前：使用者填第一個欄位之前就該知道這是非官方工具、
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

/// 主要 4 個分頁：首頁、任務、健康、券夾（對齊設計稿的 tabbar）。
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
                HealthView()
            }
            .tabItem {
                Label("健康", systemImage: "heart.fill")
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
}
