import Foundation
import LocalAuthentication
import SwiftUI

/// 生物辨識（Face ID / Touch ID）解鎖。用於保護 App 存取與敏感個資顯示。
/// 設計：使用 `.deviceOwnerAuthentication`（生物辨識，失敗可退回裝置密碼）。
/// 若裝置未設定任何鎖（例如模擬器預設無密碼），視為「無法上鎖」→ 放行，
/// 但介面會提示使用者為裝置設定鎖以獲得保護，避免在開發環境把 App 卡死。
@MainActor
final class BiometricLock: ObservableObject {
    enum State: Equatable { case locked, unlocked, unavailable }

    @Published private(set) var state: State = .locked

    private let reason = "解鎖以保護你的個人資料"

    /// 裝置是否具備可用的鎖（生物辨識或密碼）。
    var canEvaluate: Bool {
        var error: NSError?
        let ok = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return ok
    }

    /// 嘗試解鎖。無可用鎖時標記為 unavailable 並放行。
    func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            state = .unavailable
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            state = ok ? .unlocked : .locked
        } catch {
            // 使用者取消或驗證失敗：維持鎖定，等待再次嘗試。不記錄任何細節。
            state = .locked
        }
    }

    /// 回到背景時重新上鎖。
    func relock() {
        if state == .unlocked { state = .locked }
    }
}

/// 把子畫面包在生物辨識鎖後面。可由設定開關（biometricLockEnabled）停用。
/// 預設 false：Onboarding 完成前完全不碰 Face ID，使用者在 Onboarding 最後一步選擇「啟用」才會變 true。
struct BiometricGate<Content: View>: View {
    @AppStorage("biometricLockEnabled") private var lockEnabled = false
    @StateObject private var lock = BiometricLock()
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if !lockEnabled || lock.state != .locked {
                content()
            } else {
                lockedScreen
            }
        }
        .task { await unlockIfNeeded() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await unlockIfNeeded() }
            } else if phase == .background {
                lock.relock()
            }
        }
    }

    private func unlockIfNeeded() async {
        guard lockEnabled, lock.state == .locked else { return }
        await lock.authenticate()
    }

    private var lockedScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "faceid")
                .font(.system(size: 56))
                .foregroundColor(Theme.Colors.primary)
            Text("揮汗有禮已鎖定")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text("以 Face ID 解鎖來保護你的個人資料")
                .font(.subheadline)
                .foregroundColor(Theme.Colors.muted)
                .multilineTextAlignment(.center)
            Button("解鎖") { Task { await lock.authenticate() } }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}
