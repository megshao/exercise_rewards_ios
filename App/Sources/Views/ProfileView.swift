import SwiftUI
import ExerciseRewardsKit

/// 我的資料：3 個欄位（身分證、生日、手機）**唯讀**顯示，讀取透過 ProfileStoring（KeychainStore）。
/// 個資最小化到登入必需：姓名/email/健保卡卡號皆不在此收集，保留在 `Profile` model 中
/// （欄位不變，只是 UI 不收集），存 Keychain 時維持空字串。
///
/// **為什麼這一頁不給改**：這三個欄位是官網的登入憑證，存在本機只是免得每次登入重打。
/// 在這裡改掉不會動到官網上的任何東西，只會讓下一次登入失敗——而且失敗的原因
/// （憑證被改過）從畫面上完全看不出來。要換成另一個身分，唯一正確的做法是把這支手機上的
/// 資料清乾淨再以新身分登入，也就是下方那顆「立即登出並清除本機資料」。
///
/// 安全與隱私的所有選項（本機資料說明、使用統計、原始碼）都直接放在這一層，
/// 不再多一層「資安中心」子頁——個資與保護個資的開關本來就該在同一個畫面看得完。
/// 清除／換帳號**刻意不放在那張清單裡**（見 `switchAccountButton`）。
struct ProfileView: View {
    @Environment(\.appEnvironment) private var environment
    @EnvironmentObject private var envStore: AppEnvironmentStore
    @EnvironmentObject private var voucherUsage: VoucherUsageStore
    /// 廠商品項頁的本機紀錄，也算「本機資料」，登出時要一起清（見 `clearLocalData`）。
    @EnvironmentObject private var vendorIntro: VendorIntroStore
    @StateObject private var viewModel = ProfileViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showClearConfirm = false
    @State private var showCleared = false
    /// 「傳送匿名使用統計」開關。直接綁 Telemetry 用的同一個 UserDefaults 鍵，
    /// 所以「立即登出並清除本機資料」重設偏好時，這個 Toggle 會自己跟著彈回去。
    @AppStorage(Telemetry.preferenceKey) private var telemetryEnabled = Telemetry.defaultEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                privacyBanner

                fieldGroup

                revealToggle

                securitySection

                switchAccountButton

