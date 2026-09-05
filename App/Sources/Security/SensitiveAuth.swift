import Foundation
import LocalAuthentication
import SwiftUI
import SportsRewardsKit

/// 動作級敏感驗證（B/C 規格）：在「進入個資設定」「儲存個資」「兌換」等敏感動作前重新驗證身份。
///
/// - 若已啟用 Face ID（`biometricLockEnabled`）且裝置可用 → `LocalAuthentication`
///   `.deviceOwnerAuthentication`（可退裝置密碼）。
/// - 若未啟用 Face ID（或裝置不可用）→ fallback：彈出表單只要求輸入手機號碼，
///   須與本機 `ProfileStoring` 讀出的 Profile 的 phone 去除空白後完全相符才算通過
///   （個資最小化：不再比對 email）。
/// - 取消／驗證失敗一律回傳 `false`，呼叫端不得執行該敏感動作。
/// - 絕不 log 手機號碼等個資。
///
/// 用法：由持有 `AppEnvironment` 的最上層畫面（見 `RootTabView`）建立單一實例、呼叫
/// `configure(profileStore:)` 並用 `.sensitiveAuthFallback(_:)` 掛上 fallback 表單一次，
/// 其餘畫面透過 `@EnvironmentObject` 拿到同一個實例後直接呼叫 `authorize(reason:)`。
@MainActor
final class SensitiveAuthCoordinator: ObservableObject {
    /// UserDefaults 直接讀取而非 @AppStorage：本類別非 View，@AppStorage 的自動失效機制
    /// 在此無意義，直接讀取即可拿到與 BiometricGate 相同的即時值。key 需與
    /// `BiometricGate`/Onboarding 的 `@AppStorage("biometricLockEnabled")` 完全一致。
    private static let biometricLockEnabledKey = "biometricLockEnabled"

    @Published var isPresentingFallback = false
    @Published var fallbackPhone = ""
    @Published var fallbackErrorMessage: String?
    @Published private(set) var fallbackReason = ""

    private var profileStore: ProfileStoring?
    private var pendingContinuation: CheckedContinuation<Bool, Never>?

    /// 與其他 ViewModel 的 `configure` 慣例一致：只綁定一次，重複呼叫忽略。
    func configure(profileStore: ProfileStoring) {
        guard self.profileStore == nil else { return }
        self.profileStore = profileStore
    }

    private var biometricLockEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.biometricLockEnabledKey)
    }

    private var canEvaluateBiometrics: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// 執行一次敏感動作驗證。`reason` 會顯示在 Face ID 系統對話框，以及 fallback 表單的說明文字。
    /// 回傳 `true` 才可以執行呼叫端的敏感動作；`false`（取消／失敗/不符）一律不執行。
    func authorize(reason: String) async -> Bool {
        if biometricLockEnabled, canEvaluateBiometrics {
            return await biometricAuthorize(reason: reason)
        }
        return await presentFallback(reason: reason)
    }

    private func biometricAuthorize(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            // 使用者取消或驗證失敗：不記錄任何細節，直接視為未通過。
            return false
        }
    }

    private func presentFallback(reason: String) async -> Bool {
        fallbackReason = reason
        fallbackPhone = ""
        fallbackErrorMessage = nil
        isPresentingFallback = true
        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation
        }
    }

    /// fallback 表單按下「驗證」時呼叫。相符才關閉表單並放行；不符只顯示錯誤、停留原地。
    func submitFallback() {
        guard let profileStore, let saved = try? profileStore.load() else {
            fallbackErrorMessage = "本機尚無個資，請先完成個資設定"
            return
        }
        guard Self.matches(inputPhone: fallbackPhone, saved: saved) else {
            fallbackErrorMessage = "手機號碼與本機資料不符，請再確認一次"
            return
        }
        isPresentingFallback = false
        resume(true)
    }

    /// fallback 表單按下「取消」或滑動關閉時呼叫。
    func cancelFallback() {
        isPresentingFallback = false
        resume(false)
    }

    /// 手機去除所有空白後完全相符才算通過（個資最小化：只比對手機，不再比對 email）。
    static func matches(inputPhone: String, saved: Profile) -> Bool {
        let phoneInput = inputPhone.filter { !$0.isWhitespace }
        let phoneSaved = saved.phone.filter { !$0.isWhitespace }
        guard !phoneInput.isEmpty else { return false }
        return phoneInput == phoneSaved
    }

    private func resume(_ value: Bool) {
        pendingContinuation?.resume(returning: value)
        pendingContinuation = nil
    }
}

/// Face ID 未啟用／裝置不可用時的 fallback 驗證表單：只輸入手機號碼，需與本機 Profile 完全相符。
struct SensitiveAuthFallbackView: View {
    @ObservedObject var coordinator: SensitiveAuthCoordinator

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("身份驗證")
                        .font(Theme.displayFont(18, weight: .heavy))
                    Text("請輸入手機號碼以驗證身分：\(coordinator.fallbackReason)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.muted)
                }

                VStack(spacing: 14) {
                    fallbackField(label: "手機號碼", text: $coordinator.fallbackPhone,
                                  placeholder: "09xxxxxxxx", keyboard: .phonePad)
                }

                if let message = coordinator.fallbackErrorMessage {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.danger)
                }

                Button {
                    coordinator.submitFallback()
                } label: {
                    Text("驗證")
                }
                .buttonStyle(.huihanPrimary)

                Spacer()
            }
            .padding(20)
            .background(Theme.Colors.background)
            .navigationTitle("身份驗證")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { coordinator.cancelFallback() }
                }
            }
        }
    }

    private func fallbackField(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.muted)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(size: 15))
                .foregroundColor(Theme.Colors.text)
                .tint(Theme.Colors.primary)
                .padding(14)
                .background(Theme.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .stroke(Theme.Colors.line2, lineWidth: 1)
                )
        }
    }
}

extension View {
    /// 掛在最上層一次即可：呈現 `SensitiveAuthCoordinator` 的 fallback 驗證表單。
    /// 滑動關閉（未按取消）也會視為取消，確保等待中的 `authorize(reason:)` 不會卡住。
    func sensitiveAuthFallback(_ coordinator: SensitiveAuthCoordinator) -> some View {
        sheet(isPresented: Binding(
            get: { coordinator.isPresentingFallback },
            set: { newValue in
                if !newValue { coordinator.cancelFallback() }
            }
        )) {
            SensitiveAuthFallbackView(coordinator: coordinator)
        }
    }
}
