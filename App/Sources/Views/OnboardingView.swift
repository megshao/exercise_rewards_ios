import SwiftUI
import SportsRewardsKit

/// 首次啟動導覽：
/// 1. 簡短歡迎頁。
/// 2. 強制填 3 欄位（身分證、生日、手機——個資最小化到登入必需，姓名/健保卡卡號/email
///    皆不在此收集）。
/// 3. 「送出並驗證」呼叫既有 `AuthServicing.login`（內部就是 `/access` 分流 + login）：
///    - `.success` → 存 Profile 到 Keychain → 直接完成，進主畫面。
///    - `.invalidCredentials` → 停在表單，提示「身分證/生日/手機有誤」。
///    - `.notRegistered` → **App 不做註冊**：顯示提示訊息＋「前往官網註冊」按鈕，
///      用外部 Safari 開官網 `https://500.gov.tw/registrant/access`；App 內完全不實作
///      任何註冊步驟、不碰健保卡。使用者需自行到官網完成註冊後回來重新登入。
///
/// App 不使用任何生物辨識：個資本來就只存在這支手機，手機本身的鎖屏已經是同一層保護，
/// 再加一層 Face ID 只是重複擋自己人。
struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(\.appEnvironment) private var environment
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var envStore: AppEnvironmentStore
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        Group {
            switch viewModel.step {
            case .welcome:
                welcomeStep
            case .form:
                formStep
            }
        }
        .background(Theme.Colors.background)
        .task {
            viewModel.configure(auth: environment.auth, profileStore: environment.profileStore,
                                 envStore: envStore, onFinish: onFinish)
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

                // 主標一律用上架名稱 Sports Rewards：刻意不拿活動名「揮汗有禮」自稱，
                // 避免被誤認為官方 App；活動名只出現在說明用途的副標裡。
                Text("Sports Rewards")
                    .font(Theme.displayFont(28, weight: .heavy))

                Text("協助你參加運動部「揮汗有禮」活動的非官方小工具\n每週達標，就能換一張超商加碼券")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            // 非官方聲明（App 內三處揭露之一：啟動頁／我的資料／App Store 商店描述）。
            disclaimerCard

            Text("首次使用需先完成身分驗證，資料只加密存在這支手機。")
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
        // E1：畫面瀏覽。歡迎頁與表單頁分開計，才看得出「開了 App 但沒進表單」的人數。
        .onAppear { Telemetry.screenAppeared(.onboardingWelcome) }
    }

    /// 首次啟動就把話講清楚：這是個人做的非官方工具，跟主辦單位沒有任何關係。
    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
            Text("本 App 由個人開發，是非官方工具，與運動部沒有任何隸屬或授權關係。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    // MARK: - Step 2：個資填寫 + 送出驗證

    private var formStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("填寫個人資料")
                        .font(Theme.displayFont(20, weight: .heavy))
                    Text("首次使用需完整填寫以下資料以驗證身分。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.muted)
                }

                VStack(alignment: .leading, spacing: 7) {
                    // 使用者正要輸入身分證號，這是全 App 最需要把話說準的一刻。
                    // 「不會寫入紀錄檔」在 Crashlytics 存在後語意變模糊，改成「不會把個資
                    // 寫進任何紀錄」——這句話即使在遙測開啟時也仍然為真。
                    Text("這三欄只加密存在這支手機，登入時直接送給 500.gov.tw。App 不會把個資寫進任何紀錄，也不會給第三方。")
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
        .onAppear { Telemetry.screenAppeared(.onboardingForm) }
    }

    /// `.notRegistered` 分支：本 App 不做註冊，只提示使用者先到官網完成註冊，
    /// 按鈕以外部 Safari 開啟（非 App 內 WebView）。
    private var notRegisteredCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("此身分證尚未在官網註冊，請先至官網完成註冊後再回來登入。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.text)

            Button {
                // E6：無參數。開啟的是固定 URL，不含任何使用者輸入。
                Telemetry.logEvent(.registerRedirect)
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

}

// MARK: - ViewModel

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Equatable {
        case welcome
        case form
    }

    @Published var step: Step = .welcome
    /// 主表單只收 3 欄（身分證/生日/手機）——個資最小化到登入必需。`Profile` 其餘欄位
    /// （name/email/nhiCardNo）維持預設空字串，App 從不收集。
    @Published var draft = Profile()
    @Published var isSubmitting = false
    @Published var formErrorMessage: String?

    /// `.notRegistered` 分支：App 不做註冊，只顯示提示＋「前往官網註冊」外部連結。
    @Published var isNotRegistered = false

    private var auth: AuthServicing?
    private var profileStore: ProfileStoring?
    private weak var envStore: AppEnvironmentStore?
    private var onFinish: (() -> Void)?

    func configure(auth: AuthServicing, profileStore: ProfileStoring,
                   envStore: AppEnvironmentStore, onFinish: @escaping () -> Void) {
        guard self.auth == nil else { return }
        self.auth = auth
        self.profileStore = profileStore
        self.envStore = envStore
        self.onFinish = onFinish
    }

    func startTapped() {
        step = .form
        Telemetry.setCrashKey(.onboardingStep(.form))
        // E2：無參數。
        Telemetry.logEvent(.tutorialBegin)
    }

    /// 3 欄位皆須非空、格式基本正確才允許送出。回傳 nil 代表通過。
    static func validate(_ profile: Profile) -> String? {
        validationFailure(profile)?.message
    }

    /// 驗證失敗時，同時給出「哪個欄位」（給遙測用的封閉列舉）與「給使用者看的訊息」。
    ///
    /// 遙測只拿 `field`：**不送長度、不送第一碼、不送使用者輸入的任何字元**。
    /// 四個值（empty / id_no / birth_date / phone）都無法反推出任何內容。
    static func validationFailure(_ profile: Profile) -> (field: OnboardingField, message: String)? {
        let idNo = profile.idNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let birth = profile.birthDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = profile.phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !idNo.isEmpty, !birth.isEmpty, !phone.isEmpty else {
            return (.empty, "請完整填寫身分證號、生日與手機號碼")
        }
        guard idNo.range(of: "^[A-Za-z][0-9]{9}$", options: .regularExpression) != nil else {
            return (.idNo, "身分證字號格式不正確")
        }
        guard birth.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
            return (.birthDate, "出生日期格式不正確")
        }
        guard phone.range(of: "^09[0-9]{8}$", options: .regularExpression) != nil else {
            return (.phone, "手機號碼格式不正確")
        }
        return nil
    }

    /// 送出並驗證：呼叫既有 `AuthServicing.login`（內部就是 `/access` 分流 + login）。
    func submitTapped() async {
        guard let auth, let profileStore else { return }
        if let failure = Self.validationFailure(draft) {
            isNotRegistered = false
            formErrorMessage = failure.message
            // E3：只送「哪個欄位格式不對」。
            Telemetry.logEvent(.onboardingValidationFailed(field: failure.field))
            return
        }
        formErrorMessage = nil
        isNotRegistered = false

        let credentials = LoginCredentials(idNo: draft.idNo, birthDate: draft.birthDate, phone: draft.phone)

        // 示範帳號（App Store 審查用）：不連線、不寫 Keychain，直接切進示範環境。
        // 哨兵值與理由見 DemoMode。
        if let envStore, envStore.enterDemoIfSentinel(credentials) {
            finish()
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        // 只量「按下送出到拿到結果」的耗時。憑證本身完全不經過 Telemetry。
        let startedAt = DispatchTime.now()
        do {
            let outcome = try await auth.login(credentials)
            let elapsed = Telemetry.elapsedMs(since: startedAt)
            switch outcome {
            case .success:
                Telemetry.setCrashKey(.sessionState(.loggedIn))
                // E4：只有 method（常數）／trigger／耗時，沒有 cookie、沒有 CSRF、沒有三碼。
                Telemetry.logEvent(.login(trigger: .onboarding, durationMs: elapsed))
                try profileStore.save(draft)
                finish()
            case .invalidCredentials:
                // 「三碼不符」只是官網 302 回 /login 的分類，我們不知道是哪一碼錯，也不想知道。
                Telemetry.logEvent(.loginFailed(trigger: .onboarding, reason: .invalidCredentials,
                                                netCode: nil, durationMs: elapsed))
                formErrorMessage = "身分證號、出生日期或手機號碼有誤，請確認後再試一次"
            case .notRegistered:
                Telemetry.logEvent(.loginFailed(trigger: .onboarding, reason: .notRegistered,
                                                netCode: nil, durationMs: elapsed))
                // App 不做註冊，只導向官網（見 formStep 的 notRegisteredCard）。
                isNotRegistered = true
            }
        } catch {
            let elapsed = Telemetry.elapsedMs(since: startedAt)
            // `/access` 與 `/login` 是公開頁：這裡失敗不可能是 session 過期，一律當改版訊號看。
            let reason = Telemetry.reportFailure(error, endpoint: .login)
            Telemetry.setCrashKey(.sessionState(.loginFailed))
            Telemetry.logEvent(.loginFailed(trigger: .onboarding, reason: reason,
                                            netCode: Telemetry.networkCode(from: error),
                                            durationMs: elapsed))
            formErrorMessage = "網路連線異常，請確認網路後再試一次"
        }
    }


    private func finish() {
        // E7：真實登入成功路徑。示範帳號也會走到這裡，但 `enterDemoIfSentinel` 已經先把
        // `isDemo` 設成 true，Telemetry 的示範模式閘門會把它擋掉——順序是對的。
        Telemetry.logEvent(.tutorialComplete)
        onFinish?()
    }
}
