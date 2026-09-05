import SwiftUI
import LocalAuthentication
import SportsRewardsKit

/// 首次啟動導覽：
/// 1. 簡短歡迎頁。
/// 2. 強制填 3 欄位（身分證、生日、手機——個資最小化到登入必需，姓名/健保卡卡號/email
///    皆不在此收集）。
/// 3. 「送出並驗證」呼叫既有 `AuthServicing.login`（內部就是 `/access` 分流 + login）：
///    - `.success` → 存 Profile 到 Keychain → 進「是否啟用 Face ID」步驟。
///    - `.invalidCredentials` → 停在表單，提示「身分證/生日/手機有誤」。
///    - `.notRegistered` → **App 不做註冊**：顯示提示訊息＋「前往官網註冊」按鈕，
///      用外部 Safari 開官網 `https://500.gov.tw/registrant/access`；App 內完全不實作
///      任何註冊步驟、不碰健保卡。使用者需自行到官網完成註冊後回來重新登入。
/// 4. 是否啟用 Face ID（可略過）→ 完成，進主畫面。
///
/// **Onboarding 完成前完全不碰 Face ID**：只有使用者在最後一步主動按「啟用」才會觸發
/// LocalAuthentication 權限詢問並把 `biometricLockEnabled` 設成 true；按「略過」則維持
/// 預設 false，`BiometricGate` 因此不會在下次冷啟動彈生物辨識。
struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(\.appEnvironment) private var environment
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        Group {
            switch viewModel.step {
            case .welcome:
                welcomeStep
            case .form:
                formStep
            case .faceID:
                faceIDStep
            }
        }
        .background(Theme.Colors.background)
        .task {
            viewModel.configure(auth: environment.auth, profileStore: environment.profileStore, onFinish: onFinish)
        }
    }

    // MARK: - Step 1：歡迎

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Colors.primary)

                Text("揮汗有禮")
                    .font(Theme.displayFont(28, weight: .heavy))

                Text("達標換好禮\n每週就能領一張超商加碼券")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            Text("首次使用需先完成身份驗證，資料只加密存在這支手機。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                viewModel.startTapped()
            } label: {
                Text("開始使用")
            }
            .buttonStyle(.huihanPrimary)
        }
        .padding(24)
    }

    // MARK: - Step 2：個資填寫 + 送出驗證

    private var formStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("填寫個人資料")
                        .font(Theme.displayFont(20, weight: .heavy))
                    Text("首次使用需完整填寫以下資料以驗證身份。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.muted)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("以下資料只加密存在這支手機，不會上傳雲端、不會寫入紀錄檔。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(hex: 0x186C3E))
                }
                .padding(14)
                .background(Theme.Colors.successBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

                VStack(spacing: 16) {
                    ProfileField(label: "身分證號", text: $viewModel.draft.idNo, placeholder: "A123456789")

                    BirthDateField(isoDate: $viewModel.draft.birthDate)

                    ProfileField(label: "手機號碼", text: $viewModel.draft.phone,
                                 placeholder: "09xxxxxxxx", keyboard: .phonePad)
                }

                if viewModel.isNotRegistered {
                    notRegisteredCard
                } else if let message = viewModel.formErrorMessage {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.danger)
                }

                Button {
                    Task { await viewModel.submitTapped() }
                } label: {
                    Text("送出並驗證")
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isSubmitting))
            }
            .padding(20)
            .padding(.bottom, 40)
        }
    }

    /// `.notRegistered` 分支：本 App 不做註冊，只提示使用者先到官網完成註冊，
    /// 按鈕以外部 Safari 開啟（非 App 內 WebView）。
    private var notRegisteredCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("此身分證尚未在官網註冊，請先至官網完成註冊後再回來登入。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.text)

            Button {
                openURL(Self.registerURL)
            } label: {
                Text("前往官網註冊")
            }
            .buttonStyle(.huihanSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.Colors.line2, lineWidth: 1)
        )
    }

    private static let registerURL = URL(string: "https://500.gov.tw/registrant/access")!

    // MARK: - Step 3：是否啟用 Face ID

    private var faceIDStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Colors.primary)
            Text("啟用 Face ID？")
                .font(Theme.displayFont(22, weight: .heavy))
            Text("啟用後，App 啟動與個資設定、儲存、兌換等敏感動作都會用 Face ID 保護；\n未啟用則改以手機號碼驗證身份。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            if let message = viewModel.biometricErrorMessage {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Spacer()

            Button {
                Task { await viewModel.enableBiometricTapped() }
            } label: {
                Text("啟用 Face ID")
            }
            .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isRequestingBiometric))

            Button {
                viewModel.skipBiometricTapped()
            } label: {
                Text("略過")
            }
            .buttonStyle(.huihanSecondary)
        }
        .padding(24)
    }
}