                footer
            }
            .padding(20)
        }
        .background(Theme.Colors.background)
        .navigationTitle("我的資料")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Telemetry.screenAppeared(.profile) }
        .task {
            viewModel.configure(profileStore: environment.profileStore)
            viewModel.load()
        }
        .alert("登出並清除本機資料？", isPresented: $showClearConfirm) {
            Button("登出並清除", role: .destructive) { clearLocalData() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("將登出並刪除這支手機上儲存的個人資料與登入狀態，App 會回到初次設定畫面，你可以用另一組身分登入。官方網站上的活動紀錄不受影響。此動作無法復原。")
        }
        .alert("已登出", isPresented: $showCleared) {
            Button("好", role: .cancel) {}
        } message: {
            Text("本機資料已刪除，請重新登入。")
        }
        .alert("讀取失敗", isPresented: $viewModel.showErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "請稍後再試")
        }
    }

    // MARK: - 隱私聲明

    /// 明確聲明個資的界線。
    ///
    /// **這段文字改過一次，原因要留著**：加了 Firebase（匿名使用統計）之後，原本第一點的
    /// 「也不會提供給任何第三方」就不再是一句無條件為真的話了。個資的部分完全沒變
    /// ——仍然一個位元都不外傳；變的是「會有不含個資的操作事件送給 Firebase」。
    /// 所以這裡把界線拆成兩段講清楚，而不是把兩件事混在一句籠統的保證裡。
    private var privacyBanner: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(Theme.Colors.success)
                Text("個資不外傳，只在登入時送給官方網站")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Color(hex: 0x186C3E))
            }

            VStack(alignment: .leading, spacing: 5) {
                privacyBullet("本 App 沒有伺服器也沒有後台。你的個資不會上傳雲端、不會同步 iCloud、不會寫進任何紀錄，也不會給第三方——這一點沒有例外。")
                privacyBullet("以下三個欄位只在你登入時，由這支手機直接送到官方網站 500.gov.tw；平常以加密方式存在這支手機（Keychain），可隨時用下方「立即登出並清除本機資料」永久刪除。")
                // 唯讀是刻意的，而且理由跟隱私無關（改了不會外傳，只是會登不進去）。
                // 放在這一段講，是因為使用者第一個疑問就是「為什麼不能改」。
                privacyBullet("三個欄位只能檢視、不能修改：它們是官網的登入憑證，在這裡改掉不會變更官網上的資料，只會讓下次登入失敗。要換成另一個身分，請用下方「立即登出並清除本機資料」。")
                // 剪貼簿是一條新的資料路徑（與其他 App 共用），要在講個資界線的地方一併揭露，
                // 不能只藏在那顆按鈕旁邊的小字裡。
                privacyBullet("官網改版、App 讀不到頁面時，畫面上會多一顆「複製身分證號」讓你到官網少打一欄。只有你按下它才會複製，而且只複製身分證號；內容只留在這支手機的剪貼簿約 3 分鐘、不同步到其他裝置，時間到自動清除。")
                privacyBullet("唯一會離開這支手機的是下方的「傳送匿名使用統計」：把「按了哪個按鈕、哪一步失敗、有沒有當機」送給 Google Firebase，用來修 bug。裡面沒有個資、沒有你上傳的截圖與券碼，不想送可以在下面關掉。")
                // 只下載、零上傳的那條連線也要講。放在最後一點，因為它是三種對外行為裡
                // 影響最小的一種——但「影響小」不是可以不說的理由。
                privacyBullet("券夾在找不到某張券的品項頁時，會去 GitHub 下載一份公開的商品目錄備份檔（所有人同一份）。那次連線不送出任何資料，但對方會看到你的 IP 與時間；在這個 App 裡兌換過的券本來就記得，不會用到它。")
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

    /// 三欄一律唯讀（見檔頭說明）。生日**不遮罩**——原本的 `BirthDateField` 也沒有遮，
    /// 敏感度與身分證號／手機不同級，這裡維持一致而不順手加嚴。
    private var fieldGroup: some View {
        VStack(spacing: 16) {
            ProfileValueRow(
                label: "身分證號",
                value: viewModel.draft.idNo,
                maskedValue: viewModel.maskedIdNo,
                isRevealed: viewModel.isRevealed
            )

            ProfileValueRow(
                label: "出生日期",
                value: viewModel.birthDateDisplay,
                badge: viewModel.birthDateRocText
            )

            ProfileValueRow(
                label: "手機號碼",
                value: viewModel.draft.phone,
                maskedValue: viewModel.maskedPhone,
                isRevealed: viewModel.isRevealed
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
                // 清除／換帳號不在這張清單裡：它是這一頁唯一會改變狀態的動作，
                // 混在幾個唯讀說明與一個開關中間太容易被當成另一個設定項。
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
        Link(destination: URL(string: "https://github.com/megshao/exercise_rewards_ios")!) {
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

    /// 匿名使用統計開關。**同意免責聲明後預設開啟，使用者可隨時關掉（opt-out）**。
    ///
    /// 為什麼不是 opt-in：當機報告是最需要收到的東西，而藏在設定頁裡等人自己發現，
    /// 實際開啟率低到樣本沒有意義。改成在**首次啟動的免責聲明**把這件事明講
    /// （見 `DisclaimerView`），使用者讀過並主動勾選同意之後才初始化 Firebase——
    /// 保障放在「送之前一定先告知」，而不是「預設不送」。
    ///
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
                     ? "開啟中 · 送出操作事件與當機報告給 Google Firebase · 不含個資、截圖、券碼 · 可隨時關掉"
                     : "已關閉 · 目前不會有任何資料送到 Google · 重新打開也不含個資、截圖、券碼")
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

    /// 換帳號的唯一手段，所以從「安全與隱私」清單裡拉出來獨立成一顆按鈕。
    ///
    /// 一顆按鈕同時是「清除本機資料」與「換帳號」：這兩件事在這支 App 裡本來就是同一個動作
    /// ——沒有伺服器、沒有帳號切換 API，換身分就是把這支手機上的憑證清掉再重新登入。
    /// 標題把使用者要的結果（重新登入）放前面，把代價（清除本機資料）明講在後面，
    /// 而不是只寫「清除」讓人猜得到不到自己想要的東西。
    ///
    /// padding 與背景一律畫在 label **裡面**並加 `.buttonStyle(.plain)`，整塊才都可點
    /// （兌換頁那顆「兌換」就是因為加在 Button 外面，八成面積點不到）。
    private var switchAccountButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("換帳號")

            Button {
                showClearConfirm = true
            } label: {
                HStack(spacing: 13) {
                    iconBox("person.crop.circle.badge.xmark",
                            tint: Theme.Colors.danger, bg: Color(hex: 0xFDECEB))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("立即登出並清除本機資料")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(Theme.Colors.danger)
                        Text("刪除這支手機上的個資與登入狀態，回到初次設定後以另一組身分登入")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC3C8D0))
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .stroke(Theme.Colors.danger.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            // label 是個容器（圖示＋標題＋副標＋箭頭），XCUITest 會把子元素的 label 串成一長串，
            // 用標題查不到這顆按鈕——所以給它一個明確的 id（比照 `voucherRevealButton`）。
            .accessibilityIdentifier("switchAccountButton")
        }
    }

    /// 版本號讀 Info.plist 的 `CFBundleShortVersionString`，不硬編碼——避免哪天送審版本
    /// 改了卻忘了同步這行。名稱一律用上架名 Exercise Rewards（活動名不拿來自稱）。
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    private var footer: some View {
        // 「只連 500.gov.tw」在 1.1 之後不再為真（多了一個唯讀的公開備份檔），
        // 頁尾字數有限，所以只講「個資只送官網」——完整的出口清單在隱私權政策。
        Text("Exercise Rewards v\(appVersion) · 非官方工具\n個資不上雲 · 個資只送 500.gov.tw · 使用統計開著時會連 Firebase")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.Colors.dim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    // 沒有「儲存到本機」了：這一頁不再修改任何東西（見檔頭說明）。

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

    /// 清除本機所有資料：刪 Keychain 個資、重置 onboarding 旗標，回初次設定。
    ///
    /// 同時也是**換帳號**的實作（見 `switchAccountButton`）：這支 App 沒有伺服器也沒有
    /// 帳號切換的概念，換身分就是把這支手機上的憑證與工作階段清乾淨後重新登入。
    /// 清除的範圍刻意**沒有**為了「換帳號比較快」而縮小——歡迎頁與免責聲明的同意紀錄
    /// 照樣重置，因為這顆按鈕同時承諾了「清除本機資料」，那個承諾優先。
    private func clearLocalData() {
        // E26 必須在**這一行**送出：後面的 `Telemetry.resetPreference()` 會把偏好關掉並重置
        // app instance ID，那之後就再也送不出去了。順序＝先記錄、再重置、最後回到未同意狀態。
        Telemetry.logEvent(.localDataClear)
        envStore.exitDemo()
        try? environment.profileStore.clear()
        TasksCache.clear()
        // 「這張券我用過了」的本機標記也算本機資料。exitDemo() 在非示範模式是 no-op，
        // 不能靠它順手清掉，所以這裡明確再清一次。走 store 而非直接寫 UserDefaults，
        // 這樣三個分頁的畫面會立刻跟著歸零。
        voucherUsage.clear()
        // 「這一期換了哪家廠商」同樣是本機紀錄，不清掉就會出現「資料都清了卻還記得
        // 你換過哪一家」，與這顆按鈕的承諾不符。
        vendorIntro.clear()
        // 遙測偏好也算「本機資料」：清除後回到預設的關閉狀態，並立刻停止收集。
        Telemetry.resetPreference()
        // 免責聲明的同意紀錄也屬於「初次設定狀態」的一部分：清除後下次開 App
        // 會再看到一次聲明。
        DisclaimerConsent.reset()
        // 舊版（1.0.0 build 4 以前）曾寫入的 HealthKit 授權旗標。功能已移除，
        // 但既有裝置上這把 key 還在，一併清掉才符合「清除本機所有資料」的承諾。
        UserDefaults.standard.removeObject(forKey: "com.megshao.exerciserewards.health.didRequestAuthorization")
        // 官方站的登入 cookie 是持久化在 App 沙盒容器、跨啟動續用的；只清 Keychain 個資
        // 並不會登出。不一併清掉就與這顆按鈕（與隱私說明）承諾的「清除本機所有資料」不符。
        let environment = environment
        Task { await environment.resetSession() }
        showCleared = true
        // 觸發回到最初的狀態（RootView 依這兩個旗標與同意版本切換）：
        // 歡迎頁 → 免責聲明 → 個資填寫。「清除本機所有資料」承諾的是回到初次設定，
        // 只重設 onboarding 會讓使用者直接落在免責聲明頁，跟第一次安裝不一樣。
        hasSeenWelcome = false
        hasCompletedOnboarding = false
    }

}

/// 唯讀的個資列：標籤 + 值（敏感欄位依 `isRevealed` 決定遮罩），另可掛一顆說明用的膠囊標籤。
///
/// **為什麼不是給 `ProfileField` 加一個 `isEditable` 旗標**：那支元件的遮罩綁在
/// 「未聚焦時遮、聚焦時顯示真值」上，而唯讀情境根本沒有聚焦這件事，旗標會讓它的
/// `showMasked` 條件變成兩套互相排斥的邏輯。它也還被 Onboarding 的填寫頁共用——
/// 那裡必須保持可輸入，不該為了這一頁的需求去動它。
///
/// 底色用 `disabledBackground`（而不是輸入框的白底）讓「不能改」在視覺上就看得出來，
/// 不必等使用者點下去才發現沒反應。
private struct ProfileValueRow: View {
    let label: String
    let value: String
    var maskedValue: String? = nil
    var badge: String? = nil
    var isRevealed: Bool = true

    /// 有遮罩字串、未展開、且真的有值時才遮；沒值一律顯示佔位符。
    private var shown: String {
        if let maskedValue, !isRevealed, !value.isEmpty { return maskedValue }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.muted)

            HStack(spacing: 8) {
                Text(shown.isEmpty ? "—" : shown)
                    .font(.system(size: 15))
                    .foregroundColor(shown.isEmpty ? Theme.Colors.dim : Theme.Colors.text)
                    // 以欄位標籤定位，與原本的輸入框一致（差別是現在是 staticText）。
                    .accessibilityIdentifier(label)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Colors.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.card)
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.disabledBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .stroke(Theme.Colors.line2, lineWidth: 1)
            )
        }
    }
}

