import SwiftUI
import SportsRewardsKit
import LocalAuthentication

/// 我的資料：3 欄位表單（身分證、生日、手機），存/讀透過 ProfileStoring（KeychainStore）。
/// 個資最小化到登入必需：姓名/email/健保卡卡號皆不在此收集，保留在 `Profile` model 中
/// （欄位不變，只是 UI 不收集），存 Keychain 時維持空字串。
struct ProfileView: View {
    @Environment(\.appEnvironment) private var environment
    @EnvironmentObject private var sensitiveAuth: SensitiveAuthCoordinator
    @StateObject private var viewModel = ProfileViewModel()
    @AppStorage("biometricLockEnabled") private var biometricEnabled = false
    @State private var showBiometricUnavailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                privacyBanner

                fieldGroup

                revealToggle

                faceIDCard

                NavigationLink {
                    SettingsView()
                } label: {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                        Text("資安中心")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                }
                .buttonStyle(.plain)
                .cardStyle(padding: 16)
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(Theme.Colors.background)
        .navigationTitle("我的資料")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
        .task {
            viewModel.configure(profileStore: environment.profileStore)
            viewModel.load()
        }
        .alert("此裝置無法使用 Face ID / Touch ID", isPresented: $showBiometricUnavailable) {
            Button("好", role: .cancel) {}
        } message: {
            Text("請先在系統設定啟用 Face ID／Touch ID 或裝置密碼。未啟用時，敏感操作將改以手機號碼驗證。")
        }
        .alert("已儲存到本機", isPresented: $viewModel.showSavedAlert) {
            Button("好", role: .cancel) {}
        }
        .alert("儲存失敗", isPresented: $viewModel.showErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "請稍後再試")
        }
    }

    /// Face ID 解鎖開關。啟用時檢查裝置是否支援；不支援則不開並提示。
    private var faceIDCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "faceid")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 34, height: 34)
                .background(Color(hex: 0xFFF2E8))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Face ID 解鎖")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                Text("開啟 App 與敏感操作時以生物辨識驗證")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Colors.muted)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { biometricEnabled },
                set: { newValue in
                    if newValue && !Self.biometricsAvailable() {
                        biometricEnabled = false
                        showBiometricUnavailable = true
                    } else {
                        biometricEnabled = newValue
                    }
                }
            ))
            .labelsHidden()
            .tint(Theme.Colors.primary)
        }
        .cardStyle(padding: 16)
    }

    private static func biometricsAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    private var privacyBanner: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Theme.Colors.success)
            Text("以下資料只加密存在這支手機，不會上傳雲端、不會寫入紀錄檔。")
                .font(.system(size: 12.5))
                .foregroundStyle(Color(hex: 0x186C3E))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.Colors.successBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Color(hex: 0xB7E5CB), lineWidth: 1)
        )
    }

    private var fieldGroup: some View {
        VStack(spacing: 16) {
            ProfileField(
                label: "身分證號",
                text: $viewModel.draft.idNo,
                placeholder: "A123456789",
                sensitive: true,
                isRevealed: viewModel.isRevealed,
                maskedText: viewModel.maskedIdNo
            )

            BirthDateField(isoDate: $viewModel.draft.birthDate)

            ProfileField(
                label: "手機號碼",
                text: $viewModel.draft.phone,
                placeholder: "09xxxxxxxx",
                sensitive: true,
                isRevealed: viewModel.isRevealed,
                maskedText: viewModel.maskedPhone,
                keyboard: .phonePad
            )
            // email/健保卡卡號/姓名不在此收集：個資最小化到登入必需三欄。
        }
    }

    private var revealToggle: some View {
        Button {
            viewModel.isRevealed.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isRevealed ? "eye.slash.fill" : "lock.fill")
                    .foregroundStyle(Theme.Colors.dim)
                Text(viewModel.isRevealed ? "隱藏敏感欄位" : "敏感欄位以 Face ID 解鎖後才顯示完整內容")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.dim)
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task {
                    // 敏感動作再驗證：儲存個資前先過 Face ID（或未啟用時的手機號碼 fallback）。
                    if await sensitiveAuth.authorize(reason: "驗證身份以儲存個資") {
                        viewModel.save()
                    }
                }
            } label: {
                Text("儲存到本機")
            }
            .buttonStyle(.huihanPrimary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .background(Theme.Colors.card)
    }
}