// MARK: - ViewModel

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Equatable {
        case welcome
        case form
        case faceID
    }

    @Published var step: Step = .welcome
    /// 主表單只收 3 欄（身分證/生日/手機）——個資最小化到登入必需。`Profile` 其餘欄位
    /// （name/email/nhiCardNo）維持預設空字串，App 從不收集。
    @Published var draft = Profile()
    @Published var isSubmitting = false
    @Published var formErrorMessage: String?
    @Published var isRequestingBiometric = false
    @Published var biometricErrorMessage: String?

    /// `.notRegistered` 分支：App 不做註冊，只顯示提示＋「前往官網註冊」外部連結。
    @Published var isNotRegistered = false

    private var auth: AuthServicing?
    private var profileStore: ProfileStoring?
    private var onFinish: (() -> Void)?

    func configure(auth: AuthServicing, profileStore: ProfileStoring, onFinish: @escaping () -> Void) {
        guard self.auth == nil else { return }
        self.auth = auth
        self.profileStore = profileStore
        self.onFinish = onFinish
    }

    func startTapped() {
        step = .form
    }

    /// 3 欄位皆須非空、格式基本正確才允許送出。回傳 nil 代表通過。
    static func validate(_ profile: Profile) -> String? {
        let idNo = profile.idNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let birth = profile.birthDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = profile.phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !idNo.isEmpty, !birth.isEmpty, !phone.isEmpty else {
            return "請完整填寫身分證號、生日與手機號碼"
        }
        guard idNo.range(of: "^[A-Za-z][0-9]{9}$", options: .regularExpression) != nil else {
            return "身分證字號格式不正確"
        }
        guard birth.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
            return "出生日期格式不正確"
        }
        guard phone.range(of: "^09[0-9]{8}$", options: .regularExpression) != nil else {
            return "手機號碼格式不正確"
        }
        return nil
    }

    /// 送出並驗證：呼叫既有 `AuthServicing.login`（內部就是 `/access` 分流 + login）。
    func submitTapped() async {
        guard let auth, let profileStore else { return }
        if let error = Self.validate(draft) {
            isNotRegistered = false
            formErrorMessage = error
            return
        }
        formErrorMessage = nil
        isNotRegistered = false
        isSubmitting = true
        defer { isSubmitting = false }

        let credentials = LoginCredentials(idNo: draft.idNo, birthDate: draft.birthDate, phone: draft.phone)
        do {
            let outcome = try await auth.login(credentials)
            switch outcome {
            case .success:
                try profileStore.save(draft)
                step = .faceID
            case .invalidCredentials:
                formErrorMessage = "身分證號、出生日期或手機號碼有誤，請確認後再試一次"
            case .notRegistered:
                // App 不做註冊，只導向官網（見 formStep 的 notRegisteredCard）。
                isNotRegistered = true
            }
        } catch {
            formErrorMessage = "網路連線異常，請確認網路後再試一次"
        }
    }

    /// 使用者按「啟用 Face ID」：實際觸發一次生物辨識權限詢問，成功才把
    /// `biometricLockEnabled` 設成 true 並完成 Onboarding。
    func enableBiometricTapped() async {
        isRequestingBiometric = true
        biometricErrorMessage = nil
        defer { isRequestingBiometric = false }

        let context = LAContext()
        var evalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
            biometricErrorMessage = "此裝置尚未設定 Face ID / 裝置密碼，暫時無法啟用，可先「略過」"
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                       localizedReason: "啟用 Face ID 保護你的個人資料")
            if ok {
                UserDefaults.standard.set(true, forKey: "biometricLockEnabled")
                finish()
            } else {
                biometricErrorMessage = "驗證未通過，請再試一次，或選擇「略過」"
            }
        } catch {
            // 使用者取消或驗證失敗：不記錄任何細節，停在此步驟讓使用者可重試或略過。
            biometricErrorMessage = "驗證未通過，請再試一次，或選擇「略過」"
        }
    }

    /// 略過：維持預設 `biometricLockEnabled = false`，直接完成 Onboarding。
    func skipBiometricTapped() {
        finish()
    }

    private func finish() {
        onFinish?()
    }
}