/// 單一欄位輸入元件。所有欄位皆可直接輸入；敏感欄位在「未聚焦且已有值、且未展開」時
/// 以遮罩顯示，點一下即可聚焦編輯真實內容。文字色固定為深色，避免深色模式白底白字。
///
/// 非 private，但**目前只有 Onboarding 的個資填寫頁在用**——「我的資料」改成唯讀之後
/// 走的是 `ProfileValueRow`。這裡刻意保留可輸入的行為不動：首次設定必須能打字。
struct ProfileField: View {
    let label: String
    var sublabel: String? = nil
    @Binding var text: String
    var placeholder: String = ""
    var sensitive: Bool = false
    var isRevealed: Bool = true
    var maskedText: String? = nil
    var keyboard: UIKeyboardType = .default
    /// 讓呼叫端控制這一格的焦點（例如出生日期選完之後把焦點交給手機號碼）。
    /// 給 nil 時用元件自己的內部狀態——單獨使用的欄位不必為了焦點多宣告一個 `@FocusState`。
    var focus: FocusState<Bool>.Binding? = nil
    @FocusState private var internalFocus: Bool

    /// 實際生效的焦點狀態：有外部綁定就看外部的。
    private var isFocused: Bool { focus?.wrappedValue ?? internalFocus }

    /// 是否要蓋上遮罩（僅敏感欄位、未展開、未聚焦、且已有值時）。
    private var showMasked: Bool {
        sensitive && !isRevealed && !isFocused && !text.isEmpty
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
                textField
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
                    .stroke(isFocused ? Theme.Colors.primary : Theme.Colors.line2,
                            lineWidth: isFocused ? 1.5 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { setFocused() }
        }
    }

