import SwiftUI
import ExerciseRewardsKit

/// 我的券夾：列出已兌換（可使用）的加碼券與任務完成待兌換的期別。
/// - 已兌換 → 點「檢視券碼」開 VoucherView（每次都要 OTP 驗證後才顯示條碼）。
/// - 已兌換且使用者標記過「已使用」→ 移到最下方的「已使用」區，**不再顯示「檢視券碼」**。
///   官網沒有這個狀態，只能靠使用者自己標記（見 `VoucherUsage`）。
/// - 待兌換 → 點「去兌換」開 RedeemView（兌換的二次確認在 RedeemView 內）。
struct WalletView: View {
    @Environment(\.appEnvironment) private var environment
    /// 「已使用」標記的共用真相來源（見 `VoucherUsageStore`）。
    @EnvironmentObject private var voucherUsage: VoucherUsageStore
    /// 券碼頁關閉時要導回券夾，sheet 內容需要顯式注入（見 `TabRouter`）。
    @EnvironmentObject private var tabRouter: TabRouter
    /// 「這一期換的是哪家廠商」的本機紀錄，是「查看可兌換品項」的第一來源。
    @EnvironmentObject private var vendorIntro: VendorIntroStore
    @StateObject private var viewModel = WalletViewModel()
    @State private var voucherPeriod: TaskPeriod?
    @State private var redeemPeriod: TaskPeriod?
    /// 正在瀏覽的廠商品項頁。用一個小結構當 sheet 的 item，因為要同時帶路徑與標題。
    @State private var introTarget: WalletIntroTarget?

