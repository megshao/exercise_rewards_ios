import SwiftUI
import SportsRewardsKit

@main
struct HuihanApp: App {
    /// 正式環境：DefaultAppEnvironment() 已接真實 AuthService/TasksService/KeychainStore/HealthKitReader。
    private let environment: AppEnvironment = DefaultAppEnvironment()

    var body: some Scene {
        WindowGroup {
            BiometricGate {
                RootView()
            }
            .environment(\.appEnvironment, environment)
            .preferredColorScheme(.light) // 設計為白底單一主題，鎖淺色避免深色模式白底白字
        }
    }
}

/// App 根導覽：先跑一次 Onboarding（首次啟動），之後進到主要的 TabView。
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                RootTabView()
            } else {
                OnboardingView(onFinish: { hasCompletedOnboarding = true })
            }
        }
        .tint(Theme.Colors.primary)
    }
}

/// 主要 4 個分頁：首頁、任務、健康、券夾（對齊 design/Main.dc.html 的 tabbar）。
///
/// `SensitiveAuthCoordinator` 在此建立單一實例並透過 `.environmentObject` 往下傳給所有分頁
/// （進個資設定、儲存個資、兌換前的「敏感動作再驗證」共用同一個 coordinator），
/// fallback（email+手機）表單也只在這裡掛一次，蓋在整個 TabView 之上。
struct RootTabView: View {
    @Environment(\.appEnvironment) private var environment
    @StateObject private var sensitiveAuth = SensitiveAuthCoordinator()

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
        .environmentObject(sensitiveAuth)
        .sensitiveAuthFallback(sensitiveAuth)
        .task {
            sensitiveAuth.configure(profileStore: environment.profileStore)
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.appEnvironment, DefaultAppEnvironment())
}