    /// `.focused` 只能綁在真正可聚焦的 view 上（把它加在外層容器沒有作用），
    /// 所以外部／內部兩種綁定在這裡分流。兩個分支的型別相同，不會產生 _ConditionalContent。
    @ViewBuilder
    private var textField: some View {
        let base = TextField(placeholder, text: $text)
            // 截圖用 UI 測試以欄位標籤定位輸入框（見 App/UITests/ScreenshotTests.swift）。
            .accessibilityIdentifier(label)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .font(.system(size: 15))
            .foregroundColor(Theme.Colors.text)
            .tint(Theme.Colors.primary)

        if let focus {
            base.focused(focus)
        } else {
            base.focused($internalFocus)
        }
    }

    private func setFocused() {
        if let focus {
            focus.wrappedValue = true
        } else {
            internalFocus = true
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
    /// 使用者在滾輪上按了「完成」（不是「取消」）之後呼叫，時機是 sheet **已經收掉**之後。
    /// 填寫頁用它把焦點交給下一格（見 `OnboardingView`）。
    var onCommit: (() -> Void)? = nil
    @State private var showPicker = false
    /// 這次關閉是「完成」還是「取消」。焦點不能在「完成」的 action 裡搶——
    /// 那時 sheet 還在關閉動畫中，剛設好的焦點會被它一起帶走，所以改在 `onDismiss` 才動作。
    @State private var didCommit = false

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
        .sheet(isPresented: $showPicker, onDismiss: {
            guard didCommit else { return }
            didCommit = false
            onCommit?()
        }) {
            BirthDatePickerSheet(isoDate: $isoDate, onCommit: { didCommit = true })
        }
    }
}

/// 出生日期滾輪：年／月／日三欄，可切換西元／民國。所有文字自備繁體中文，
/// 不使用系統 DatePicker，避免裝置語系是英文時整個日曆變英文。
struct BirthDatePickerSheet: View {
    @Binding var isoDate: String
    /// 按下「完成」時通知呼叫端（「取消」不會呼叫）。只記錄意圖，實際動作留給 `onDismiss`。
    var onCommit: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    enum Era: String, CaseIterable { case ad, roc }

