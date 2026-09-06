import SwiftUI
import SportsRewardsKit

/// 我的資料：3 欄位表單（身分證、生日、手機），存/讀透過 ProfileStoring（KeychainStore）。
/// 個資最小化到登入必需：姓名/email/健保卡卡號皆不在此收集，保留在 `Profile` model 中
/// （欄位不變，只是 UI 不收集），存 Keychain 時維持空字串。
///
/// 安全與隱私的所有選項（本機資料說明、一鍵清除）都直接放在這一層，
/// 不再多一層「資安中心」子頁——個資與保護個資的開關本來就該在同一個畫面看得完。
struct ProfileView: View {
    @Environment(\.appEnvironment) private var environment
    @EnvironmentObject private var envStore: AppEnvironmentStore
    @StateObject private var viewModel = ProfileViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showClearConfirm = false
    @State private var showCleared = false
    /// 「傳送匿名使用統計」開關。直接綁 Telemetry 用的同一個 UserDefaults 鍵，
    /// 所以「立即清除本機資料」重設偏好時，這個 Toggle 會自己跟著彈回去。
    @AppStorage(Telemetry.preferenceKey) private var telemetryEnabled = Telemetry.defaultEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                privacyBanner

                fieldGroup

                revealToggle

                securitySection

                footer
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(Theme.Colors.background)
        .navigationTitle("我的資料")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Telemetry.screenAppeared(.profile) }
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
        .task {
            viewModel.configure(profileStore: environment.profileStore)
            viewModel.load()
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
        .alert("已儲存到本機", isPresented: $viewModel.showSavedAlert) {
            Button("好", role: .cancel) {}
        }
        .alert("儲存失敗", isPresented: $viewModel.showErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "請稍後再試")
        }
    }

    // MARK: - 隱私聲明

    /// 明確聲明個資與健康資料的界線。
    ///
    /// **這段文字改過一次，原因要留著**：加了 Firebase（匿名使用統計）之後，原本第一點的
    /// 「也不會提供給任何第三方」就不再是一句無條件為真的話了。個資與健康資料的部分完全沒變
    /// ——仍然一個位元都不外傳；變的是「使用者自己打開使用統計之後，會有不含個資的操作事件
    /// 送給 Firebase」。所以這裡把界線拆成兩段講清楚，而不是把兩件事混在一句籠統的保證裡。
    private var privacyBanner: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(Theme.Colors.success)
                Text("個資不外傳，健康資料不出這支手機")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Color(hex: 0x186C3E))
            }

            VStack(alignment: .leading, spacing: 5) {
                privacyBullet("本 App 沒有伺服器也沒有後台。你的個資不會上傳雲端、不會同步 iCloud、不會寫進任何紀錄，也不會給第三方——這一點沒有例外。")
                privacyBullet("以下三個欄位只在你登入時，由這支手機直接送到官方網站 500.gov.tw；平常以加密方式存在這支手機（Keychain），可隨時用下方「立即清除本機資料」永久刪除。")
                privacyBullet("Apple 健康的步數、距離、運動時間只在這支手機上顯示，連「今天達標了沒」都不會被送出去。")
                privacyBullet("唯一會離開這支手機的是下方的「傳送匿名使用統計」：預設關閉，你自己打開之後，才會把「按了哪個按鈕、哪一步失敗、有沒有當機」送給 Google Firebase。裡面沒有個資、沒有健康數據、沒有你上傳的截圖與券碼。")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.successBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Color(hex: 0xB7E5CB), lineWidth: 1)
        )
    }

    private func privacyBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("・")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(Color(hex: 0x186C3E))
    }

    // MARK: - 欄位

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
                Text(viewModel.isRevealed ? "隱藏敏感欄位" : "敏感欄位已遮罩，點這裡顯示完整內容")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.dim)
            }
        }
    }

    // MARK: - 安全與隱私（原「資安中心」子頁的內容，直接展開在這一層）

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("安全與隱私")
            VStack(spacing: 0) {
                if envStore.isDemo {
                    demoRow
                    Divider().padding(.leading, 62)
                }
                localDataRow
                Divider().padding(.leading, 62)
                telemetryRow
                Divider().padding(.leading, 62)
                sourceCodeRow
                Divider().padding(.leading, 62)
                clearRow
            }
            .cardStyle(padding: 0)
        }
    }

    /// 只在示範模式下出現：讓審查員（或誤入的使用者）一鍵切回真實環境。
    private var demoRow: some View {
        Button {
            envStore.exitDemo()
            viewModel.load()
        } label: {
            HStack(spacing: 13) {
                iconBox("eye.fill", tint: Theme.Colors.text, bg: Color(hex: 0xEEF0F3))
                VStack(alignment: .leading, spacing: 2) {
                    Text("離開示範模式")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.Colors.text)
                    Text("目前顯示的是範例資料，未連線官方網站")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Colors.muted)
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

    private var localDataRow: some View {
        HStack(spacing: 13) {
            iconBox("lock.rectangle.stack.fill", tint: Theme.Colors.primary, bg: Color(hex: 0xFFF2E8))
            VStack(alignment: .leading, spacing: 2) {
                Text("本機資料")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                Text("僅這三個欄位加密存於本機 Keychain · 無伺服器 · 未同步 iCloud · 不把個資寫入紀錄")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(15)
    }

    /// 原始碼連結：隱私宣稱要能被查證才有意義，所以把 repo 直接放進 App，
    /// 而不是只寫在商店描述裡。以外部 Safari 開啟（不用 WebView，維持零 WebKit 依賴）。
    private var sourceCodeRow: some View {
        Link(destination: URL(string: "https://github.com/megshao/sports-rewards-ios")!) {
            HStack(spacing: 13) {
                iconBox("chevron.left.forwardslash.chevron.right",
                        tint: Theme.Colors.text, bg: Color(hex: 0xEEF0F3))
                VStack(alignment: .leading, spacing: 2) {
                    Text("原始碼")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.Colors.text)
                    Text("全部程式碼開源，這頁說的每一句都可以自己查證")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xC3C8D0))
            }
            .padding(15)
        }
        .buttonStyle(.plain)
    }

    /// 匿名使用統計開關。**預設關閉（opt-in）**：本 App 對外承諾「不蒐集、不外傳」，
    /// 預設開啟會直接抵觸那句話，所以要由使用者自己打開。
    /// 這裡只切偏好；真正的「送不送得出去」由 `Telemetry` 的閘門決定（示範模式一律不送）。
    ///
    /// 副標依開關狀態換句話講：關著的時候使用者最想確認的是「現在真的沒在送吧」，
    /// 開著的時候想確認的是「那到底送了什麼」。兩種狀態都要把「不含什麼」列完整，
    /// 也不用行銷語氣（「協助我們做得更好」那類）淡化這是一個把資料送給第三方的開關。
    private var telemetryRow: some View {
        HStack(spacing: 13) {
            iconBox("chart.bar.xaxis", tint: Theme.Colors.text, bg: Color(hex: 0xEEF0F3))
            VStack(alignment: .leading, spacing: 2) {
                Text("傳送匿名使用統計")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                Text(telemetryEnabled
                     ? "開啟中 · 送出操作事件與當機報告給 Google Firebase · 不含個資、健康數據、截圖、券碼 · 可隨時關掉"
                     : "預設關閉 · 目前不會有任何資料送到 Google · 打開後也不含個資、健康數據、截圖、券碼")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("傳送匿名使用統計", isOn: $telemetryEnabled)
                .labelsHidden()
                .tint(Theme.Colors.primary)
        }
        .padding(15)
        .onChange(of: telemetryEnabled) { newValue in
            // 開啟時會送 E28 `consent_granted`（同意後的第一個事件）；
            // 關閉時**不送任何事件**——使用者剛說不要，再送一筆等於沒聽到。
            Telemetry.setUserEnabled(newValue, source: .settings)
        }
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
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Colors.muted)
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

    /// 版本號讀 Info.plist 的 `CFBundleShortVersionString`，不硬編碼——避免哪天送審版本
    /// 改了卻忘了同步這行。名稱一律用上架名 Sports Rewards（活動名不拿來自稱）。
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    private var footer: some View {
        Text("Sports Rewards v\(appVersion) · 非官方工具\n個資不上雲 · 只連 500.gov.tw · 開了使用統計才會連 Firebase")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.Colors.dim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                viewModel.save()
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

    // MARK: - Helpers

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

    /// 清除本機所有資料：刪 Keychain 個資、重置 onboarding／健康授權旗標，回初次設定。
    private func clearLocalData() {
        // E26 必須在**這一行**送出：後面的 `Telemetry.resetPreference()` 會把偏好關掉並重置
        // app instance ID，那之後就再也送不出去了。順序＝先記錄、再重置、最後回到未同意狀態。
        Telemetry.logEvent(.localDataClear)
        envStore.exitDemo()
        try? environment.profileStore.clear()
        TasksCache.clear()
        // 遙測偏好也算「本機資料」：清除後回到預設的關閉狀態，並立刻停止收集。
        Telemetry.resetPreference()
        // 免責聲明的同意紀錄也屬於「初次設定狀態」的一部分：清除後下次開 App
        // 會再看到一次聲明。
        DisclaimerConsent.reset()
        UserDefaults.standard.removeObject(forKey: "com.megshao.sportsrewards.health.didRequestAuthorization")
        // 官方站的登入 cookie 是持久化在 App 沙盒容器、跨啟動續用的；只清 Keychain 個資
        // 並不會登出。不一併清掉就與這顆按鈕（與隱私說明）承諾的「清除本機所有資料」不符。
        let environment = environment
        Task { await environment.resetSession() }
        showCleared = true
        // 觸發回到 Onboarding（RootView 依 hasCompletedOnboarding 切換）。
        hasCompletedOnboarding = false
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
                    // 截圖用 UI 測試以欄位標籤定位輸入框（見 App/UITests/ScreenshotTests.swift）。
                    .accessibilityIdentifier(label)
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

// MARK: - 出生日期

/// 出生日期的純資料處理：ISO 字串 ↔ 年月日、民國換算、每月天數。
/// 全部用格里曆固定計算，不依賴裝置的行事曆/語系設定，顯示文字一律繁體中文。
enum BirthDate {
    struct Parts: Equatable {
        var year: Int
        var month: Int
        var day: Int
    }

    /// 可選年份範圍對齊官網：民國元年（1912）至 2009。
    static let years = Array(1912...2009)
    static let defaultParts = Parts(year: 1990, month: 1, day: 1)

    /// 解析 `yyyy-MM-dd`；格式不符或日期不存在（例如 2001-02-30）皆回 nil。
    static func parse(_ iso: String) -> Parts? {
        let pieces = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              let y = Int(pieces[0]), let m = Int(pieces[1]), let d = Int(pieces[2]),
              years.contains(y), (1...12).contains(m),
              (1...daysIn(year: y, month: m)).contains(d) else { return nil }
        return Parts(year: y, month: m, day: d)
    }

    static func iso(_ parts: Parts) -> String {
        String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
    }

    /// 「1990 年 5 月 20 日」
    static func display(_ parts: Parts) -> String {
        "\(parts.year) 年 \(parts.month) 月 \(parts.day) 日"
    }

    /// 「民國 79 年」——1912 為民國元年。
    static func rocYearText(_ year: Int) -> String {
        "民國 \(year - 1911) 年"
    }

    static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeap(year) ? 29 : 28
        default: return 31
        }
    }

    static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

/// 出生日期欄位：點一下開啟「年／月／日」三欄滾輪，可切換西元／民國年，
/// 全繁體中文（不吃裝置語系）。對外仍以 ISO `yyyy-MM-dd` 字串存回 Profile（與後端契約一致）。
/// 非 private：Onboarding 的個資填寫頁沿用同一元件維持樣式一致。
struct BirthDateField: View {
    @Binding var isoDate: String
    @State private var showPicker = false

    private var parts: BirthDate.Parts? { BirthDate.parse(isoDate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("出生日期")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.muted)

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.primary)

                    if let parts {
                        Text(BirthDate.display(parts))
                            .font(.system(size: 15))
                            .foregroundColor(Theme.Colors.text)
                        Text(BirthDate.rocYearText(parts.year))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.Colors.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.Colors.disabledBackground)
                            .clipShape(Capsule())
                    } else {
                        Text("請選擇出生日期")
                            .font(.system(size: 15))
                            .foregroundColor(Theme.Colors.dim)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC3C8D0))
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .stroke(Theme.Colors.line2, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("出生日期")
            .accessibilityValue(parts.map(BirthDate.display) ?? "尚未選擇")
        }
        .sheet(isPresented: $showPicker) {
            BirthDatePickerSheet(isoDate: $isoDate)
        }
    }
}

/// 出生日期滾輪：年／月／日三欄，可切換西元／民國。所有文字自備繁體中文，
/// 不使用系統 DatePicker，避免裝置語系是英文時整個日曆變英文。
struct BirthDatePickerSheet: View {
    @Binding var isoDate: String
    @Environment(\.dismiss) private var dismiss

    enum Era: String, CaseIterable { case ad, roc }

    @State private var era: Era = .roc
    @State private var year: Int
    @State private var month: Int
    @State private var day: Int

    init(isoDate: Binding<String>) {
        _isoDate = isoDate
        let parts = BirthDate.parse(isoDate.wrappedValue) ?? BirthDate.defaultParts
        _year = State(initialValue: parts.year)
        _month = State(initialValue: parts.month)
        _day = State(initialValue: parts.day)
    }

    private var selected: BirthDate.Parts { .init(year: year, month: month, day: day) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("年份表示", selection: $era) {
                    Text("民國").tag(Era.roc)
                    Text("西元").tag(Era.ad)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                wheels

                Text(summaryText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.muted)

                Button {
                    isoDate = BirthDate.iso(selected)
                    dismiss()
                } label: {
                    Text("完成")
                }
                .buttonStyle(.huihanPrimary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Theme.Colors.background)
            .navigationTitle("選擇出生日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
        }
        .presentationDetents([.height(440)])
    }

    private var wheels: some View {
        HStack(spacing: 0) {
            Picker("年", selection: $year) {
                ForEach(BirthDate.years, id: \.self) { y in
                    Text(era == .roc ? "民國 \(y - 1911) 年" : "西元 \(String(y)) 年").tag(y)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            Picker("月", selection: $month) {
                ForEach(1...12, id: \.self) { m in
                    Text("\(m) 月").tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 88)
            .clipped()

            Picker("日", selection: $day) {
                ForEach(1...BirthDate.daysIn(year: year, month: month), id: \.self) { d in
                    Text("\(d) 日").tag(d)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 88)
            .clipped()
        }
        .labelsHidden()
        .frame(height: 190)
        .padding(.horizontal, 12)
        // 換月/換年後把超出當月天數的日期收回來（例如 3/31 → 2 月時變 2/28）。
        .onChange(of: month) { _ in clampDay() }
        .onChange(of: year) { _ in clampDay() }
    }

    private func clampDay() {
        let maxDay = BirthDate.daysIn(year: year, month: month)
        if day > maxDay { day = maxDay }
    }

    /// 下方摘要固定同時顯示兩種年份，讓使用者一眼確認選對了。
    private var summaryText: String {
        "\(BirthDate.display(selected))（\(BirthDate.rocYearText(year))）"
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
            Self.recordStorageFailure(error, op: .load)
        }
    }

    func save() {
        guard let profileStore else { return }
        do {
            try profileStore.save(draft)
            showSavedAlert = true
            // E25：只有成功／失敗。`draft`（身分證、生日、手機）永遠不進 Telemetry。
            Telemetry.logEvent(.profileSave(outcome: .ok))
        } catch {
            errorMessage = "無法寫入本機安全儲存，請確認裝置已解鎖後再試一次。"
            showErrorAlert = true
            Telemetry.logEvent(.profileSave(outcome: .error))
            Self.recordStorageFailure(error, op: .save)
        }
    }

    /// Keychain 的操作代碼。只用於 N10 的 `op` 參數。
    private enum StorageOp: String, Sendable {
        case save
        case load
        case clear
    }

    /// N10：Keychain 失敗走 Crashlytics 非致命錯誤，不進 Analytics。
    ///
    /// 只送 `op` 與 `OSStatus`（例如 `errSecInteractionNotAllowed` = -25308，高頻代表
    /// 有背景讀取時機的問題）。**`Profile` 內容與 `data` 絕不附帶**；JSON 解碼失敗也只記
    /// 一個代碼，不附 `DecodingError`（它的 `debugDescription` 含欄位名與 coding path）。
    private static func recordStorageFailure(_ error: Error, op: StorageOp) {
        if let keychainError = error as? KeychainError, case .unhandled(let status) = keychainError {
            Telemetry.recordNonFatal(.keychain, extras: [
                "op": .code(op),
                "os_status": .int(Int(status)),
            ])
        } else {
            Telemetry.recordNonFatal(.profileDecode, extras: ["op": .code(op)])
        }
    }

    // MARK: Masking

    var maskedIdNo: String { Self.mask(draft.idNo, prefix: 1, suffix: 2) }
    var maskedPhone: String { Self.mask(draft.phone, prefix: 4, suffix: 3) }

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
