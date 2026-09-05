import SwiftUI
import SportsRewardsKit
import LocalAuthentication

/// 設定・資安中心：Face ID 開關（與「我的資料」頁共用同一個 biometricLockEnabled）、
/// 本機資料說明、立即清除本機資料。對齊 design/Settings.dc.html。
struct SettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @AppStorage("biometricLockEnabled") private var biometricEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showBiometricUnavailable = false
    @State private var showClearConfirm = false
    @State private var showCleared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("資安中心")
                VStack(spacing: 0) {
                    faceIDRow
                    Divider().padding(.leading, 62)
                    localDataRow
                    Divider().padding(.leading, 62)
                    clearRow
                }
                .cardStyle(padding: 0)

                footer
            }
            .padding(20)
        }
        .background(Theme.Colors.background)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .alert("此裝置無法使用 Face ID / Touch ID", isPresented: $showBiometricUnavailable) {
            Button("好", role: .cancel) {}
        } message: {
            Text("請先在系統設定啟用 Face ID／Touch ID 或裝置密碼。未啟用時，敏感操作將改以 email＋手機驗證。")
        }
        .alert("清除本機所有資料？", isPresented: $showClearConfirm) {
            Button("清除", role: .destructive) { clearLocalData() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("將刪除本機儲存的個人資料與登入狀態，App 會回到初次設定畫面。此動作無法復原。")
        }
        .alert("已清除", isPresented: $showCleared) {
            Button("好", role: .cancel) {}
        } message: {
            Text("本機資料已刪除。")
        }
    }

    // MARK: Rows

    private var faceIDRow: some View {
        HStack(spacing: 13) {
            iconBox("faceid", tint: Theme.Colors.primary, bg: Color(hex: 0xFFF2E8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Face ID 解鎖").font(.system(size: 14.5, weight: .semibold))
                Text("開啟 App 與敏感操作時以生物辨識驗證")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.Colors.muted)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { biometricEnabled },
                set: { on in
                    if on && !Self.biometricsAvailable() {
                        biometricEnabled = false
                        showBiometricUnavailable = true
                    } else { biometricEnabled = on }
                }
            ))
            .labelsHidden().tint(Theme.Colors.primary)
        }
        .padding(15)
    }

    private var localDataRow: some View {
        HStack(spacing: 13) {
            iconBox("lock.rectangle.stack.fill", tint: Theme.Colors.primary, bg: Color(hex: 0xFFF2E8))
            VStack(alignment: .leading, spacing: 2) {
                Text("本機資料").font(.system(size: 14.5, weight: .semibold))
                Text("個資加密存於 Keychain · 未同步 iCloud · 不寫入紀錄檔")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.Colors.muted)
            }
            Spacer()
        }
        .padding(15)
    }

    private var clearRow: some View {
        Button {
            showClearConfirm = true
        } label: {
            HStack(spacing: 13) {
                iconBox("trash.fill", tint: Theme.Colors.danger, bg: Color(hex: 0xFDECEB))
                VStack(alignment: .leading, spacing: 2) {
                    Text("立即清除本機資料")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.Colors.danger)
                    Text("刪除個資與登入狀態，回到初次設定")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.Colors.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xC3C8D0))
            }
            .padding(15)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Text("揮汗有禮 v0.1 · 非官方工具\n個資不上雲 · 不寫紀錄檔 · 只連 500.gov.tw")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.Colors.dim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    private func iconBox(_ name: String, tint: Color, bg: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 17))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Colors.dim)
            .padding(.leading, 4)
    }

    // MARK: Actions

    /// 清除本機所有資料：刪 Keychain 個資、重置 onboarding／Face ID／健康授權旗標，回初次設定。
    private func clearLocalData() {
        try? environment.profileStore.clear()
        TasksCache.clear()
        biometricEnabled = false
        UserDefaults.standard.removeObject(forKey: "com.megshao.sportsrewards.health.didRequestAuthorization")
        showCleared = true
        // 觸發回到 Onboarding（RootView 依 hasCompletedOnboarding 切換）。
        hasCompletedOnboarding = false
    }

    private static func biometricsAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
}