    @State private var era: Era = .roc
    @State private var year: Int
    @State private var month: Int
    @State private var day: Int

    init(isoDate: Binding<String>, onCommit: (() -> Void)? = nil) {
        _isoDate = isoDate
        self.onCommit = onCommit
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
                    onCommit?()
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
    /// 從 Keychain 讀出來的個資。**這一頁只顯示、不寫回**（沒有 `save()`），
    /// 名稱維持 `draft` 是為了不動到遮罩相關的既有屬性名。
    @Published var draft = Profile()
    @Published var isRevealed = false
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

    // 沒有 `save()`：「我的資料」不再修改個資（見 `ProfileView` 檔頭）。
    // 個資唯一的寫入點是 Onboarding 的首次設定（`OnboardingViewModel`）。
    //
    // 連帶影響：E25 `profile_save` 事件因此不再有人送。事件定義留在 `Telemetry.swift`
    // 沒有一起刪——移掉一個事件會讓既有的 Firebase 報表斷掉，那是資料上的決定，不是程式碼上的。

    /// Keychain 的操作代碼。只用於 N10 的 `op` 參數。
    private enum StorageOp: String, Sendable {
        case save
        case load
        case clear
    }

    /// Keychain 失敗走 Crashlytics 非致命錯誤，不進 Analytics。
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

    // MARK: 唯讀顯示

    /// 「1990 年 1 月 1 日」。存的是 ISO 字串，解析不出來時回空字串（畫面顯示「—」）。
    var birthDateDisplay: String {
        BirthDate.parse(draft.birthDate).map(BirthDate.display) ?? ""
    }

    /// 「民國 79 年」。與 `BirthDateField` 顯示同一組換算，唯讀頁不該少掉這個對照。
    var birthDateRocText: String? {
        BirthDate.parse(draft.birthDate).map { BirthDate.rocYearText($0.year) }
    }

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