/// 單一欄位輸入元件。所有欄位皆可直接輸入；敏感欄位在「未聚焦且已有值、且未展開」時
/// 以遮罩顯示，點一下即可聚焦編輯真實內容。文字色固定為深色，避免深色模式白底白字。
/// 非 private：Onboarding 的個資填寫頁沿用同一元件維持樣式一致。
struct ProfileField: View {
    let label: String
    var sublabel: String? = nil
    @Binding var text: String
    var placeholder: String = ""
    var sensitive: Bool = false
    var isRevealed: Bool = true
    var maskedText: String? = nil
    var keyboard: UIKeyboardType = .default
    @FocusState private var focused: Bool

    /// 是否要蓋上遮罩（僅敏感欄位、未展開、未聚焦、且已有值時）。
    private var showMasked: Bool {
        sensitive && !isRevealed && !focused && !text.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.muted)
                if let sublabel {
                    Text(sublabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.dim)
                }
            }
            ZStack(alignment: .leading) {
                TextField(placeholder, text: $text)
                    .focused($focused)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.Colors.text)
                    .tint(Theme.Colors.primary)
                    .opacity(showMasked ? 0 : 1)
                if showMasked {
                    Text(maskedText ?? "")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.Colors.text)
                        .allowsHitTesting(false)
                }
            }
            .padding(14)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .stroke(focused ? Theme.Colors.primary : Theme.Colors.line2,
                            lineWidth: focused ? 1.5 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
    }
}

/// 出生日期欄位：日曆選擇，對外仍以 ISO `yyyy-MM-dd` 字串存回 Profile（與後端契約一致）。
/// 可選範圍對齊官網：民國元年（1912-01-01）至 2009-12-31。
/// 非 private：Onboarding 的個資填寫頁沿用同一元件維持樣式一致。
struct BirthDateField: View {
    @Binding var isoDate: String

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var range: ClosedRange<Date> {
        let lower = Self.iso.date(from: "1912-01-01") ?? Date(timeIntervalSince1970: 0)
        let upper = Self.iso.date(from: "2009-12-31") ?? Date()
        return lower...upper
    }

    private var selection: Binding<Date> {
        Binding(
            get: { Self.iso.date(from: isoDate) ?? (Self.iso.date(from: "2000-01-01") ?? Date()) },
            set: { isoDate = Self.iso.string(from: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("出生日期")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.muted)
            HStack {
                DatePicker("", selection: selection, in: range, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Theme.Colors.primary)
                Spacer()
                if !isoDate.isEmpty {
                    Text(isoDate)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.muted)
                }
            }
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

// MARK: - ViewModel

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var draft = Profile()
    @Published var isRevealed = false
    @Published var showSavedAlert = false
    @Published var showErrorAlert = false
    @Published var errorMessage: String?

    private var profileStore: ProfileStoring?

    func configure(profileStore: ProfileStoring) {
        guard self.profileStore == nil else { return }
        self.profileStore = profileStore
    }

    func load() {
        guard let profileStore else { return }
        do {
            if let saved = try profileStore.load() {
                draft = saved
            }
        } catch {
            errorMessage = "讀取失敗，請重新輸入。"
            showErrorAlert = true
        }
    }

    func save() {
        guard let profileStore else { return }
        do {
            try profileStore.save(draft)
            showSavedAlert = true
        } catch {
            errorMessage = "無法寫入本機安全儲存，請確認裝置已解鎖後再試一次。"
            showErrorAlert = true
        }
    }

    // MARK: Masking

    var maskedIdNo: String { Self.mask(draft.idNo, prefix: 1, suffix: 2) }
    var maskedPhone: String { Self.mask(draft.phone, prefix: 4, suffix: 3) }
    var maskedNHICardNo: String { Self.mask(draft.nhiCardNo, prefix: 4, suffix: 4) }

    private static func mask(_ value: String, prefix: Int, suffix: Int) -> String {
        guard !value.isEmpty else { return "" }
        let chars = Array(value)
        guard chars.count > prefix + suffix else { return String(repeating: "●", count: chars.count) }
        let head = String(chars[0..<prefix])
        let tail = String(chars[(chars.count - suffix)...])
        let dots = String(repeating: "●", count: chars.count - prefix - suffix)
        return head + dots + tail
    }
}