    var body: some View {
        VStack(spacing: 0) {
            // 5b：券夾沒有自己的快取，但重新整理失敗時上一輪的清單還在畫面上——
            // 同樣不能靜默沿用，掛 banner 說這是先前抓到的（位置比照 `TasksView`）。
            if viewModel.showsSiteHandoffBanner {
                SiteHandoffBanner(destination: .tasks) {
                    viewModel.isSiteHandoffBannerDismissed = true
                }
            }
            scrollContent
        }
        .background(Theme.Colors.background)
        .navigationTitle("我的券夾")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Telemetry.screenAppeared(.wallet) }
        .task {
            viewModel.configure(tasks: environment.tasks, redeem: environment.redeem,
                                catalog: environment.vendorCatalog)
            if viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                await viewModel.refresh()
            }
            // 券清單就位後才試備援——它需要一個可兌換的期別當來源。
            await viewModel.loadIntroFallback(rememberedIDs: Set(vendorIntro.entries.keys))
        }
        // 不需要 onDismiss 重讀標記：`voucherUsage` 是共用的 `@Published`。
        .sheet(item: $voucherPeriod) { period in
            NavigationStack { VoucherView(taskID: period.id, source: .wallet, periodIndex: period.index) }
                .environment(\.appEnvironment, environment)
                .environmentObject(voucherUsage)
                .environmentObject(tabRouter)
        }
        // 上面那句「不需要 onDismiss」只適用於券碼 sheet——它只動本機的 `voucherUsage`。
        // 兌換動的是官網端狀態（該期變成 REDEEMED），不重抓的話這一期會一直留在
        // 「可兌換」區塊，跟 `TasksView`／`HomeView` 的兌換 sheet 是同一個道理。
        .sheet(item: $redeemPeriod, onDismiss: {
            Task { await viewModel.refresh() }
        }) { period in
            NavigationStack { RedeemView(taskID: period.id, periodIndex: period.index) }
                .environment(\.appEnvironment, environment)
                // RedeemView 兌換成功後會再開 VoucherView，那一頁要 voucherUsage。
                .environmentObject(voucherUsage)
                .environmentObject(tabRouter)
                // 兌換成功時要記下選到的廠商品項頁。
                .environmentObject(vendorIntro)
        }
        // 純瀏覽的廠商品項頁，與兌換頁的「兌換品項」是同一個畫面。
        .sheet(item: $introTarget) { target in
            NavigationStack {
                VendorIntroView(introPath: target.introPath, vendorName: target.vendorName)
            }
            .environment(\.appEnvironment, environment)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("已取得的加碼券，最多可獲得 14 張")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.muted)

                if viewModel.isLoading && viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if viewModel.isSiteHandoff, viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    // 5a：官網結構對不上——「請先回首頁登入」是錯誤歸因。券夾沒有單一 taskID，
                    // 交接到任務清單頁，官網那裡每一期的券都點得到。
                    SiteHandoffState(destination: .tasks) {
                        await viewModel.refresh()
                    }
                } else if let error = viewModel.errorMessage,
                          viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    emptyOrError(icon: "exclamationmark.triangle.fill", text: error, showRetry: true)
                } else if viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    emptyOrError(icon: "ticket",
                                 text: "目前沒有加碼券。\n完成任務並兌換後，加碼券會出現在這裡。",
                                 showRetry: false)
                } else {
                    if !viewModel.redeemable.isEmpty {
                        sectionTitle("可兌換")
                        ForEach(viewModel.redeemable, id: \.index) { period in
                            redeemableCard(period)
                        }
                    }
                    let unused = viewModel.redeemed.filter { !voucherUsage.isUsed($0) }
                    let used = viewModel.redeemed.filter { voucherUsage.isUsed($0) }
                    if !unused.isEmpty {
                        sectionTitle("可使用的加碼券")
                        ForEach(unused, id: \.index) { period in
                            voucherCard(period)
                        }
                    }
                    if !used.isEmpty {
                        sectionTitle("已使用")
                        ForEach(used, id: \.index) { period in
                            usedVoucherCard(period)
                        }
                    }
                }
            }
            .padding(20)
        }
        .refreshable { await viewModel.refresh() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.displayFont(16, weight: .bold))
            .padding(.top, 4)
    }

    /// 已兌換的券卡：可檢視券碼（走 OTP）。
    private func voucherCard(_ period: TaskPeriod) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill").foregroundStyle(Theme.Colors.primary)
                    Text("第 \(period.index) 期加碼券")
                        .font(Theme.displayFont(15, weight: .bold))
                }
                Spacer()
                StatusBadge(text: "已兌換",
                            foreground: Theme.Colors.dim,
                            background: Color(hex: 0xEEF0F3))
            }
            Text("\(period.startDate) ~ \(period.endDate)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.muted)
            // 官網卡片上的「兌換內容：通路／品項」。官網原文，只顯示、不進遙測。
            if let summary = period.voucherSummary {
                Text(summary)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 「查看可兌換品項」擺在結帳鈕上方：先看能換什麼、再決定要不要走簡訊驗證。
            // 只有真的拿得到廠商品項頁時才出現（本機紀錄或備援對應表，見 `introTarget(for:)`），
            // 與 `RedeemView` 對 `introPath == nil` 的處理一致——沒有頁面就沒有按鈕。
            if let target = viewModel.introTarget(for: period,
                                                  remembered: vendorIntro.entry(for: period)) {
                Button {
                    introTarget = WalletIntroTarget(introPath: target.path,
                                                    vendorName: target.vendorName)
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("查看可兌換品項")
                    }
                }
                .accessibilityIdentifier("walletViewIntro")
                .buttonStyle(.huihanSecondary)
            }

            // 名稱講清楚這顆按鈕是「到櫃檯結帳時要按的那顆」——它會走一次簡訊驗證後
            // 出示條碼，不是單純檢視。與上面的「查看可兌換品項」（純瀏覽）刻意分得很開。
            Button {
                voucherPeriod = period
            } label: {
                HStack {
                    Image(systemName: "barcode.viewfinder")
                    Text("顯示加碼券條碼結帳")
                }
            }
            .accessibilityIdentifier("walletShowBarcode")
            .buttonStyle(.huihanPrimary)

            Button {
                toggleUsed(period)
            } label: {
                Text("標記為已使用")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.muted)
            }
            .accessibilityIdentifier("walletMarkUsed")
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 已標記為使用完畢的券：整張轉灰、**不提供「檢視券碼」**，只留「還原」。
    /// 標記是本機備忘，所以卡片上要講清楚它不影響官網。
    private func usedVoucherCard(_ period: TaskPeriod) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.dim)
                    Text("第 \(period.index) 期加碼券")
                        .font(Theme.displayFont(15, weight: .bold))
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer()
                StatusBadge(text: "已使用",
                            foreground: Theme.Colors.dim,
                            background: Color(hex: 0xEEF0F3))
            }
            if let summary = period.voucherSummary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("你在 App 內標記為已使用（本機紀錄顯示，使用與否以條碼能否使用為主）。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.Colors.dim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                toggleUsed(period)
            } label: {
                Text("還原成未使用")
            }
            .accessibilityIdentifier("walletRestoreUsed")
            .buttonStyle(.huihanSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: 0xFAFBFC))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(Theme.Colors.line, lineWidth: 1)
        )
    }

    /// 任務完成待兌換：去兌換。
    private func redeemableCard(_ period: TaskPeriod) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("第 \(period.index) 期")
                    .font(Theme.displayFont(15, weight: .bold))
                Spacer()
                StatusBadge(text: "可兌換",
                            foreground: .white,
                            background: Theme.Colors.success)
            }
            Text("任務完成 · 尚未兌換")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.muted)
            Button {
                // 兌換本身在 RedeemView 有「確認兌換」二次確認，這裡不再多一道驗證。
                redeemPeriod = period
            } label: {
                HStack {
                    Image(systemName: "gift.fill")
                    Text("去兌換")
                }
            }
            .buttonStyle(.huihanPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 切換「已使用」標記。寫進共用 store，三個分頁會一起重畫。
    private func toggleUsed(_ period: TaskPeriod) {
        let used = voucherUsage.toggle(id: period.id)
        // E29：只送方向，不帶期別 UUID／期數／兌換內容。
        Telemetry.logEvent(.voucherMarkUsed(used: used))
    }

    private func emptyOrError(icon: String, text: String, showRetry: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Theme.Colors.dim)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
            if showRetry {
                Button { Task { await viewModel.refresh() } } label: { Text("重新載入") }
                    .buttonStyle(.huihanSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var redeemed: [TaskPeriod] = []
    @Published var redeemable: [TaskPeriod] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// 這一次抓取是否撞上「官網結構對不上」（`SiteHandoff.shouldHandoff(_:)`）。
    /// 與 `errorMessage` 互斥：走接手畫面的錯誤不再套「請先回首頁登入」那句。
    @Published private(set) var isSiteHandoff = false
    /// 使用者關掉了頂端 banner。下一次抓取再失敗時要重新出現，所以每次 `refresh` 開頭歸零。
    @Published var isSiteHandoffBannerDismissed = false

    /// 畫面上還有上一輪的清單、又撞上改版、而且使用者還沒關掉——三個條件都成立才掛 banner。
    var showsSiteHandoffBanner: Bool {
        isSiteHandoff && !(redeemed.isEmpty && redeemable.isEmpty) && !isSiteHandoffBannerDismissed
    }

    /// 備援用的「廠商名 → introPath」對應表（見 `loadIntroFallback`）。
    /// 空字典有兩種意思：還沒抓、或抓了但沒有可兌換期別可借。兩者對畫面的效果相同
    /// （沒有路徑就不顯示按鈕），所以不特別區分。
    @Published private(set) var introByVendorName: [String: String] = [:]

    private var tasks: TasksServicing?
    private var redeem: RedeemServicing?
    private var catalog: VendorCatalogFetching?
    /// 一個 App session 只嘗試一次備援抓取。失敗（或沒有可借的期別）不重試——
    /// 這只是為了長出一顆瀏覽用的按鈕，不值得每次下拉都多打一次官網。
    private var didAttemptIntroFallback = false

    func configure(tasks: TasksServicing, redeem: RedeemServicing,
                   catalog: VendorCatalogFetching) {
        guard self.tasks == nil else { return }
        self.tasks = tasks
        self.redeem = redeem
        self.catalog = catalog
    }

    /// 已兌換期別的廠商品項頁路徑。
    ///
    /// 先看本機紀錄（`VendorIntroStore`，在 App 內兌換時記下的，精確且免費），
    /// 沒有才退到備援對應表（從別的期別借來，靠官網原文的廠商名比對）。
    /// 兩條都沒有就回 nil，畫面上那顆按鈕就不出現——與 `RedeemView` 對
    /// `introPath == nil` 的處理一致。
    func introTarget(for period: TaskPeriod,
                     remembered: VendorIntroMemory.Entry?) -> (path: String, vendorName: String)? {
        if let remembered {
            return (remembered.introPath, remembered.vendorName)
        }
        guard let vendorName = Self.matchVendorName(in: period.voucherSummary,
                                                    knownNames: introByVendorName.keys),
              let path = introByVendorName[vendorName] else { return nil }
        return (path, vendorName)
    }

    /// 還有沒有「已兌換但補不到品項頁」的券。有才值得去抓離線備份。
    private func needsBackup(rememberedIDs: Set<String>) -> Bool {
        redeemed.contains { period in
            guard !rememberedIDs.contains(period.id) else { return false }
            return Self.matchVendorName(in: period.voucherSummary,
                                        knownNames: introByVendorName.keys) == nil
        }
    }

    /// 從官網原文「通路／品項」對出通路名。
    ///
    /// **不可以用「切第一個『／』」**：實地擷取的兌換頁上有一家廠商就叫
    /// 「萬家福／樂家康」——廠商名本身含分隔符，切出來會變成「萬家福」而永遠對不上。
    /// 所以改成拿已知的廠商名去比對前綴。
    ///
    /// 長名優先：短名先命中會把長名吃掉（例如「萬家福」若也單獨存在，
    /// 就會搶走「萬家福／樂家康」的那一列）。
    ///
    /// 對不出來就回 nil——寧可不顯示按鈕，也不要開錯廠商的品項頁。
    static func matchVendorName(in summary: String?, knownNames: some Collection<String>) -> String? {
        guard let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return nil }
        return knownNames
            .filter { !$0.isEmpty && summary.hasPrefix($0) }
            .max { $0.count < $1.count }
    }

    /// 備援：借一個**還可兌換**的期別去載入兌換清單，把「廠商名 → introPath」記下來。
    ///
    /// 為什麼借得成立：`intro/vendor-*.html` 是每家廠商的靜態頁，與期別無關——
    /// 同一家廠商在哪一期的兌換清單上都指向同一頁。而已兌換的期別在官網已經沒有
    /// 兌換頁可以解析（見 `VendorIntroMemory` 檔頭）。
    ///
    /// 失敗一律安靜結束：這是加值功能，不該讓券夾冒出錯誤訊息或走接手畫面。
    /// `rememberedIDs`＝已有本機紀錄的期別（`VendorIntroStore` 的鍵）。
    /// 用來判斷第三層還有沒有必要連線，見下方註解。
    func loadIntroFallback(rememberedIDs: Set<String>) async {
        guard !didAttemptIntroFallback else { return }
        didAttemptIntroFallback = true

        // 第二層：借一個**還可兌換**的期別去載入兌換清單，把「廠商名 → introPath」記下來。
        // 借得成立是因為 intro 頁是每家廠商的靜態頁、與期別無關；已兌換的期別在官網
        // 已經沒有兌換頁可解析（見 `VendorIntroMemory` 檔頭）。
        if let redeem, let donor = redeemable.first(where: { !$0.id.isEmpty }) {
            do {
                let options = try await redeem.options(taskID: donor.id)
                var map: [String: String] = [:]
                for option in options {
                    guard let path = option.introPath, VendorIntroPath.isValid(path) else { continue }
                    // 同名廠商只留第一個；官網同一家不會指向兩頁。
                    if map[option.vendorName] == nil { map[option.vendorName] = path }
                }
                introByVendorName = map
            } catch {
                // 安靜結束：券夾的主要內容（券清單）已經在畫面上了，這只是加值功能。
            }
        }

        // 第三層：官網借不到（14 期全兌換完、沒有可兌換期別、或上面那次抓取失敗）
        // 就用離線備份補齊。只補**還沒有**的廠商——官網當下給的路徑永遠優先於快照。
        //
        // **只有真的補不到才連線。** 這是全 App 唯一離開 500.gov.tw 的請求，
        // 而在 App 內兌換過的期別本來就有本機紀錄、根本不需要它。無條件連線等於
        // 讓多數使用者為了一個用不到的備份，白白對第三方主機曝露一次 IP。
        guard let catalog, needsBackup(rememberedIDs: rememberedIDs) else { return }
        do {
            let backup = try await catalog.fetch()
            for vendor in backup.vendors where introByVendorName[vendor.vendorName] == nil {
                introByVendorName[vendor.vendorName] = vendor.introPath
            }
        } catch {
            // 同上，安靜結束。
        }
    }

    func refresh() async {
        guard let tasks else { return }
        let hadCache = !redeemed.isEmpty || !redeemable.isEmpty
        isLoading = true
        errorMessage = nil
        // 每次抓取都是一次新的判斷；banner 的 dismissed 一起歸零，這次再失敗才會重新出現。
        isSiteHandoff = false
        isSiteHandoffBannerDismissed = false
        defer { isLoading = false }
        let startedAt = DispatchTime.now()
        do {
            let periods = try await tasks.fetchTasks()
            redeemed = periods.filter { $0.state == .redeemed }
            redeemable = periods.filter { $0.state == .redeemable }
            TasksTelemetry.reportSuccess(source: .wallet, periods: periods,
                                         highlighted: HomeViewModel.highlightedPeriod(in: periods),
                                         hadCache: hadCache, startedAt: startedAt)
        } catch {
            TasksTelemetry.reportFailure(error, source: .wallet, hadCache: hadCache,
                                         startedAt: startedAt, sessionProbable: true)
            // 官網結構對不上走接手畫面（有清單就掛 banner）；其他錯誤才是原本那句。
            if SiteHandoff.shouldHandoff(error) {
                isSiteHandoff = true
            } else {
                errorMessage = "無法載入券夾，請先回首頁登入，或稍後重試。"
            }
        }
    }
}

/// 券夾要開啟的廠商品項頁。`.sheet(item:)` 需要 `Identifiable`，而這裡要同時帶
/// 路徑與標題，所以包成一個小結構而不是直接用字串。
struct WalletIntroTarget: Identifiable, Equatable {
    let introPath: String
    let vendorName: String
    var id: String { introPath }
}
